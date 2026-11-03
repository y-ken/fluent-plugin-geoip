# Loads the plugin and looks up an address with the bundled GeoLite2 database,
# to confirm that the plugin and the geoip-c and geoip2_c native extensions are
# usable at runtime after a fresh install.
require "fluent/plugin/filter_geoip"
require "geoip2"

database = File.join(Gem.loaded_specs["fluent-plugin-geoip"].full_gem_path, "data", "GeoLite2-City.mmdb")
city = GeoIP2::Database.new(database).lookup("66.102.3.80")&.to_h&.dig("city", "names", "en")
abort "geoip2_c lookup failed: #{city.inspect}" unless city == "Mountain View"
puts "filter_geoip loaded; geoip-c and geoip2_c native extensions OK (66.102.3.80 is in #{city})"
