Pod::Spec.new do |spec|
    spec.name     = 'BtaAudienzz'
    spec.version  = '0.1.13'
    spec.license  = { :type => 'Apache-2.0', :file => 'LICENSE' }
    spec.homepage = 'https://github.com/audienzz/bta-audienzz-ios-sdk'
    spec.authors  = { 'Audienzz <tech@audienzz.ch>' => 'https://audienzz.ch' }
    spec.summary  = 'iOS BTA (Below The Article) feed SDK by Audienzz'
    spec.source   = { :git => 'https://github.com/audienzz/bta-audienzz-ios-sdk.git',
                      :tag => '0.1.13' }

    spec.swift_version         = '5.7'
    spec.ios.deployment_target = '13.0'

    spec.requires_arc          = true

    spec.source_files          = 'BtaAudienzz/**/*.swift'
    spec.exclude_files         = 'Example'
end
