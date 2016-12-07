require 'geoip'
require 'yajl'

module Fluent
  class GeoIP
    REGEXP_PLACEHOLDER_SINGLE = /^\$\{(?<geoip_key>-?[^\[]+)\[['"](?<record_key>-?[^'"]+)['"]\]\}$/
    REGEXP_PLACEHOLDER_SCAN = /['"]?(\$\{[^\}]+?\})['"]?/

    GEOIP_KEYS = %w(city latitude longitude country_code3 country_code country_name dma_code area_code region)

    attr_reader :log

    def initialize(plugin, conf)
      @map = {}
      plugin.geoip_lookup_key = plugin.geoip_lookup_key.split(/\s*,\s*/)
      @geoip_lookup_key = plugin.geoip_lookup_key
      @skip_adding_null_record = plugin.skip_adding_null_record
      @log = plugin.log

      # enable_key_* format (legacy format)
      conf.keys.select{|k| k =~ /^enable_key_/}.each do |key|
        geoip_key = key.sub('enable_key_','')
        raise Fluent::ConfigError, "geoip: unsupported key #{geoip_key}" unless GEOIP_KEYS.include?(geoip_key)
        @geoip_lookup_key.zip(conf[key].split(/\s*,\s*/)).each do |lookup_field,record_key|
          if record_key.nil?
            raise Fluent::ConfigError, "geoip: missing value found at '#{key} #{lookup_field}'"
          end
          @map[record_key] = "${#{geoip_key}['#{lookup_field}']}"
        end
      end
      if conf.keys.select{|k| k =~ /^enable_key_/}.size > 0
        log.warn "geoip: 'enable_key_*' config format is obsoleted. use <record></record> directive for now."
        log.warn "geoip: for further details referable to https://github.com/y-ken/fluent-plugin-geoip"
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
              raise Fluent::ConfigError, "geoip: failed to parse '#{v}' as json."
            end
          }
          validate_json.call if json?(v.tr('\'"\\', ''))
        }
      }
      @placeholder_keys = @map.values.join.scan(REGEXP_PLACEHOLDER_SCAN).map{ |placeholder| placeholder[0] }.uniq
      @placeholder_keys.each do |key|
        geoip_key = key.match(REGEXP_PLACEHOLDER_SINGLE)[:geoip_key]
        raise Fluent::ConfigError, "geoip: unsupported key #{geoip_key}" unless GEOIP_KEYS.include?(geoip_key)
      end

      if plugin.is_a?(Fluent::BufferedOutput)
        @placeholder_expander = PlaceholderExpander.new
        unless have_tag_option?(plugin)
          raise Fluent::ConfigError, "geoip: required at least one option of 'tag', 'remove_tag_prefix', 'remove_tag_suffix', 'add_tag_prefix', 'add_tag_suffix'."
        end
      end

      @geoip = ::GeoIP::City.new(plugin.geoip_database, :memory, false)
    end

    def add_geoip_field(record)
      placeholder = create_placeholder(geolocate(get_address(record)))
      return record if @skip_adding_null_record && placeholder.values.first.nil?
      @map.each do |record_key, value|
        if value.match(REGEXP_PLACEHOLDER_SINGLE)
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
      return record
    end

    private

    def have_tag_option?(plugin)
      plugin.tag ||
        plugin.remove_tag_prefix || plugin.remove_tag_suffix ||
        plugin.add_tag_prefix || plugin.add_tag_suffix
    end

    def json?(text)
      text.match(/^\[.+\]$/) || text.match(/^\{.+\}$/)
    end

    def quoted_value?(text)
      # to improbe compatibility with fluentd v1-config
      trim_quote = text[1..text.size-2]
      text.match(/(^'.+'$|^".+"$)/)
    end

    def parse_json(message)
      begin
        return Yajl::Parser.parse(message)
      rescue Yajl::ParseError => e
        log.info "geoip: failed to parse '#{message}' as json.", :error_class => e.class, :error => e.message
        return nil
      end
    end

    def get_address(record)
      address = {}
      @geoip_lookup_key.each do |field|
        address[field] = record[field]; next if not record[field].nil?
        key = field.split('.')
        obj = record
        key.each {|k|
          break obj = nil if not obj.has_key?(k)
          obj = obj[k]
        }
        address[field] = obj
      end
      address
    end

    def geolocate(addresses)
      geodata = {}
      addresses.each do |field, ip|
        geo = ip.nil? ? nil : @geoip.look_up(ip)
        geodata[field] = geo
      end
      geodata
    end

    def create_placeholder(geodata)
      placeholder = {}
      @placeholder_keys.each do |placeholder_key|
        position = placeholder_key.match(REGEXP_PLACEHOLDER_SINGLE)
        next if position.nil? or geodata[position[:record_key]].nil?
        placeholder[placeholder_key] = geodata[position[:record_key]][position[:geoip_key].to_sym]
      end
      placeholder
    end
  end
end
