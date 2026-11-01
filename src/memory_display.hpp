// A display that exists only in memory: what the board's panel would show, at the skin's screen size, read back as
// pixels afterwards. A LovyanGFX device like the board's (the skin's canvas pushes its bands to it the same way), on a
// frame buffer panel with no bus, no window and no /dev/fb.
#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

#include <LovyanGFX.hpp>
#include <lgfx/v1/panel/Panel_FrameBufferBase.hpp>  // not part of LovyanGFX.hpp

namespace skin_toolbox {

class MemoryPanel : public lgfx::Panel_FrameBufferBase {
public:
    MemoryPanel(int width, int height);

    // Panel_FrameBufferBase::init would start a bus (Panel_Device::init); a panel in memory has none.
    bool init(bool use_reset) override;

private:
    static constexpr int bytes_per_pixel = 2;  // RGB565, the board's panel format

    std::vector<uint8_t> m_pixels_;
    std::vector<uint8_t*> m_lines_;
};

class MemoryDisplay : public lgfx::LGFX_Device {
public:
    MemoryDisplay(int width, int height);

    // What the display shows now, `scale` times bigger (each pixel a scale x scale square), as a PNG file; empty, or
    // what went wrong.
    std::string write_png(const std::filesystem::path& file, int scale);

private:
    MemoryPanel m_panel_;
};

}  // namespace skin_toolbox
