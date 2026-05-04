cmake_minimum_required(VERSION 3.16)

project(flatPdfQt2 VERSION 0.1 LANGUAGES CXX)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(QT_GRAPHICS_API "metal")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Minimum macOS version (Catalina)
if(APPLE AND NOT DEFINED CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum macOS version")
endif()

if(NOT CMAKE_PREFIX_PATH AND EXISTS "/Applications/Qt/6.9.1/macos")
    list(APPEND CMAKE_PREFIX_PATH "/Applications/Qt/6.9.1/macos")
endif()

find_package(Qt6 6.2 REQUIRED COMPONENTS Core Gui Qml Quick QmlModels Network Widgets)

qt_add_executable(appflatPdfQt2
    main.cpp
    PdfFlattener.cpp
    PdfFlattener.h
    MacAbout.h
)

if(APPLE)
    target_sources(appflatPdfQt2 PRIVATE MacAbout.mm)
endif()

target_compile_features(appflatPdfQt2 PRIVATE cxx_std_17)

qt_add_qml_module(appflatPdfQt2
    URI flatPdfQt2
    VERSION 1.0
    QML_FILES
        Main.qml
)

set_target_properties(appflatPdfQt2 PROPERTIES
    OUTPUT_NAME flatPDF
    MACOSX_BUNDLE_BUNDLE_NAME flatPDF
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE_ICON_FILE flatPdf.icns
)

# Bundle app icon into Resources
if(APPLE)
    set_source_files_properties(flatPdf.icns PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    target_sources(appflatPdfQt2 PRIVATE flatPdf.icns)
endif()

target_link_libraries(appflatPdfQt2 PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QmlModels
    Qt6::Network
    Qt6::Widgets
)

if(APPLE)
    target_link_libraries(appflatPdfQt2 PRIVATE "-framework Cocoa")
endif()

include(GNUInstallDirs)
install(TARGETS appflatPdfQt2
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
