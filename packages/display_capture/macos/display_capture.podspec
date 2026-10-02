Pod::Spec.new do |s|
  s.name             = 'display_capture'
  s.version          = '0.1.0'
  s.summary          = 'Display capture plugin for Flutter desktop macOS.'
  s.description      = <<-DESC
  Native display capture and window-chrome integration for the Display Controller app.
                       DESC
  s.homepage         = 'https://github.com/tejusadiga2004/MultiDisplay'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Display Controller' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'display_capture/Sources/**/*.{swift,metal}'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '14.0'
  s.swift_version = '5.9'
end
