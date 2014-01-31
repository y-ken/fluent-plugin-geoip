class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)

  GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region lonlat)
  config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
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

    @geoip_lookup_key = @geoip_lookup_key.split(".")


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
      Fluent::Engine.emit(tag, time, add_geoip_field(record))
    end
  end

  def get_address(record)
    obj = record
    @geoip_lookup_key.each do |key|
      return nil if not obj.has_key?(key)
      obj = obj[key]
    end
    obj
  end

  def add_geoip_field(record)
    address = get_address(record)
    return record if address.nil?
    result = @geoip.look_up(address)
    return record if result.nil?
    @geoip_keys_map.each do |geoip_key,record_key|
      if geoip_key == 'lonlat'
        record.store(record_key, [result[:longitude], result[:latitude]])
      else
        record.store(record_key, result[geoip_key.to_sym])
      end
    end
    return record
  end
end
