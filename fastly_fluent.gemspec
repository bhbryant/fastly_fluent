# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)\

Gem::Specification.new do |spec|
  spec.name          = "fastly_fluent"
  spec.version       = '0.0.1'
  spec.authors       = ["Benjamin Bryant"]
  spec.email         = ["benjaminhbryant@gmail.com"]
  spec.description   = %q{fluent plugin for JSON encoded fastly syslogs}
  spec.summary       = %q{}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_runtime_dependency "fluentd"
end
