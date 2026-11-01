# avela_skin_toolbox: builds one skin, from its own sources, together with the toolbox's scenes into
# avela_skin_render, which writes a PNG per scene. render.sh configures it; run by hand:
#   tools/configure_skin.py --skin <skin> --components <components> --out-dir <build>/config
#   cmake -S . -B <build> -DSKIN_DIR=<skin> -DCOMPONENTS_DIR=<components> -DCONFIG_DIR=<build>/config
#         [-DLOVYANGFX_DIR=<LovyanGFX checkout>]
cmake_minimum_required(VERSION 3.24)
project(avela_skin_toolbox C CXX ASM)

# The toolbox's version: X.Y.Z on a release, X.Y.Z-dev on devel between releases (cicd/release.sh sets it).
set(TOOLBOX_VERSION "1.0.0")

# The skin API versions the scenes (src/scenes.cpp) are written for: a pip-style specifier like the firmware's
# supported_skin_api_versions. Raise it with the scenes when the firmware's skin API changes.
set(supported_skin_api_versions ">=0.1.0")

set(SKIN_DIR "" CACHE PATH "the skin component's folder (avela_skin_<name>)")
set(COMPONENTS_DIR "" CACHE PATH "the folder holding the components the skin requires (e.g. the firmware's components/)")
set(CONFIG_DIR "" CACHE PATH "tools/configure_skin.py's output for this skin")
set(LOVYANGFX_DIR "" CACHE PATH "a LovyanGFX checkout; empty: fetch the release the firmware pins")
foreach(required IN ITEMS SKIN_DIR COMPONENTS_DIR CONFIG_DIR)
    if(NOT ${required})
        message(FATAL_ERROR "set ${required} (render.sh does)")
    endif()
endforeach()
get_filename_component(SKIN_DIR "${SKIN_DIR}" ABSOLUTE)
get_filename_component(COMPONENTS_DIR "${COMPONENTS_DIR}" ABSOLUTE)
get_filename_component(CONFIG_DIR "${CONFIG_DIR}" ABSOLUTE)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS ON)  # gnu++23, like ESP-IDF's gnu++2b

include(cmake/skin_component.cmake)
include(cmake/skin_api_version.cmake)
include(cmake/lovyangfx.cmake)

include("${CONFIG_DIR}/sdkconfig.cmake")  # CONFIG_* for the skin's CMakeLists.txt
include("${CONFIG_DIR}/skin.cmake")       # SKIN_COMPONENT, SKIN_API_VERSION, SKIN_TITLE
avela_check_skin_api_version("${SKIN_COMPONENT}" "${SKIN_API_VERSION}" "${supported_skin_api_versions}")
message(STATUS "skin ${SKIN_COMPONENT} (\"${SKIN_TITLE}\"), skin API ${SKIN_API_VERSION}, screen ${CONFIG_AVELA_SCREEN_NAME}")

# The skin, as its CMakeLists.txt describes it
avela_read_component("${SKIN_DIR}" skin)
if(NOT skin_SOURCES)
    message(FATAL_ERROR "the skin registers no sources: is it the chosen skin (its CONFIG_AVELA_SKIN_<NAME>)?")
endif()
avela_embed_files(skin_embedded ${skin_EMBED_FILES})
avela_embed_files(skin_embedded_text TEXT ${skin_EMBED_TXTFILES})

# The headers of what the skin requires (the skin API: view concepts, value types, avela_ui); LovyanGFX is ours.
set(skin_requires ${skin_REQUIRES} ${skin_PRIV_REQUIRES})
list(REMOVE_ITEM skin_requires lovyan03__lovyangfx)
foreach(name IN LISTS skin_requires)
    if(NOT EXISTS "${COMPONENTS_DIR}/${name}/CMakeLists.txt")
        message(FATAL_ERROR "the skin requires ${name}, which is not in ${COMPONENTS_DIR}")
    endif()
endforeach()
avela_skin_api_include_directories("${COMPONENTS_DIR}" skin_api_include_directories ${skin_requires})

add_library(skin STATIC ${skin_SOURCES} ${skin_embedded} ${skin_embedded_text})
target_include_directories(skin PUBLIC ${skin_INCLUDE_DIRS} ${skin_api_include_directories} "${CONFIG_DIR}"
                           PRIVATE ${skin_PRIV_INCLUDE_DIRS})
target_link_libraries(skin PUBLIC lovyangfx)

add_executable(avela_skin_render src/main.cpp src/scenes.cpp src/memory_display.cpp)
target_compile_definitions(avela_skin_render PRIVATE AVELA_SKIN_HEADER="${SKIN_COMPONENT}/skin.hpp")
target_compile_options(avela_skin_render PRIVATE -Wall -Wextra)
target_link_libraries(avela_skin_render PRIVATE skin)
