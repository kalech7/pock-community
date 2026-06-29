# Uncomment the next line to define a global platform for your project
platform :osx, '10.15'

target 'Pock' do

  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # PockKit
  pod 'PockKit', :git => 'git@github.com:pock/pockkit.git'

  # Analytics
  pod 'AppCenter/Analytics'
  pod 'AppCenter/Crashes'

  # Utils
  pod 'Magnet'
  pod 'Zip'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      deployment_target = config.build_settings['MACOSX_DEPLOYMENT_TARGET']
      next if deployment_target.nil?

      if Gem::Version.new(deployment_target) < Gem::Version.new('10.13')
        config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.13'
      end
    end
  end
end
