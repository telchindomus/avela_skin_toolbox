// avela_skin_render: renders every sample scene of the skin it was built with (render.sh configures one build per
// skin) into PNG files.
//   avela_skin_render --out <folder> [--scale <n>]
#include <charconv>
#include <filesystem>
#include <iostream>
#include <span>
#include <string_view>

#include "scenes.hpp"

namespace {

constexpr int maximum_scale = 8;

void usage()
{
    std::cerr << "usage: avela_skin_render --out <folder> [--scale <1.." << maximum_scale << ">]\n";
}

}  // namespace

int main(int argument_count, char** argument_values)
{
    const std::span arguments{argument_values, static_cast<std::size_t>(argument_count)};
    std::filesystem::path output;
    int scale = 1;
    for (std::size_t index = 1; index + 1 < arguments.size(); index += 2) {
        const std::string_view name = arguments[index];
        const std::string_view value = arguments[index + 1];
        if (name == "--out") {
            output = value;
        } else if (name == "--scale") {
            const auto result = std::from_chars(value.data(), value.data() + value.size(), scale);
            if (result.ec != std::errc{} || scale < 1 || scale > maximum_scale) {
                usage();
                return 2;
            }
        } else {
            usage();
            return 2;
        }
    }
    if (output.empty() || arguments.size() % 2 == 0) {
        usage();
        return 2;
    }
    std::filesystem::create_directories(output);
    return skin_toolbox::render_scenes(output, scale) ? 0 : 1;
}
