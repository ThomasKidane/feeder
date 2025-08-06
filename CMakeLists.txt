cmake_minimum_required(VERSION 3.16)
project(feeder)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Widgets)

add_executable(feeder
    src/main.cpp
    src/mainwindow.cpp
    src/mainwindow.h
    src/swift_wrapper.h
    src/swift_wrapper.cpp
)

target_link_libraries(feeder
    Qt6::Widgets
    "-framework ImageCaptureCore"
    "-framework AppKit"
    "-framework Foundation"
    "-framework Photos"
    "-framework CoreFoundation"
)

# Add entitlements for USB device access and file system permissions
set_target_properties(feeder PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
)

# Copy entitlements file
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/feeder.entitlements" "${CMAKE_CURRENT_BINARY_DIR}/feeder.entitlements" COPYONLY)

# Apply entitlements and code signing after build
add_custom_command(TARGET feeder POST_BUILD
    COMMAND codesign --force --sign - --entitlements "${CMAKE_CURRENT_BINARY_DIR}/feeder.entitlements" "$<TARGET_FILE:feeder>"
    COMMENT "Signing feeder with entitlements"
) 