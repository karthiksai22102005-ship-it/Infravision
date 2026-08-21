cmake_minimum_required(VERSION 3.14)
project(infravision_camera LANGUAGES CXX)

set(PLUGIN_NAME "infravision_camera_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/infravision_camera/infravision_camera_plugin.h"
  "infravision_camera_plugin.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  POSITION_INDEPENDENT_CODE ON
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE "NOMINMAX")
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# flutter_wrapper_plugin provides the include directory for the Flutter
# C++ API headers (flutter/method_channel.h, flutter/texture_registrar.h, etc.)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  mf
  mfplat
  mfreadwrite
  mfuuid
  ole32
)

# Expose public headers so the app's generated plugin registrant can
# include <infravision_camera/infravision_camera_plugin.h>.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

set(PLUGIN_BUNDLED_LIBRARIES)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  add_subdirectory("${bundled_library}" "${PLUGIN_NAME}_bundled")
  target_link_libraries(${PLUGIN_NAME} PRIVATE ${bundled_library}_target)
endforeach()
