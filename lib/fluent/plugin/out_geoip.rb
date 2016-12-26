require 'fluent/mixin/rewrite_tag_name'

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

  config_param :backend_library, :enum, :list => [:geoip, :geoip2_compat, :geoip2_c], :default => :geoip

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  # To support Fluentd v0.10.57 or earlier
  unless method_defined?(:router)
    define_method("router") { Fluent::Engine }
  end

  def initialize
    require 'fluent/plugin/geoip'

    super
  end

  def configure(conf)
    super
    Fluent::GeoIP.class_eval do
      include Fluent::Mixin::RewriteTagName
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
