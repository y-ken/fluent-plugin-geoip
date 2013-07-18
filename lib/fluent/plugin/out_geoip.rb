class Fluent::GeoipOutput < Fluent::Output
  Fluent::Plugin.register_output('geoip', self)
  
  def initialize
    require 'geoip'
    super
  end

  config_param :geoip_database, :string

  def configure(conf)
    super

    @geoip = GeoIP.new(@geoip_database)
  end

  def emit(tag, es, chain)
    es.each do |time,record|
      $log.info "geoip: #{record['host']} : #{@geoip.send(:city, record['host'])}"
    end

    chain.next
  end
end
