module Fluent
  class GeoipFilter < Filter
    Plugin.register_filter('geoip', self)

    config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
    config_param :geoip_lookup_key, :string, :default => 'host'
    config_param :skip_adding_null_record, :bool, :default => false

    config_set_default :include_tag_key, false

    config_param :hostname_command, :string, :default => 'hostname'

    config_param :flush_interval, :time, :default => 0
    config_param :log_level, :string, :default => 'warn'


    def initialize
      require 'fluent/plugin/geoip_supplement'

      super
    end

    def configure(conf)
      super
      @supplement = GeoIPSupplement.new(self, conf)
    end

    def filter(tag, time, record)
      @supplement.add_geoip_field(record)
    end
  end
end
