# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.22.1)
project(crisper_audio_dsp LANGUAGES C CXX)

add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/../../../../native/crisper_dsp"
                 "${CMAKE_CURRENT_BINARY_DIR}/crisper_dsp")
add_library(crisper_audio_dsp SHARED crisper_audio_jni.cpp)
target_compile_features(crisper_audio_dsp PRIVATE cxx_std_17)
target_compile_options(crisper_audio_dsp PRIVATE -Wall -Wextra -Werror)
target_link_libraries(crisper_audio_dsp PRIVATE crisper_dsp)
# Support Android devices configured with 16 KB memory pages, including when
# this library is built with an NDK whose default is still 4 KB.
target_link_options(crisper_audio_dsp PRIVATE "-Wl,-z,max-page-size=16384")
