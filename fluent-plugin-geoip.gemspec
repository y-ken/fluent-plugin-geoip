# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-geoip"
  spec.version       = "0.5.0"
  spec.authors       = ["Kentaro Yoshida"]
  spec.email         = ["y.ken.studio@gmail.com"]
  spec.summary       = %q{Fluentd Output plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.}
  spec.homepage      = "https://github.com/y-ken/fluent-plugin-geoip"
  spec.license       = "Apache License, Version 2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"

  if defined?(RUBY_VERSION) && RUBY_VERSION > '2.2'
    spec.add_development_dependency "test-unit", '~> 3'
  end

  spec.add_runtime_dependency "fluentd"
  spec.add_runtime_dependency "fluent-mixin-rewrite-tag-name"
  spec.add_runtime_dependency "geoip-c"
end
