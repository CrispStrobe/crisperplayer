#!/usr/bin/env ruby
# Adds only explicitly selected, provisioned companion targets. No portal
# capabilities or profiles are changed. Run before pod install / archive.
require 'xcodeproj'
require 'optparse'
root = File.expand_path('..', __dir__)
selected = []
OptionParser.new do |parser|
  parser.on('--root PATH') { |value| root = File.expand_path(value) }
  parser.on('--widget') { selected << :widget }
  parser.on('--watch') { selected << :watch }
end.parse!
abort 'Select --widget and/or --watch after configuring their profiles.' if selected.empty?
project = Xcodeproj::Project.open(File.join(root, 'ios/Runner.xcodeproj'))
host = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target missing' unless host
specs = {
  widget: ['PlayerWidget', :app_extension, :ios, '15.0', 'com.crispstrobe.crisperplayer.PlayerWidget'],
  watch: ['PlayerWatch', :application, :watchos, '10.0', 'com.crispstrobe.crisperplayer.watchkitapp']
}
version = File.read(File.join(root, 'pubspec.yaml')).match(/^version:\s*([^+\s]+)\+(\d+)/)
selected.each do |kind|
  name, type, platform, minimum, identifier = specs.fetch(kind)
  target = project.targets.find { |t| t.name == name } || project.new_target(type, name, platform, minimum)
  group = project.main_group.groups.find { |g| g.name == name } || project.main_group.new_group(name, "Companions/#{name}")
  source_name = "#{name}.swift"
  reference = group.files.find { |f| f.path == source_name } || group.new_file(source_name)
  target.source_build_phase.add_file_reference(reference, true)
  if kind == :watch
    assets = group.files.find { |f| f.path == 'Assets.xcassets' } || group.new_file('Assets.xcassets')
    target.resources_build_phase.add_file_reference(assets, true)
  end
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_NAME' => name, 'EXECUTABLE_NAME' => name,
      'PRODUCT_BUNDLE_IDENTIFIER' => identifier, 'INFOPLIST_FILE' => "Companions/#{name}/Info.plist",
      'DEVELOPMENT_TEAM' => 'N9XSJ4M3GT', 'CODE_SIGN_STYLE' => 'Manual',
      'MARKETING_VERSION' => version[1], 'CURRENT_PROJECT_VERSION' => version[2],
      'SWIFT_VERSION' => '5.0', 'SKIP_INSTALL' => 'YES',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    })
    if kind == :widget
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Companions/PlayerWidget/PlayerWidget.entitlements'
      config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
    else
      config.build_settings['SDKROOT'] = 'watchos'
      config.build_settings['SUPPORTED_PLATFORMS'] = 'watchos watchsimulator'
      config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'
      config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
    end
  end
  host.add_dependency(target) unless host.dependencies.any? { |d| d.target == target }
  phase_name = kind == :widget ? 'Embed Player Widget' : 'Embed Player Watch'
  phase = host.copy_files_build_phases.find { |p| p.name == phase_name } || host.new_copy_files_build_phase(phase_name)
  phase.dst_subfolder_spec = kind == :widget ? '13' : '16'
  phase.dst_path = kind == :watch ? '$(CONTENTS_FOLDER_PATH)/Watch' : ''
  build_file = phase.files.find { |f| f.file_ref == target.product_reference } || phase.add_file_reference(target.product_reference, true)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  # Flutter's Thin Binary phase reads the finished app/Info.plist. Embed
  # companions before it, avoiding an archive dependency cycle in Xcode 15+.
  host.build_phases.delete(phase)
  thin = host.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  host.build_phases.insert(thin || host.build_phases.length, phase)
end
project.save
puts "Configured companion targets: #{selected.join(', ')}"
