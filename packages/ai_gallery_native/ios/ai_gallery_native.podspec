Pod::Spec.new do |s|
  s.name             = 'ai_gallery_native'
  s.version          = '0.2.0'
  s.summary          = 'AI Gallery native photo and embedding bridge'
  s.description      = 'PhotoKit, LiteRT-LM, local indexing, and sharing bridge for AI Gallery.'
  s.homepage         = 'https://example.invalid/ai-gallery'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AI Gallery' => 'dev@invalid.example' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h,m}'
  s.vendored_frameworks = 'Frameworks/CLiteRTLM.framework'
  s.frameworks       = 'Photos', 'UIKit', 'Foundation'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
end
