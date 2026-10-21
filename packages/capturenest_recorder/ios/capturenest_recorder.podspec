Pod::Spec.new do |s|
  s.name             = 'capturenest_recorder'
  s.version          = '0.1.0'
  s.summary          = 'Native CaptureNest recorder bridge.'
  s.description      = <<-DESC
Screen recording, export, and local-media support for CaptureNest.
                       DESC
  s.homepage         = 'https://github.com/thatsbikub-lab/screen-record-app'
  s.license          = { :type => 'MIT', :file => '../../LICENSE' }
  s.author           = { 'thatsbikub-lab' => 'opensource@thatsbikub-lab.github.io' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  s.frameworks = 'ReplayKit', 'AVFoundation', 'Photos'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end


