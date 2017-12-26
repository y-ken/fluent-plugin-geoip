#! /usr/bin/env ruby

require "geoip"
require "geoip2_compat"
require "geoip2"
require "pp"

backend = ARGV[0]
ip = ARGV[1]

geoip_database = File.expand_path("../data/GeoLiteCity.dat", __dir__)
geoip2_database = File.expand_path("../data/GeoLite2-City.mmdb", __dir__)

geoip = GeoIP::City.new(geoip_database, :memory, false)
geoip2_compat = GeoIP2Compat.new(geoip2_database)
geoip2 = GeoIP2::Database.new(geoip2_database)

record = case backend
         when "geoip"
           geoip.look_up(ip)
         when "geoip2_compat"
           geoip2_compat.lookup(ip)
         when "geoip2"
           geoip2.lookup(ip)
         end

pp record.to_h
