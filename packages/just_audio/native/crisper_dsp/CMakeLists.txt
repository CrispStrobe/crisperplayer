# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.22)
project(crisper_dsp LANGUAGES C CXX)

# Static linking remains the application default. The shared target lets the
# same streaming contract run against actual Windows/macOS/Linux compilers.
option(CRISPER_DSP_SHARED "Build a shared library for native integration tests" OFF)
option(CRISPER_DSP_TESTS "Build native regression executables" OFF)
if(CRISPER_DSP_SHARED)
  set(CRISPER_DSP_LIBRARY_TYPE SHARED)
else()
  set(CRISPER_DSP_LIBRARY_TYPE STATIC)
endif()

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
add_library(crisper_dsp ${CRISPER_DSP_LIBRARY_TYPE} crisper_dsp.cpp wsola/wsola.cpp ${BUNGEE_SOURCES}
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
# MSVC requires this before <math.h> for FFTPACK's M_PI constants. Keep the
# definition on our target so the pinned upstream C sources remain unchanged.
if(MSVC)
  target_compile_definitions(crisper_dsp PRIVATE _USE_MATH_DEFINES)
endif()
# Native audio processing needs optimization even in Flutter Debug builds.
target_compile_options(crisper_dsp PRIVATE
  $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-O2>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang,AppleClang>:-fwrapv>
  # CMake's MSVC Debug flags include /RTC1, which conflicts with /O2. Keep that
  # debugger configuration buildable; device performance checks use Release.
  $<$<AND:$<C_COMPILER_ID:MSVC>,$<NOT:$<CONFIG:Debug>>>:/O2>)
if(ANDROID)
  target_link_libraries(crisper_dsp PRIVATE log)
elseif(UNIX)
  target_link_libraries(crisper_dsp PRIVATE m)
endif()

if(CRISPER_DSP_TESTS)
  enable_testing()
  add_executable(crisper_dsp_wsola_search tools/test_wsola_search.cpp wsola/wsola.cpp)
  target_compile_features(crisper_dsp_wsola_search PRIVATE cxx_std_20)
  target_include_directories(crisper_dsp_wsola_search PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  add_test(NAME wsola_search COMMAND crisper_dsp_wsola_search)
endif()
