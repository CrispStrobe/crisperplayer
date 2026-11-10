# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.22)
project(crisper_dsp LANGUAGES C CXX)

# Offline, explicit source list: no FetchContent and no optional/proprietary DSP.
set(BUNGEE_SOURCES
  vendor/bungee/src/Assert.cpp
  vendor/bungee/src/Fourier.cpp
  vendor/bungee/src/Grain.cpp
  vendor/bungee/src/Grains.cpp
  vendor/bungee/src/Input.cpp
  vendor/bungee/src/Instrumentation.cpp
  vendor/bungee/src/Output.cpp
  vendor/bungee/src/Partials.cpp
  vendor/bungee/src/Stretch.cpp
  vendor/bungee/src/Stretcher.cpp
  vendor/bungee/src/Synthesis.cpp
  vendor/bungee/src/Timing.cpp
  vendor/bungee/src/Window.cpp
  vendor/bungee/src/version.cpp)
add_library(crisper_dsp STATIC crisper_dsp.cpp ${BUNGEE_SOURCES}
  vendor/pffft/pffft.c vendor/pffft/fftpack.c vendor/sonic/sonic.c)
set_target_properties(crisper_dsp PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_features(crisper_dsp PUBLIC cxx_std_20)
target_include_directories(crisper_dsp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(crisper_dsp PRIVATE
  vendor/bungee vendor/eigen vendor/pffft vendor/sonic
  vendor/signalsmith-stretch vendor)
target_compile_definitions(crisper_dsp PRIVATE
  EIGEN_MPL2_ONLY=1 EIGEN_DONT_PARALLELIZE=1 BUNGEE_SELF_TEST=0
  BUNGEE_VISIBILITY= BUNGEE_VERSION="61f52bf34be577d189d388772ddfa3696dee77d8"
  eigen_assert=BUNGEE_ASSERT1)
# Native audio processing needs optimization even in Flutter Debug builds.
target_compile_options(crisper_dsp PRIVATE
  $<$<C_COMPILER_ID:GNU,Clang>:-O2>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-fwrapv>)
if(ANDROID)
  target_link_libraries(crisper_dsp PRIVATE log)
elseif(UNIX)
  target_link_libraries(crisper_dsp PRIVATE m)
endif()
