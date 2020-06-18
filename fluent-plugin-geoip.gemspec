# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-geoip"
  spec.version       = "1.3.2"
  spec.authors       = ["Kentaro Yoshida"]
  spec.email         = ["y.ken.studio@gmail.com"]
  spec.summary       = %q{Fluentd Filter plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.}
  spec.homepage      = "https://github.com/y-ken/fluent-plugin-geoip"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "test-unit", ">= 3.1.0"
  spec.add_development_dependency "test-unit-rr"
  spec.add_development_dependency "geoip2_compat"

  spec.add_runtime_dependency "fluentd", [">= 0.14.8", "< 2"]
  spec.add_runtime_dependency "geoip-c"
  spec.add_runtime_dependency "geoip2_c"
  spec.add_runtime_dependency "dig_rb"
end
