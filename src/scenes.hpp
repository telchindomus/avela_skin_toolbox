// The sample scenes: every screen of the skin API with sample values, each drawn the way the firmware draws it (the
// header skin above, the screen's page skin below; setters first, then draw()) and written as <scene>.png. The scenes
// cover the skin API versions in supported_skin_api_versions (CMakeLists.txt); a new page skin needs a new scene.
#pragma once

#include <filesystem>

namespace skin_toolbox {

// Renders every scene into `output`; false (with a message on stderr) if a file can't be written.
bool render_scenes(const std::filesystem::path& output, int scale);

}  // namespace skin_toolbox
