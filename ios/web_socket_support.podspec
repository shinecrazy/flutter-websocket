#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint web_socket_support.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'web_socket_support'
  s.version          = '0.2.5'
  s.summary          = 'Flutter plugin for websockets using Starscream on iOS and OkHttp on Android.'
  s.description      = <<-DESC
A Flutter plugin for websockets on iOS and Android. This plugin is based on Starscream (for iOS) and OkHttp (for Android) platforms.
                       DESC
  s.homepage         = 'https://github.com/sharpbitstudio/flutter-websocket-support-mobile-implementation'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SharpBit Studio' => 'contact@sharpbitstudio.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'Starscream', '~> 4.0.0'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end