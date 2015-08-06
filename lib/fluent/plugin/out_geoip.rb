require 'fluent/mixin/rewrite_tag_name'

class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)

  REGEXP_PLACEHOLDER_SINGLE = /^\$\{(?<geoip_key>-?[^\[]+)\[['"](?<record_key>-?[^'"]+)['"]\]\}$/
  REGEXP_PLACEHOLDER_SCAN = /['"]?(\$\{[^\}]+?\})['"]?/

  GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region)

  config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
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

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def initialize
    require 'fluent/plugin/geoip_supplement'

    super
  end

  def configure(conf)
    super
    Fluent::GeoIPSupplement.class_eval do
      include Fluent::Mixin::RewriteTagName
    end
    @supplement = Fluent::GeoIPSupplement.new(self, conf)
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
    chunk.msgpack_each do |tag, time, record|
      Fluent::Engine.emit(tag, time, @supplement.add_geoip_field(record))
    end
  end
end
