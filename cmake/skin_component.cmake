# Reads an ESP-IDF component (a skin, or a component it builds on) the way ESP-IDF's own first pass does
# (tools/cmake/scripts/component_get_requirements.cmake): its CMakeLists.txt runs with a stand-in
# idf_component_register that only records the arguments (and an idf_build_get_property that answers the target). The CONFIG_* variables must be set before (sdkconfig.cmake).
# Paths come back absolute.

# Components ask for the target to register less for the host tests (IDF_TARGET linux); the toolbox wants what they
# register for the radio.
function(idf_build_get_property output property)
    if(NOT property STREQUAL "IDF_TARGET")
        message(FATAL_ERROR "skin_component.cmake: idf_build_get_property(${property}) isn't stood in for")
    endif()
    set(${output} "esp32" PARENT_SCOPE)
endfunction()

macro(idf_component_register)
    cmake_parse_arguments(_registered "" ""
                          "SRCS;INCLUDE_DIRS;PRIV_INCLUDE_DIRS;EMBED_FILES;EMBED_TXTFILES;REQUIRES;PRIV_REQUIRES"
                          ${ARGN})
    set(_component_registered TRUE)
endmacro()

function(_absolute_paths base output)
    set(paths "")
    foreach(path IN LISTS ARGN)
        get_filename_component(path "${path}" ABSOLUTE BASE_DIR "${base}")
        list(APPEND paths "${path}")
    endforeach()
    set(${output} "${paths}" PARENT_SCOPE)
endfunction()

# avela_read_component(<directory> <prefix>): sets <prefix>_SOURCES, <prefix>_INCLUDE_DIRS (public),
# <prefix>_PRIV_INCLUDE_DIRS, <prefix>_EMBED_FILES, <prefix>_EMBED_TXTFILES, <prefix>_REQUIRES (public) and
# <prefix>_PRIV_REQUIRES. The component's CMakeLists.txt runs in this function's scope, so the arguments are kept in
# names it won't use.
function(avela_read_component _avela_directory _avela_prefix)
    set(_component_registered FALSE)
    set(COMPONENT_DIR "${_avela_directory}")
    include("${_avela_directory}/CMakeLists.txt")
    if(NOT _component_registered)
        message(FATAL_ERROR "${_avela_directory}/CMakeLists.txt doesn't call idf_component_register")
    endif()
    _absolute_paths("${_avela_directory}" _avela_sources ${_registered_SRCS})
    _absolute_paths("${_avela_directory}" _avela_include_directories ${_registered_INCLUDE_DIRS})
    _absolute_paths("${_avela_directory}" _avela_private_include_directories ${_registered_PRIV_INCLUDE_DIRS})
    _absolute_paths("${_avela_directory}" _avela_embed_files ${_registered_EMBED_FILES})
    _absolute_paths("${_avela_directory}" _avela_embed_text_files ${_registered_EMBED_TXTFILES})
    set(${_avela_prefix}_SOURCES "${_avela_sources}" PARENT_SCOPE)
    set(${_avela_prefix}_INCLUDE_DIRS "${_avela_include_directories}" PARENT_SCOPE)
    set(${_avela_prefix}_PRIV_INCLUDE_DIRS "${_avela_private_include_directories}" PARENT_SCOPE)
    set(${_avela_prefix}_EMBED_FILES "${_avela_embed_files}" PARENT_SCOPE)
    set(${_avela_prefix}_EMBED_TXTFILES "${_avela_embed_text_files}" PARENT_SCOPE)
    set(${_avela_prefix}_REQUIRES "${_registered_REQUIRES}" PARENT_SCOPE)
    set(${_avela_prefix}_PRIV_REQUIRES "${_registered_PRIV_REQUIRES}" PARENT_SCOPE)
endfunction()

# avela_skin_api_include_directories(<components directory> <output> <names...>): the include directories of the
# named components and of everything they require publicly, found in <components directory>. Names that aren't
# there (ESP-IDF's own components, reached through a component's public REQUIRES) are skipped: the skin API headers
# are platform-free, so a skin never needs them.
function(avela_skin_api_include_directories components_directory output)
    set(pending ${ARGN})
    set(visited "")
    set(include_directories "")
    while(pending)
        list(POP_FRONT pending name)
        if(name IN_LIST visited OR NOT EXISTS "${components_directory}/${name}/CMakeLists.txt")
            continue()
        endif()
        list(APPEND visited "${name}")
        avela_read_component("${components_directory}/${name}" required)
        list(APPEND include_directories ${required_INCLUDE_DIRS})
        list(APPEND pending ${required_REQUIRES})
    endwhile()
    set(${output} "${include_directories}" PARENT_SCOPE)
endfunction()

# avela_embed_files(<output sources> <files...>): one assembly file per embedded file, defining the same
# _binary_<name>_start / _binary_<name>_end symbols ESP-IDF's EMBED_FILES gives (name = the file name as a C
# identifier), so the skin's assets.hpp works unchanged. TEXT appends a 0 like EMBED_TXTFILES.
function(avela_embed_files output)
    cmake_parse_arguments(embed "TEXT" "" "" ${ARGN})
    set(sources "")
    foreach(file IN LISTS embed_UNPARSED_ARGUMENTS)
        get_filename_component(file_name "${file}" NAME)
        string(MAKE_C_IDENTIFIER "${file_name}" symbol)
        set(terminator "")
        if(embed_TEXT)
            set(terminator "    .byte 0\n")
        endif()
        set(assembly "${CMAKE_BINARY_DIR}/embedded/${symbol}.S")
        file(WRITE "${assembly}"
             "    .section .rodata.embedded.${symbol}, \"a\"\n"
             "    .balign 4\n"
             "    .global _binary_${symbol}_start\n"
             "_binary_${symbol}_start:\n"
             "    .incbin \"${file}\"\n"
             "    .global _binary_${symbol}_end\n"
             "_binary_${symbol}_end:\n"
             "${terminator}"
             "    .section .note.GNU-stack, \"\", @progbits\n")
        set_source_files_properties("${assembly}" PROPERTIES OBJECT_DEPENDS "${file}")
        list(APPEND sources "${assembly}")
    endforeach()
    set(${output} "${sources}" PARENT_SCOPE)
endfunction()
