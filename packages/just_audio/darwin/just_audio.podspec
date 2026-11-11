#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'just_audio'
  s.version          = '0.0.1'
  s.summary          = 'Flutter audio player'
  s.description      = <<-DESC
A flutter plugin for playing audio.
                       DESC
  s.homepage         = 'https://github.com/ryanheise/just_audio'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Wrapper translation units include the exact shared native sources; this
  # keeps Android, Apple and desktop on one reviewed vendor/source closure.
  s.source_files = 'just_audio/Sources/just_audio/**/*.{h,m,mm,c,cpp}'
  s.public_header_files = 'just_audio/Sources/just_audio/include/**/*.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.frameworks = 'AVFoundation'
  s.libraries = 'c++'
  s.compiler_flags = '-O2 -fwrapv'
  native = '"${PODS_TARGET_SRCROOT}/../native/crisper_dsp'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)', native + '"', native + '/vendor"',
      native + '/vendor/bungee"', native + '/vendor/eigen"',
      native + '/vendor/pffft"', native + '/vendor/sonic"',
      native + '/vendor/signalsmith-stretch"'
    ].join(' '),
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) EIGEN_MPL2_ONLY=1 EIGEN_DONT_PARALLELIZE=1 BUNGEE_SELF_TEST=0 BUNGEE_VISIBILITY= BUNGEE_VERSION=\\"61f52bf34be577d189d388772ddfa3696dee77d8\\" eigen_assert=BUNGEE_ASSERT1'
  }
end
