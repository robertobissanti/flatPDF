# Custom override of Qt's FindWrapOpenGL that skips the legacy AGL fallback on Apple Silicon.
# Based on Qt 6.9.1's original module with the AGL fallback removed.

if(TARGET WrapOpenGL::WrapOpenGL)
    set(WrapOpenGL_FOUND ON)
    return()
endif()

set(WrapOpenGL_FOUND OFF)

find_package(OpenGL ${WrapOpenGL_FIND_VERSION})

if(OpenGL_FOUND)
    set(WrapOpenGL_FOUND ON)
    add_library(WrapOpenGL::WrapOpenGL INTERFACE IMPORTED)
    if(APPLE)
        get_target_property(__opengl_fw_lib_path OpenGL::GL IMPORTED_LOCATION)
        if(__opengl_fw_lib_path AND NOT __opengl_fw_lib_path MATCHES "/([^/]+)\\.framework$")
            get_filename_component(__opengl_fw_path "${__opengl_fw_lib_path}" DIRECTORY)
        endif()
        if(NOT __opengl_fw_path)
            set(__opengl_fw_path "-framework OpenGL")
        endif()
        target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE ${__opengl_fw_path})

        # Only link AGL if the framework actually exists on this macOS SDK.
        find_library(WrapOpenGL_AGL NAMES AGL)
        if(WrapOpenGL_AGL)
            # On Apple Silicon SDKs the framework stub exists without a binary; skip in that case.
            if(EXISTS "${WrapOpenGL_AGL}/AGL" OR EXISTS "${WrapOpenGL_AGL}/Versions/Current/AGL")
                target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE "${WrapOpenGL_AGL}")
            endif()
        endif()
    else()
        target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE OpenGL::GL)
    endif()
elseif(UNIX AND NOT APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "Integrity")
    find_package(OpenGL ${WrapOpenGL_FIND_VERSION} COMPONENTS OpenGL)
    if(OpenGL_FOUND)
        set(WrapOpenGL_FOUND ON)
        add_library(WrapOpenGL::WrapOpenGL INTERFACE IMPORTED)
        target_link_libraries(WrapOpenGL::WrapOpenGL INTERFACE OpenGL::OpenGL)
    endif()
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(WrapOpenGL DEFAULT_MSG WrapOpenGL_FOUND)
