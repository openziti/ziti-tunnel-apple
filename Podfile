abstract_target 'ios_targets' do
  platform :ios, '13.4.3'
  use_frameworks!
  # pod 'CZiti-iOS', '~> 0.1'
  pod 'CZiti-iOS', '~> 0.21.0-beta.2'

  target 'Ziti Mobile Edge' do
  end

  target 'MobileShare' do
  end

  target 'MobilePacketTunnelProvider' do
    post_install do |installer|
      installer.pods_project.build_configurations.each do |config|
        config.build_settings["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] = "arm64"
      end
    end
  end
end

abstract_target 'macos_targets' do
  platform :osx, '10.15'
  use_frameworks!
  # pod 'CZiti-macOS', '~> 0.1'
  pod 'CZiti-macOS', '~> 0.21.0-beta.2'

  target 'Ziti Desktop Edge' do
  end

  target 'PacketTunnelProvider' do
  end
end

