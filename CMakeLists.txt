cmake_minimum_required(VERSION 3.21)
project(kadr VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick OpenGL)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(kadr
    src/main.cpp
)

qt_add_qml_module(kadr
    URI Kadr
    VERSION 1.0
    QML_FILES
        qml/Main.qml
    SOURCES
        src/mpvobject.cpp src/mpvobject.h
        src/theme.cpp src/theme.h
)

target_include_directories(kadr PRIVATE src)
target_link_libraries(kadr PRIVATE Qt6::Quick Qt6::OpenGL PkgConfig::MPV)

install(TARGETS kadr RUNTIME DESTINATION bin)
