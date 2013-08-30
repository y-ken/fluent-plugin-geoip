class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)
  
  GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region)
  config_param :geoip_database, :string, :default => 'data/GeoLiteCity.dat'
  config_param :geoip_lookup_key, :string, :default => 'host'

  include Fluent::HandleTagNameMixin
  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false

  def initialize
    require 'geoip'
    super
  end
  
  def configure(conf)
    super

    @geoip_keys_map = Hash.new
    conf.keys.select{|k| k =~ /^enable_key_/}.each do |key|
      geoip_key_name = key.sub('enable_key_','')
      raise Fluent::ConfigError, "geoip: unsupported key #{geoip_key_name}" unless GEOIP_KEYS.include?(geoip_key_name)
      @geoip_keys_map.store(geoip_key_name, conf[key])
    end

    if ( !@remove_tag_prefix && !@remove_tag_suffix && !@add_tag_prefix && !@add_tag_suffix )
      raise Fluent::ConfigError, "geoip: missing remove_tag_prefix, remove_tag_suffix, add_tag_prefix or add_tag_suffix."
    end

    @geoip = GeoIP::City.new(@geoip_database, :memory, false)
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
      result = @geoip.look_up(record[@geoip_lookup_key])
      if result.nil?
        $log.warn "geoip: lookup failed. ", :record => record[@geoip_lookup_key]
      else
        @geoip_keys_map.each do |geoip_key,record_key|
          record.store(record_key, result[geoip_key.to_sym])
        end
      end
      Fluent::Engine.emit(tag, time, record)
    end
  end
end
