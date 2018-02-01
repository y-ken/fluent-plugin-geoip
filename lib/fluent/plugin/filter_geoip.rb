require 'fluent/plugin/filter'
require 'fluent/plugin/geoip'

module Fluent::Plugin
  class GeoipFilter < Fluent::Plugin::Filter
    Fluent::Plugin.register_filter('geoip', self)

    helpers :compat_parameters, :inject

    config_param :geoip_database, :string, default: File.expand_path('../../../data/GeoLiteCity.dat', __dir__)
    config_param :geoip2_database, :string, default: File.expand_path('../../../data/GeoLite2-City.mmdb', __dir__)
    config_param :geoip_lookup_keys, :array, value_type: :string, default: ["host"]
    config_param :geoip_lookup_key, :string, default: nil, deprecated: "Use geoip_lookup_keys instead"
    config_param :skip_adding_null_record, :bool, default: false

    config_set_default :@log_level, "warn"

    config_param :backend_library, :enum, list: Fluent::GeoIP::BACKEND_LIBRARIES, default: :geoip2_c

    def configure(conf)
      compat_parameters_convert(conf, :inject)
      super
      @geoip = Fluent::GeoIP.new(self, conf)
    end

    def filter(tag, time, record)
      filtered_record = @geoip.add_geoip_field(record)
      if filtered_record
        record = filtered_record
      end
      record = inject_values_to_record(tag, time, record)
      record
    end

    def multi_workers_ready?
      true
    end
  end
end
