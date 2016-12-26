require 'fluent/plugin/geoip'

module Fluent
  class GeoipFilter < Filter
    Plugin.register_filter('geoip', self)

    config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
    config_param :geoip2_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLite2-City.mmdb'
    config_param :geoip_lookup_key, :string, :default => 'host'
    config_param :skip_adding_null_record, :bool, :default => false

    config_set_default :include_tag_key, false

    config_param :hostname_command, :string, :default => 'hostname'

    config_param :flush_interval, :time, :default => 0
    config_param :log_level, :string, :default => 'warn'

    begin
      config_param :backend_library, :enum, :list => Fluent::GeoIP::BACKEND_LIBRARIES, :default => :geoip
    rescue ArgumentError
      # For v0.10.x
      config_param :backend_library, :string, :default => 'geoip'
    end

    def configure(conf)
      super
      # For v0.10.x
      if @backend_library.is_a?(String)
        @backend_library = @backend_library.to_sym
        unless Fluent::GeoIP::BACKEND_LIBRARIES.include?(@backend_library)
          raise Fluent::ConfigError, "valid options are #{Fluent::GeoIP::BACKEND_LIBRARIES.join(',')} but got #{@backend_library}"
        end
      end
      @geoip = Fluent::GeoIP.new(self, conf)
    end

    def filter_stream(tag, es)
      new_es = MultiEventStream.new
      es.each do |time, record|
        begin
          filtered_record = @geoip.add_geoip_field(record)
          new_es.add(time, filtered_record) if filtered_record
        rescue => e
          router.emit_error_event(tag, time, record, e)
        end
      end
      new_es
    end
  end
end
