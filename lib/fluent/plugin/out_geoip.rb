class Fluent::GeoipOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('geoip', self)
  
  def initialize
    require 'geoip.bundle'
    super
  end

  config_param :geoip_database, :string, :default => 'data/GeoLiteCity.dat'

  include Fluent::HandleTagNameMixin
  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false

  def configure(conf)
    super
    
    if ( !@remove_tag_prefix && !@remove_tag_suffix && !@add_tag_prefix && !@add_tag_suffix )
      raise ConfigError, "geoip: Set remove_tag_prefix, remove_tag_suffix, add_tag_prefix or add_tag_suffix."
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
      result = @geoip.look_up(record['host'])
      $log.info "geoip: #{record['host']} : #{result}"
      Fluent::Engine.emit(tag, time, result)
    end
  end
end
