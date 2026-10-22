# Adds the CaptureNestBroadcast upload extension to the generated ios/ runner.
# Run by tool/bootstrap_platforms.sh after `flutter create`; safe to run more than once.
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
name = 'CaptureNestBroadcast'
project_path = File.join(root, 'ios', 'Runner.xcodeproj')

FileUtils.mkdir_p(File.join(root, 'ios', name))
%w[SampleHandler.swift Info.plist].each do |file|
  FileUtils.cp(File.join(root, 'ios_broadcast', file), File.join(root, 'ios', name, file))
end

project = Xcodeproj::Project.open(project_path)
exit 0 if project.targets.any? { |target| target.name == name }

version_line = File.read(File.join(root, 'pubspec.yaml'))[/^version:\s*(\S+)/, 1] || '1.0.0+1'
marketing_version, build_number = version_line.split('+')
build_number ||= '1'

app = project.targets.find { |target| target.name == 'Runner' }
extension = project.new_target(:app_extension, name, :ios, '15.0', nil, :swift)

group = project.main_group.new_group(name, name)
extension.add_file_references([group.new_reference('SampleHandler.swift')])
group.new_reference('Info.plist')
extension.add_system_framework('ReplayKit')

release = extension.build_configurations.find { |config| config.name == 'Release' }
unless extension.build_configurations.any? { |config| config.name == 'Profile' }
  profile = extension.add_build_configuration('Profile', :release)
  profile.build_settings = release.build_settings.dup
end

extension.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.thatsbikublab.capturenest.broadcast'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['INFOPLIST_FILE'] = "#{name}/Info.plist"
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['MARKETING_VERSION'] = marketing_version
  settings['CURRENT_PROJECT_VERSION'] = build_number
  settings['SWIFT_VERSION'] = '5.0'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['SKIP_INSTALL'] = 'YES'
  settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  settings['ENABLE_BITCODE'] = 'NO'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

app.add_dependency(extension)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(extension.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Flutter's "Thin Binary" script must run after embedding, otherwise Xcode reports a build cycle.
thin_binary = app.build_phases.find { |phase| phase.respond_to?(:name) && phase.name == 'Thin Binary' }
if thin_binary
  app.build_phases.delete(embed)
  app.build_phases.insert(app.build_phases.index(thin_binary), embed)
end

project.save
puts "Added #{name} broadcast extension to the iOS runner."
