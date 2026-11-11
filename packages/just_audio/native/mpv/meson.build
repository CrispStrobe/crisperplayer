# SPDX-License-Identifier: MIT
# Copied with the reviewed native source closure by prepare_portable_mpv.py.
add_languages('cpp', required: true)
crisper_cpp = meson.get_compiler('cpp')
crisper_c = meson.get_compiler('c')
crisper_includes = include_directories(
  'core', 'core/vendor', 'core/vendor/bungee', 'core/vendor/eigen',
  'core/vendor/pffft', 'core/vendor/sonic', 'core/vendor/signalsmith-stretch')
crisper_definitions = [
  '-DEIGEN_MPL2_ONLY=1', '-DEIGEN_DONT_PARALLELIZE=1', '-DBUNGEE_SELF_TEST=0',
  '-DBUNGEE_VISIBILITY=',
  '-DBUNGEE_VERSION="61f52bf34be577d189d388772ddfa3696dee77d8"',
  '-Deigen_assert=BUNGEE_ASSERT1',
]
crisper_library = static_library('crisper_dsp',
  'core/crisper_dsp.cpp', 'core/wsola/wsola.cpp',
  'core/vendor/sonic/sonic.c',
  'core/vendor/pffft/pffft.c', 'core/vendor/pffft/fftpack.c',
  'core/vendor/bungee/src/Assert.cpp',
  'core/vendor/bungee/src/Fourier.cpp',
  'core/vendor/bungee/src/Grain.cpp',
  'core/vendor/bungee/src/Grains.cpp',
  'core/vendor/bungee/src/Input.cpp',
  'core/vendor/bungee/src/Instrumentation.cpp',
  'core/vendor/bungee/src/Output.cpp',
  'core/vendor/bungee/src/Partials.cpp',
  'core/vendor/bungee/src/Stretch.cpp',
  'core/vendor/bungee/src/Stretcher.cpp',
  'core/vendor/bungee/src/Synthesis.cpp',
  'core/vendor/bungee/src/Timing.cpp',
  'core/vendor/bungee/src/Window.cpp',
  'core/vendor/bungee/src/version.cpp',
  include_directories: crisper_includes,
  c_args: crisper_definitions + crisper_c.get_supported_arguments('-O2'),
  cpp_args: crisper_definitions + crisper_cpp.get_supported_arguments('-O2', '-fwrapv'),
  pic: true,
  override_options: ['cpp_std=c++20'])
dependencies += declare_dependency(
  link_with: crisper_library,
  include_directories: include_directories('core'))
