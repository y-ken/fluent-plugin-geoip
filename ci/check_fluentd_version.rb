# The CI covers Fluentd 1.20.1 and later. Fail if Bundler resolved an older one.
require "fluent/version"
version = Gem::Version.new(Fluent::VERSION)
puts "Fluentd #{version}"
abort "Fluentd 1.20.1 or later is expected" if version < Gem::Version.new("1.20.1")
