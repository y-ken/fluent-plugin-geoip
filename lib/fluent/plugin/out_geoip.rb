class Fluent::GeoipOutput < Fluent::Output
  Fluent::Plugin.register_output('geoip', self)
  
  def initialize
    require 'geoip.bundle'
    super
  end

  config_param :geoip_database, :string, :default => 'data/GeoLiteCity.dat'

  def configure(conf)
    super

    @geoip = GeoIP::City.new(@geoip_database)
  end

  def emit(tag, es, chain)
    es.each do |time,record|
      $log.info "geoip: #{record['host']} : #{@geoip.look_up(record['host'])}"
    end

    chain.next
  end
end
