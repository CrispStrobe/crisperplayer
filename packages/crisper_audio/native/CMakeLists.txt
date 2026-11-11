# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.22)
project(crisper_audio_native VERSION 0.1.0 LANGUAGES C CXX)

option(CRISPER_AUDIO_TESTS "Build native output regressions" OFF)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

add_library(crisper_audio SHARED crisper_output.cpp miniaudio_impl.c dsp_link.cpp)
target_compile_features(crisper_audio PRIVATE c_std_11 cxx_std_20)
target_include_directories(crisper_audio PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
set_target_properties(crisper_audio PROPERTIES
  OUTPUT_NAME crisper_audio POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(crisper_audio PRIVATE DART_SHARED_LIB)

# Existing four-engine core, with its original source pins and license set.
# dsp_link.cpp references the ABI translation unit, retaining its exports when
# the core is a static archive and the only external callers are Dart FFI.
set(CRISPER_DSP_SHARED OFF CACHE BOOL "" FORCE)
set(CRISPER_DSP_TESTS OFF CACHE BOOL "" FORCE)
# Flutter invokes this project through .plugin_symlinks/crisper_audio. Resolve
# that symlink BEFORE moving to a sibling; just_audio has no Linux/Windows
# native plugin registration and need not have a sibling plugin symlink.
get_filename_component(CRISPER_AUDIO_PACKAGE_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)
set(CRISPER_DSP_SOURCE_DIR
  "${CRISPER_AUDIO_PACKAGE_ROOT}/../just_audio/native/crisper_dsp")
# Windows: CMake's REALPATH does not resolve Flutter's plugin symlink there,
# so locate just_audio through the app's resolved Dart package configuration.
if(NOT EXISTS "${CRISPER_DSP_SOURCE_DIR}/CMakeLists.txt")
  set(_crisper_pkg_config "${CMAKE_SOURCE_DIR}/../.dart_tool/package_config.json")
  if(NOT EXISTS "${_crisper_pkg_config}")
    message(FATAL_ERROR "crisper_dsp not found next to crisper_audio and no "
                        "package config at ${_crisper_pkg_config}")
  endif()
  file(READ "${_crisper_pkg_config}" _crisper_pkg_json)
  string(JSON _crisper_pkg_count LENGTH "${_crisper_pkg_json}" packages)
  math(EXPR _crisper_pkg_last "${_crisper_pkg_count} - 1")
  foreach(_i RANGE ${_crisper_pkg_last})
    string(JSON _name GET "${_crisper_pkg_json}" packages ${_i} name)
    if(_name STREQUAL "just_audio")
      string(JSON _uri GET "${_crisper_pkg_json}" packages ${_i} rootUri)
      if(_uri MATCHES "^file:///?(.*)$")
        set(_uri "${CMAKE_MATCH_1}")
        if(NOT WIN32 AND NOT _uri MATCHES "^/")
          set(_uri "/${_uri}")
        endif()
      else()
        set(_uri "${CMAKE_SOURCE_DIR}/../.dart_tool/${_uri}")
      endif()
      string(REPLACE "%20" " " _uri "${_uri}")
      get_filename_component(_uri "${_uri}" ABSOLUTE)
      set(CRISPER_DSP_SOURCE_DIR "${_uri}/native/crisper_dsp")
      break()
    endif()
  endforeach()
endif()
if(NOT EXISTS "${CRISPER_DSP_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "crisper_dsp sources not found at ${CRISPER_DSP_SOURCE_DIR}")
endif()
add_subdirectory("${CRISPER_DSP_SOURCE_DIR}"
                 "${CMAKE_CURRENT_BINARY_DIR}/crisper_dsp")
target_link_libraries(crisper_audio PRIVATE crisper_dsp)

# Decoder-only Glint source closure. OBJECT linkage keeps Dart-only ABI
# symbols from being discarded as unused members of a static archive.
include("${CMAKE_CURRENT_SOURCE_DIR}/glint.cmake")
target_sources(crisper_audio PRIVATE $<TARGET_OBJECTS:crisper_glint>)
target_link_libraries(crisper_audio PRIVATE crisper_glint)

if(WIN32)
  target_link_libraries(crisper_audio PRIVATE ole32)
elseif(APPLE)
  target_link_libraries(crisper_audio PRIVATE
    "-framework CoreFoundation" "-framework CoreAudio"
    "-framework AudioToolbox" "-framework AudioUnit")
elseif(ANDROID)
  target_link_libraries(crisper_audio PRIVATE OpenSLES log m)
  target_link_options(crisper_audio PRIVATE "-Wl,-z,max-page-size=16384")
elseif(UNIX)
  find_package(Threads REQUIRED)
  target_link_libraries(crisper_audio PRIVATE Threads::Threads ${CMAKE_DL_LIBS} m)
  # The FFI library must load independently of the Flutter executable. Catch
  # missing runtime dependencies at link time, not only when Dart opens it.
  target_link_options(crisper_audio PRIVATE "-Wl,--no-undefined")
endif()

if(CRISPER_AUDIO_TESTS)
  enable_testing()
  add_executable(crisper_output_test tests/output_test.cpp)
  target_compile_features(crisper_output_test PRIVATE cxx_std_20)
  target_link_libraries(crisper_output_test PRIVATE crisper_audio)
  add_test(NAME crisper_output COMMAND crisper_output_test)
  set_tests_properties(crisper_output PROPERTIES TIMEOUT 20)

  # Exercise miniaudio's real fallback path with every physical backend
  # disabled. This must fail in production mode even though the explicit
  # null device remains available for offline tests.
  add_executable(crisper_output_no_device_test
    tests/no_device_test.cpp crisper_output.cpp miniaudio_impl.c)
  target_compile_features(crisper_output_no_device_test PRIVATE c_std_11 cxx_std_20)
  target_include_directories(crisper_output_no_device_test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}")
  target_compile_definitions(crisper_output_no_device_test PRIVATE
    MA_ENABLE_ONLY_SPECIFIC_BACKENDS MA_ENABLE_NULL)
  if(UNIX)
    find_package(Threads REQUIRED)
    target_link_libraries(crisper_output_no_device_test PRIVATE
      Threads::Threads ${CMAKE_DL_LIBS} m)
  endif()
  add_test(NAME crisper_output_no_device COMMAND crisper_output_no_device_test)
  set_tests_properties(crisper_output_no_device PROPERTIES TIMEOUT 20)
endif()
