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
	s.version          	= "1.2.0"
	s.summary          	= "VBot SIP Library for iOS"
	s.description      	= "Objective-C wrapper around PJSIP."
	s.homepage         	= "https://vbot.vn"
	s.license          	= 'GNU GPL v3'
	s.author           	= {"Dat Nguyen Quoc" => "datnq@vpmedia.vn"}

	s.source           	= {:git => "https://github.com/qdatt/VBotSIP.git", :tag => s.version.to_s}
	s.social_media_url 	= "https://vbot.vn"

	s.platform     		= :ios, '13.5'
	s.requires_arc 		= true

	s.source_files 		= "Pod/Classes/**/*.{h,m}"
	s.public_header_files   = "Pod/Classes/**/*.h"

	s.resource_bundles  = { 'VBotSIP' => 'Pod/Resources/*.wav' }
	s.swift_version = '5.0'
	s.ios.deployment_target = '13.5'

	s.dependency 'Vialer-pjsip-iOS'
	s.dependency 'CocoaLumberjack'

  	s.xcconfig = {'GCC_PREPROCESSOR_DEFINITIONS' => 'PJ_AUTOCONF=1'}
end
