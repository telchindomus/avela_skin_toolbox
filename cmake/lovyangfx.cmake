# LovyanGFX for the PC, headless: the framebuffer platform (LGFX_LINUX_FB, which also stops LovyanGFX from picking
# SDL when its headers happen to be installed); the toolbox draws into its own in-memory panel, never /dev/fb.
# LOVYANGFX_DIR: a LovyanGFX checkout (e.g. the firmware's managed_components/lovyan03__lovyangfx); without it the
# same release the firmware pins is fetched.
set(LOVYANGFX_VERSION "1.2.33")  # the firmware's avela_hal/idf_component.yml pins this tag

if(NOT LOVYANGFX_DIR)
    include(FetchContent)
    FetchContent_Declare(lovyangfx
        GIT_REPOSITORY https://github.com/lovyan03/LovyanGFX.git
        GIT_TAG "${LOVYANGFX_VERSION}"
        GIT_SHALLOW TRUE
        SOURCE_SUBDIR "not-a-cmake-project")  # sources only: LovyanGFX's own CMakeLists.txt is for ESP-IDF
    FetchContent_MakeAvailable(lovyangfx)
    set(LOVYANGFX_DIR "${lovyangfx_SOURCE_DIR}")
endif()

file(GLOB lovyangfx_sources CONFIGURE_DEPENDS
    "${LOVYANGFX_DIR}/src/lgfx/v1/*.cpp"
    "${LOVYANGFX_DIR}/src/lgfx/v1/misc/*.cpp"
    "${LOVYANGFX_DIR}/src/lgfx/v1/panel/*.cpp"
    "${LOVYANGFX_DIR}/src/lgfx/v1/touch/*.cpp"
    "${LOVYANGFX_DIR}/src/lgfx/v1/platforms/framebuffer/*.cpp"
    "${LOVYANGFX_DIR}/src/lgfx/v1/lv_font/*.c"
    "${LOVYANGFX_DIR}/src/lgfx/utility/*.c"
    "${LOVYANGFX_DIR}/src/lgfx/Fonts/efont/*.c"
    "${LOVYANGFX_DIR}/src/lgfx/Fonts/IPA/*.c")
if(NOT lovyangfx_sources)
    message(FATAL_ERROR "no LovyanGFX sources in ${LOVYANGFX_DIR}/src")
endif()

find_package(Threads REQUIRED)
add_library(lovyangfx STATIC ${lovyangfx_sources})
target_include_directories(lovyangfx SYSTEM PUBLIC "${LOVYANGFX_DIR}/src")
target_compile_definitions(lovyangfx PUBLIC LGFX_LINUX_FB)
target_compile_options(lovyangfx PRIVATE -w)  # not our code
target_link_libraries(lovyangfx PUBLIC Threads::Threads)
