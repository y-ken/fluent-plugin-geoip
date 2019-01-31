require 'fluent/plugin/filter'

require 'geoip'
require 'yajl'
unless {}.respond_to?(:dig)
  begin
    # backport_dig is faster than dig_rb so prefer backport_dig.
    # And Fluentd v1.0.1 uses backport_dig
    require 'backport_dig'
  rescue LoadError
    require 'dig_rb'
  end
end

module Fluent::Plugin
  class GeoipFilter < Fluent::Plugin::Filter
    Fluent::Plugin.register_filter('geoip', self)

    BACKEND_LIBRARIES = [:geoip, :geoip2_compat, :geoip2_c]

    REGEXP_PLACEHOLDER_SINGLE = /^\$\{
                                  (?<geoip_key>-?[^\[\]]+)
                                    \[
                                      (?:(?<dq>")|(?<sq>'))
                                        (?<record_key>-?(?(<dq>)[^"{}]+|[^'{}]+))
                                      (?(<dq>)"|')
                                    \]
                                  \}$/x
    REGEXP_PLACEHOLDER_SCAN = /['"]?(\$\{[^\}]+?\})['"]?/

    GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region)
    GEOIP2_COMPAT_KEYS = %w(city country_code country_name latitude longitude postal_code region region_name)

    helpers :compat_parameters, :inject, :record_accessor

    config_param :geoip_database, :string, default: File.expand_path('../../../data/GeoLiteCity.dat', __dir__)
    config_param :geoip2_database, :string, default: File.expand_path('../../../data/GeoLite2-City.mmdb', __dir__)
    config_param :geoip_lookup_keys, :array, value_type: :string, default: ["host"]
    config_param :geoip_lookup_key, :string, default: nil, deprecated: "Use geoip_lookup_keys instead"
    config_param :skip_adding_null_record, :bool, default: false

    config_set_default :@log_level, "warn"

    config_param :backend_library, :enum, list: BACKEND_LIBRARIES, default: :geoip2_c

    def configure(conf)
      compat_parameters_convert(conf, :inject)
      super

      @map = {}
      if @geoip_lookup_key
        @geoip_lookup_keys = @geoip_lookup_key.split(/\s*,\s*/)
      end

      @geoip_lookup_keys.each do |key|
        if key.include?(".") && !key.start_with?("$")
          $log.warn("#{key} is not treated as nested attributes")
        end
      end
      @geoip_lookup_accessors = @geoip_lookup_keys.map {|key| [key, record_accessor_create(key)] }.to_h

      if conf.keys.any? {|k| k =~ /^enable_key_/ }
        raise Fluent::ConfigError, "geoip: 'enable_key_*' config format is obsoleted. use <record></record> directive instead."
      end

      # <record></record> directive
      conf.elements.select { |element| element.name == 'record' }.each { |element|
        element.each_pair { |k, v|
          element.has_key?(k) # to suppress unread configuration warning
          v = v[1..v.size-2] if quoted_value?(v)
          @map[k] = v
          validate_json = Proc.new {
            begin
              dummy_text = Yajl::Encoder.encode('dummy_text')
              Yajl::Parser.parse(v.gsub(REGEXP_PLACEHOLDER_SCAN, dummy_text))
            rescue Yajl::ParseError => e
              message = "geoip: failed to parse '#{v}' as json."
              log.error message, error: e
              raise Fluent::ConfigError, message
            end
          }
          validate_json.call if json?(v.tr('\'"\\', ''))
        }
      }

      @placeholder_keys = @map.values.join.scan(REGEXP_PLACEHOLDER_SCAN).map{|placeholder| placeholder[0] }.uniq
      @placeholder_keys.each do |key|
        m = key.match(REGEXP_PLACEHOLDER_SINGLE)
        raise Fluent::ConfigError, "Invalid placeholder attributes: #{key}" unless m
        geoip_key = m[:geoip_key]
        case @backend_library
        when :geoip
          raise Fluent::ConfigError, "#{@backend_library}: unsupported key #{geoip_key}" unless GEOIP_KEYS.include?(geoip_key)
        when :geoip2_compat
          raise Fluent::ConfigError, "#{@backend_library}: unsupported key #{geoip_key}" unless GEOIP2_COMPAT_KEYS.include?(geoip_key)
        when :geoip2_c
          # Nothing to do.
          # We cannot define supported key(s) before we fetch values from GeoIP2 database
          # because geoip2_c can fetch any fields in GeoIP2 database.
        end
      end

      @geoip = load_database
    end

    def filter(tag, time, record)
      filtered_record = add_geoip_field(record)
      if filtered_record
        record = filtered_record
      end
      record = inject_values_to_record(tag, time, record)
      record
    end

    def multi_workers_ready?
      true
    end

    private

    def add_geoip_field(record)
      placeholder = create_placeholder(geolocate(get_address(record)))
      return record if @skip_adding_null_record && placeholder.values.first.nil?
      @map.each do |record_key, value|
        if value.match(REGEXP_PLACEHOLDER_SINGLE) #|| value.match(REGEXP_PLACEHOLDER_BRACKET_SINGLE)
          rewrited = placeholder[value]
        elsif json?(value)
          rewrited = value.gsub(REGEXP_PLACEHOLDER_SCAN) {|match|
            match = match[1..match.size-2] if quoted_value?(match)
            Yajl::Encoder.encode(placeholder[match])
          }
          rewrited = parse_json(rewrited)
        else
          rewrited = value.gsub(REGEXP_PLACEHOLDER_SCAN, placeholder)
        end
        record[record_key] = rewrited
      end
      record
    end

    def json?(text)
      text.match(/^\[.+\]$/) || text.match(/^\{.+\}$/)
    end

    def quoted_value?(text)
      # to improbe compatibility with fluentd v1-config
      text.match(/(^'.+'$|^".+"$)/)
    end

    def parse_json(message)
      begin
        return Yajl::Parser.parse(message)
      rescue Yajl::ParseError => e
        log.info "geoip: failed to parse '#{message}' as json.", error_class: e.class, error: e.message
        return nil
      end
    end

    def get_address(record)
      address = {}
      @geoip_lookup_accessors.each do |field, accessor|
        address[field] = accessor.call(record)
      end
      address
    end

    def geolocate(addresses)
      geodata = {}
      addresses.each do |field, ip|
        geo = nil
        if ip
          geo = if @geoip.respond_to?(:look_up)
                  @geoip.look_up(ip)
                else
                  @geoip.lookup(ip)
                end
        end
        geodata[field] = geo
      end
      geodata
    end

    def create_placeholder(geodata)
      placeholder = {}
      @placeholder_keys.each do |placeholder_key|
        position = placeholder_key.match(REGEXP_PLACEHOLDER_SINGLE)
        next if position.nil? or geodata[position[:record_key]].nil?
        keys = [position[:record_key]] + position[:geoip_key].split('.').map(&:to_sym)
        value = geodata.dig(*keys)
        value = if [:latitude, :longitude].include?(keys.last)
                  value || 0.0
                else
                  value
                end
        placeholder[placeholder_key] = value
      end
      placeholder
    end

    def load_database
      case @backend_library
      when :geoip
        ::GeoIP::City.new(@geoip_database, :memory, false)
      when :geoip2_compat
        require 'geoip2_compat'
        GeoIP2Compat.new(@geoip2_database)
      when :geoip2_c
        require 'geoip2'
        GeoIP2::Database.new(@geoip2_database)
      end
    rescue LoadError
      raise Fluent::ConfigError, "You must install #{@backend_library} gem."
    end
  end
end
