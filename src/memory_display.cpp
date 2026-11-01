#include "memory_display.hpp"

#include <cstdlib>
#include <fstream>

namespace skin_toolbox {

//--------------------------------------------------------------------------------------------------

MemoryPanel::MemoryPanel(int width, int height)
    : m_pixels_(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * bytes_per_pixel),
      m_lines_(static_cast<std::size_t>(height))
{
    auto panel_config = config();
    panel_config.memory_width = static_cast<uint16_t>(width);
    panel_config.panel_width = static_cast<uint16_t>(width);
    panel_config.memory_height = static_cast<uint16_t>(height);
    panel_config.panel_height = static_cast<uint16_t>(height);
    config(panel_config);

    for (std::size_t line = 0; line < m_lines_.size(); ++line) {
        m_lines_[line] = &m_pixels_[line * static_cast<std::size_t>(width) * bytes_per_pixel];
    }
    _lines_buffer = m_lines_.data();
    setColorDepth(lgfx::rgb565_2Byte);
}

//--------------------------------------------------------------------------------------------------

bool MemoryPanel::init(bool /*use_reset*/)
{
    _range_mod.top = INT16_MAX;
    _range_mod.left = INT16_MAX;
    _range_mod.right = 0;
    _range_mod.bottom = 0;
    setRotation(_rotation);
    return true;
}

//--------------------------------------------------------------------------------------------------

MemoryDisplay::MemoryDisplay(int width, int height) : m_panel_(width, height)
{
    setPanel(&m_panel_);
}

//--------------------------------------------------------------------------------------------------

std::string MemoryDisplay::write_png(const std::filesystem::path& file, int scale)
{
    lgfx::LGFX_Sprite image;
    image.setColorDepth(lgfx::rgb888_3Byte);
    if (image.createSprite(width() * scale, height() * scale) == nullptr) {
        return "no memory for the image";
    }
    for (int y = 0; y < height(); ++y) {
        for (int x = 0; x < width(); ++x) {
            image.fillRect(x * scale, y * scale, scale, scale, readPixel(x, y));
        }
    }
    std::size_t length = 0;
    // the area must be given: LovyanGFX's defaults (0 x 0) mean "nothing"
    void* png = image.createPng(&length, 0, 0, image.width(), image.height());
    if (png == nullptr) {
        return "the PNG encoder failed";
    }
    std::ofstream output(file, std::ios::binary);
    output.write(static_cast<const char*>(png), static_cast<std::streamsize>(length));
    std::free(png);  // NOLINT(cppcoreguidelines-no-malloc): LovyanGFX's PNG encoder allocates with malloc
    if (!output.good()) {
        return "can't write the file";
    }
    return {};
}

}  // namespace skin_toolbox
