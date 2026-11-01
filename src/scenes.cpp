#include "scenes.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <iostream>
#include <span>
#include <string>
#include <string_view>

#include "avela_clock/local_time.hpp"
#include "avela_firmware_update/model/firmware_update_state.hpp"
#include "avela_network/model/wifi_status.hpp"
#include "avela_radio/model/default_station.hpp"
#include "avela_radio/model/playback_state.hpp"
#include "avela_radio/model/radio_model.hpp"
#include "avela_radio/model/station.hpp"
#include "avela_radio/ui/thumbnail.hpp"
#include "avela_ui/canvas.hpp"
#include "memory_display.hpp"
#include "sdkconfig.h"
#if CONFIG_AVELA_WEATHER
#include "avela_weather/model/weather_report.hpp"
#endif

// The skin's entry header (`<skin component>/skin.hpp`, naming avela::Skin), set by the toolbox's CMakeLists.txt.
#include AVELA_SKIN_HEADER

namespace skin_toolbox {

namespace {

using avela::FirmwareUpdateState;
using avela::LocalTime;
using avela::PlaybackState;
using avela::Skin;
using avela::WifiStatus;

constexpr LocalTime evening{.m_year = 2026,
                            .m_month = 10,
                            .m_day = 24,
                            .m_weekday = 6,
                            .m_hour = 18,
                            .m_minute = 42,
                            .m_second = 0,
                            .m_synchronised = true};
constexpr LocalTime clock_not_set{};  // power-on, before SNTP: January 1970, not synchronised

constexpr int strong_signal_bars = 3;
constexpr int volume = 64;
constexpr int settling_frames = 24;  // frames of the same spectrum before the picture: the bars have reached it
constexpr std::string_view host_name = "avela";  // the default (menuconfig: Avela network)

// A spectrum frame like music: strong lows, a bump in the mids, falling highs.
std::array<uint8_t, avela::RadioModel::spectrum_band_count> music_spectrum()
{
    std::array<uint8_t, avela::RadioModel::spectrum_band_count> levels{};
    for (std::size_t band = 0; band < levels.size(); ++band) {
        const double position = static_cast<double>(band) / static_cast<double>(levels.size() - 1);
        const double lows = 0.85 * std::exp(-3.0 * position);
        const double mids = 0.35 * std::exp(-40.0 * (position - 0.45) * (position - 0.45));
        const double level = std::min(1.0, lows + mids);
        levels.at(band) = static_cast<uint8_t>(level * avela::RadioModel::spectrum_level_max);
    }
    return levels;
}

struct Rendering {
    MemoryDisplay& m_display;
    const Skin::Surface& m_surface;
    const std::filesystem::path& m_output;
    int m_scale;
    bool m_written_all = true;

    // playing, state: the radio's, as in player(); the other screens show it playing
    void header(const LocalTime& time, WifiStatus status, int bars, bool playing = true,
                PlaybackState state = PlaybackState::playing) const
    {
        Skin::HeaderSkin header{m_surface};
        header.set_time(time);
        header.set_playback(playing, state);
        header.set_volume(volume);
        header.set_wifi(status, bars);
        header.draw();
    }

    void save(std::string_view scene)
    {
        const std::filesystem::path file = m_output / (std::string{scene} + ".png");
        if (const std::string error = m_display.write_png(file, m_scale); !error.empty()) {
            std::cerr << "avela_skin_render: " << file.string() << ": " << error << "\n";
            m_written_all = false;
            return;
        }
        std::cout << file.string() << "\n";
    }
};

// playing: the user's request; state: what the radio does about it (the stream and the spectrum only while it plays)
void player(Rendering& rendering, std::string_view scene, bool playing, PlaybackState state, const LocalTime& time,
            WifiStatus status)
{
    const bool sounding = state == PlaybackState::playing;
    const auto spectrum = sounding ? music_spectrum() : std::array<uint8_t, avela::RadioModel::spectrum_band_count>{};
    rendering.header(time, status, status == WifiStatus::connected ? strong_signal_bars : 0, playing, state);
    Skin::PlayerSkin skin{rendering.m_surface};
    skin.set_station("Radio Paradise", "Eclectic / Rock");
    skin.set_thumbnail(avela::Thumbnail{.m_monogram = "RP"});
    skin.set_stream(sounding ? "Pink Floyd - Time" : "", sounding ? "128 kbit/s MP3" : "");
    skin.set_playing(playing);
    skin.set_playback_state(state);
    for (int frame = 0; frame < settling_frames; ++frame) {  // the bars move towards the levels frame by frame
        skin.set_spectrum(spectrum);
    }
    skin.draw();
    rendering.save(scene);
}

void stations(Rendering& rendering)
{
    rendering.header(evening, WifiStatus::connected, strong_signal_bars);
    Skin::StationsSkin skin{rendering.m_surface};
    // the default stations as the radio lists them (their monograms are the radio's, written out here)
    constexpr std::array monograms{"SL", "RP", "FJ", "RSJ", "GS", "LH"};
    static_assert(monograms.size() == avela::default_stations.size());
    std::array<avela::Station, avela::default_stations.size()> stations{};
    for (std::size_t index = 0; index < stations.size(); ++index) {
        stations.at(index) = avela::Station{.m_name = avela::default_stations.at(index).m_name,
                                            .m_monogram = monograms.at(index),
                                            .m_genre = avela::default_stations.at(index).m_genre};
    }
    skin.set_selection(stations, 2, 1);  // FIP Jazz selected, Radio Paradise playing
    skin.draw();
    rendering.save("stations");
}

void info(Rendering& rendering, std::string_view scene, WifiStatus status)
{
    const bool connected = status == WifiStatus::connected;
    rendering.header(evening, status, connected ? strong_signal_bars : 0);
    Skin::InfoSkin skin{rendering.m_surface};
    constexpr int signal_dbm = -58;
    skin.set_network(status, connected ? "HomeNetwork" : "", connected ? "192.168.1.42" : "", host_name,
                     connected ? signal_dbm : 0);
    constexpr std::size_t free_kilobytes = 142;
    constexpr std::size_t lowest_free_kilobytes = 128;
    constexpr std::size_t total_kilobytes = 320;
    skin.set_memory(free_kilobytes, lowest_free_kilobytes, total_kilobytes);
    skin.set_firmware("0.1.0", std::chrono::hours{3} + std::chrono::minutes{14});
    skin.draw();
    rendering.save(scene);
}

void wifi_setup(Rendering& rendering, std::string_view scene, bool page_up)
{
    rendering.header(evening, WifiStatus::not_configured, 0);
    Skin::WifiSetupSkin skin{rendering.m_surface};
    skin.set_saved_network(WifiStatus::not_configured, "");
    skin.set_setup_network("Avela-setup", "avela_657", "WIFI:T:WPA;S:Avela-setup;P:avela_657;;");
    skin.set_setup_page(page_up, page_up ? "192.168.4.1" : "");
    skin.draw();
    rendering.save(scene);
}

void firmware_update(Rendering& rendering, std::string_view scene, FirmwareUpdateState state, int percent,
                     std::string_view failure)
{
    rendering.header(evening, WifiStatus::connected, 0);
    Skin::FirmwareUpdateSkin skin{rendering.m_surface};
    skin.set_running_version("0.1.0");
    skin.set_update_page("http://avela.local/update", "http://192.168.1.42/update");
    skin.set_progress(state, percent, failure);
    skin.draw();
    rendering.save(scene);
}

// the screens main offers on the tiles (avela_firmware main/screens.hpp: TilesScreen::screens)
constexpr std::array tile_screens{
    avela::ScreenId::player,
#if CONFIG_AVELA_WEATHER
    avela::ScreenId::weather,
#endif
    avela::ScreenId::info,
};

void tiles(Rendering& rendering)
{
    rendering.header(evening, WifiStatus::connected, strong_signal_bars);
    Skin::TilesSkin skin{rendering.m_surface};
    skin.set_tiles(tile_screens, 0);  // on Radio, as Back from the player opens them
    skin.draw();
    rendering.save("tiles");
}

#if CONFIG_AVELA_WEATHER
using avela::ForecastDay;
using avela::WeatherCondition;
using avela::WeatherReport;
using avela::WeatherStatus;

WeatherReport sample_weather(bool daytime)
{
    WeatherReport report{};
    report.m_status = WeatherStatus::ready;
    report.m_place.append("Warsaw");
    report.m_has_values = true;
    report.m_daytime = daytime;
    // between them the two samples show every condition, and the moon
    report.m_temperature = daytime ? 14 : 6;
    report.m_feels_like = daytime ? 12 : 3;  
    report.m_humidity_percent = daytime ? 62 : 91;
    report.m_wind_speed = daytime ? 14 : 6;  
    report.m_high = 17;                      
    report.m_low = 9;                        
    report.m_condition = daytime ? WeatherCondition::partly_cloudy : WeatherCondition::fog;
    report.m_forecast = daytime ? std::array{ForecastDay{.m_weekday = 0, .m_condition = WeatherCondition::clear,
                                                         .m_high = 16, .m_low = 8},
                                             ForecastDay{.m_weekday = 1, .m_condition = WeatherCondition::rain,
                                                         .m_high = 13, .m_low = 7},
                                             ForecastDay{.m_weekday = 2, .m_condition = WeatherCondition::snow,
                                                         .m_high = 2, .m_low = -3},
                                             ForecastDay{.m_weekday = 3, .m_condition = WeatherCondition::thunderstorm,
                                                         .m_high = 21, .m_low = 14}}
                                : std::array{ForecastDay{.m_weekday = 0, .m_condition = WeatherCondition::cloudy,
                                                         .m_high = 11, .m_low = 5},
                                             ForecastDay{.m_weekday = 1, .m_condition = WeatherCondition::drizzle,
                                                         .m_high = 10, .m_low = 4},
                                             ForecastDay{.m_weekday = 2, .m_condition = WeatherCondition::clear,
                                                         .m_high = 12, .m_low = 2},
                                             ForecastDay{.m_weekday = 3, .m_condition = WeatherCondition::partly_cloudy,
                                                         .m_high = 13, .m_low = 6}};
    report.m_revision = 1;
    return report;
}

void weather(Rendering& rendering, std::string_view scene, const WeatherReport& report)
{
    rendering.header(evening, WifiStatus::connected, strong_signal_bars);
    Skin::WeatherSkin skin{rendering.m_surface};
    skin.set_weather(report);
    skin.set_host_name(host_name);
    skin.draw();
    rendering.save(scene);
}

WeatherReport weather_without_values(WeatherStatus status)
{
    WeatherReport report{};
    report.m_status = status;
    report.m_place.append(status == WeatherStatus::not_configured ? "" : "Atlantis");
    report.m_revision = 1;
    return report;
}
#endif

}  // namespace

//--------------------------------------------------------------------------------------------------

bool render_scenes(const std::filesystem::path& output, int scale)
{
    static MemoryDisplay display{Skin::screen.m_width, Skin::screen.m_height};
    static avela::BandBuffers<Skin::screen.m_width> band_buffers;
    static avela::Canvas canvas{display, band_buffers};
    static Skin::Fonts fonts;

    display.init();
    fonts.load();
    const Skin::Surface surface{.m_canvas = canvas, .m_fonts = fonts};
    Rendering rendering{.m_display = display, .m_surface = surface, .m_output = output, .m_scale = scale};

    player(rendering, "player_playing", true, PlaybackState::playing, evening, WifiStatus::connected);
    player(rendering, "player_paused", false, PlaybackState::stopped, evening, WifiStatus::connected);
    player(rendering, "player_connecting", true, PlaybackState::connecting, evening, WifiStatus::connected);
    player(rendering, "player_failed", true, PlaybackState::failed, evening, WifiStatus::connected);
    player(rendering, "player_clock_not_set", true, PlaybackState::stopped, clock_not_set, WifiStatus::connecting);
    stations(rendering);
    info(rendering, "info_connected", WifiStatus::connected);
    info(rendering, "info_not_configured", WifiStatus::not_configured);
    wifi_setup(rendering, "wifi_setup_starting", false);
    wifi_setup(rendering, "wifi_setup_up", true);
    firmware_update(rendering, "firmware_update_waiting", FirmwareUpdateState::waiting, 0, "");
    firmware_update(rendering, "firmware_update_receiving", FirmwareUpdateState::receiving, 42, "");
    firmware_update(rendering, "firmware_update_restarting", FirmwareUpdateState::restarting, 100, "");
    firmware_update(rendering, "firmware_update_failed", FirmwareUpdateState::failed, 0,
                    "This isn't an Avela firmware.");
    tiles(rendering);
#if CONFIG_AVELA_WEATHER
    weather(rendering, "weather_day", sample_weather(true));
    weather(rendering, "weather_night", sample_weather(false));
    weather(rendering, "weather_not_configured", weather_without_values(WeatherStatus::not_configured));
    weather(rendering, "weather_place_not_found", weather_without_values(WeatherStatus::place_not_found));
#endif
    return rendering.m_written_all;
}

}  // namespace skin_toolbox
