# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.22)
project(crisper_audio LANGUAGES C CXX)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../native"
                 "${CMAKE_CURRENT_BINARY_DIR}/native")
set(crisper_audio_bundled_libraries $<TARGET_FILE:crisper_audio> PARENT_SCOPE)
