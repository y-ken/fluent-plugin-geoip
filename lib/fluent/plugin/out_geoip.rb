require 'fluent/plugin/output'
require 'fluent/plugin/geoip'

class Fluent::Plugin::GeoipOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('geoip', self)

  helpers :event_emitter, :inject, :compat_parameters

  config_param :geoip_database, :string, default: File.expand_path('../../../data/GeoLiteCity.dat', __dir__)
  config_param :geoip2_database, :string, default: File.expand_path('../../../data/GeoLite2-City.mmdb', __dir__)
  config_param :geoip_lookup_key, :string, default: 'host'
  config_param :tag, :string, default: nil
  config_param :skip_adding_null_record, :bool, default: false

  config_param :flush_interval, :time, default: 0
  config_set_default :@log_level, "warn"

  config_param :backend_library, :enum, list: Fluent::GeoIP::BACKEND_LIBRARIES, default: :geoip2_c
  config_section :buffer do
    config_set_default :@type, :memory
    config_set_default :chunk_keys, ['tag']
  end

  def configure(conf)
    compat_parameters_convert(conf, :buffer, default_chunk_key: 'tag')
    super
    raise Fluetn::ConfigError, "chunk key must include 'tag'" unless @chunk_key_tag
    placeholder_validate!(:tag, @tag) if @tag
    @geoip = Fluent::GeoIP.new(self, conf)
  end

  def format(tag, time, record)
    record = inject_values_to_record(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def formatted_to_msgpack_binary
    true
  end

  def write(chunk)
    es = Fluent::MultiEventStream.new
    tag = ""
    chunk.each do |_tag, time, record|
      tag = _tag
      es.add(time, @geoip.add_geoip_field(record))
    end
    tag = extract_placeholders(@tag, chunk.metadata) if @tag
    router.emit_stream(tag, es)
  end
end
