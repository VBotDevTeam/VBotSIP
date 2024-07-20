#
# Be sure to run `pod lib lint VBotSIP.podspec --use-libraries' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
	s.name             	= "VBotSIP"
	s.version          	= "1.0.0"
	s.summary          	= "VBot SIP Library for iOS"
	s.description      	= "Objective-C wrapper around PJSIP."
	s.homepage         	= "https://vbot.vn"
	s.license          	= 'GNU GPL v3'
	s.author           	= {"VBot" => "vbot.vn"}

	s.source        = { :git => 'https://github.com/VBotDevTeam/VBotSIP.git', :tag => s.version.to_s }
	s.swift_version = '5.0'
	s.ios.deployment_target = '13.5'
	

	s.dependency 'Vialer-pjsip-iOS'
	s.dependency 'CocoaLumberjack'
  	s.dependency 'Reachability'
	
	s.vendored_frameworks = 'VBotSIP.framework'
  	s.pod_target_xcconfig = { 
  'ONLY_ACTIVE_ARCH' => 'NO',
  'GCC_PREPROCESSOR_DEFINITIONS' => ['$(inherited)', 'PJ_AUTOCONF=1', 'SV_APP_EXTENSIONS'],
  'IPHONEOS_DEPLOYMENT_TARGET' => '13.5'

}
	
end
