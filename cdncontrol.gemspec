$:.push File.expand_path('../lib', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'cdn_control'
  gem.version       = '0.0.9'
  gem.authors       = ["Jon Cowie", "Marcus Barczak"]
  gem.email         = 'jonlives@gmail.com'
  gem.homepage      = 'https://github.com/etsy/cdncontrol'
  gem.summary       = "Tool for managing multiple CDN balances on Dyn's GSLB"
  gem.description   = "Tool for managing multiple CDN balances on Dyn's GSLB"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "cdncontrol"
  gem.require_paths = ["lib"]

  gem.add_runtime_dependency 'dynect_rest', '>= 0.4.3'
  gem.add_runtime_dependency 'choice'
  gem.add_runtime_dependency 'app_conf'
end
