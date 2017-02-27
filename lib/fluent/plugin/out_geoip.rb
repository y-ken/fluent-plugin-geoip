require 'fluent/mixin/rewrite_tag_name'
require 'fluent/plugin/geoip'

class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)

  config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
  config_param :geoip2_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLite2-City.mmdb'
  config_param :geoip_lookup_key, :string, :default => 'host'
  config_param :tag, :string, :default => nil
  config_param :skip_adding_null_record, :bool, :default => false

  include Fluent::HandleTagNameMixin
  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false

  include Fluent::Mixin::RewriteTagName
  config_param :hostname_command, :string, :default => 'hostname'

  config_param :flush_interval, :time, :default => 0
  config_param :log_level, :string, :default => 'warn'

  begin
    config_param :backend_library, :enum, :list => Fluent::GeoIP::BACKEND_LIBRARIES, :default => :geoip
  rescue ArgumentError
    # For v0.10.x
    config_param :backend_library, :string, :default => 'geoip'
  end

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  # To support Fluentd v0.10.57 or earlier
  unless method_defined?(:router)
    define_method("router") { Fluent::Engine }
  end

  def configure(conf)
    super
    Fluent::GeoIP.class_eval do
      include Fluent::Mixin::RewriteTagName
    end
    # For v0.10.x
    if @backend_library.is_a?(String)
      @backend_library = @backend_library.to_sym
      unless Fluent::GeoIP::BACKEND_LIBRARIES.include?(@backend_library)
        raise Fluent::ConfigError, "valid options are #{Fluent::GeoIP::BACKEND_LIBRARIES.join(',')} but got #{@backend_library}"
      end
    end
    @geoip = Fluent::GeoIP.new(self, conf)
  end

  def start
    super
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def shutdown
    super
  end

  def write(chunk)
    es = Fluent::MultiEventStream.new
    tag = ""
    chunk.msgpack_each do |_tag, time, record|
      tag = _tag
      es.add(time, @geoip.add_geoip_field(record))
    end
    router.emit_stream(tag, es)
  end
end
