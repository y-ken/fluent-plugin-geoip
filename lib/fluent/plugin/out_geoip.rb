class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)

  GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region lonlat)
  config_param :geoip_database, :string, :default => File.dirname(__FILE__) + '/../../../data/GeoLiteCity.dat'
  config_param :geoip_lookup_key, :string, :default => 'host'

  include Fluent::HandleTagNameMixin
  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false
  attr_reader :geoip_keys_map

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
      @geoip_keys_map.store(geoip_key_name, conf[key].split(/\s*,\s*/))
    end

    @geoip_lookup_key = @geoip_lookup_key.split(/\s*,\s*/).map {|lookupkey|
      lookupkey.split(".")
    }
    if @geoip_lookup_key.size > 1
      @geoip_keys_map.each{|name, key|
        if key.size != @geoip_lookup_key.size
          raise Fluent::ConfigError, "geoip: lookup key length is not match #{name}"
        end
      }
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
      Fluent::Engine.emit(tag, time, add_geoip_field(record))
    end
  end

  def get_address(record)
    @geoip_lookup_key.map {|key|
      obj = record
      key.each {|k|
        break obj = nil if not obj.has_key?(k)
        obj = obj[k]
      }
      obj
    }
  end

  def add_geoip_field(record)
    addresses = get_address(record)
    return record if addresses.all? {|address| address == nil }
    results = addresses.map {|address| @geoip.look_up(address) }
    return record if results.all? {|result| result == nil }
    @geoip_keys_map.each do |geoip_key,record_keys|
      record_keys.each_with_index {|record_key, idx|
        if geoip_key == 'lonlat'
          record.store(record_key, [results[idx][:longitude], results[idx][:latitude]])
        else
          record.store(record_key, results[idx][geoip_key.to_sym])
        end
      }
    end
    return record
  end
end
