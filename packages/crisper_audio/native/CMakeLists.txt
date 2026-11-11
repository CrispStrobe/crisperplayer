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
add_subdirectory("${CRISPER_AUDIO_PACKAGE_ROOT}/../just_audio/native/crisper_dsp"
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
