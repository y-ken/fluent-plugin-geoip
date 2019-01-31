require 'helper'
require 'fluent/plugin/filter_geoip'
require 'fluent/test/driver/filter'

class GeoipFilterTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    @time = Fluent::Engine.now
  end

  CONFIG = %[
    geoip_lookup_keys  host
    <record>
      geoip_city ${city.names.en['host']}
    </record>
  ]

  def create_driver(conf = CONFIG, syntax: :v1)
    Fluent::Test::Driver::Filter.new(Fluent::Plugin::GeoipFilter).configure(conf, syntax: syntax)
  end

  def filter(config, messages, syntax: :v1)
    d = create_driver(config, syntax: syntax)
    yield d if block_given?
    d.run(default_tag: "input.access") {
      messages.each {|message|
        d.feed(@time, message)
      }
    }
    d.filtered_records
  end

  def setup_geoip_mock(d)
    plugin = d.instance
    db = Object.new
    def db.lookup(ip)
      {}
    end
    plugin.instance_variable_set(:@geoip, db)
  end

  sub_test_case "configure" do
    test "empty" do
      assert_nothing_raised {
        create_driver('')
      }
    end

    test "obsoleted configuration" do
      assert_raise(Fluent::ConfigError) {
        create_driver('enable_key_city geoip_city')
      }
    end

    test "deprecated configuration geoip_lookup_key" do
      conf = %[
        geoip_lookup_key  host,ip
        <record>
          geoip_city ${city['host']}
        </record>
      ]
      d = create_driver(conf)
      assert_equal(["host", "ip"], d.instance.geoip_lookup_keys)
    end

    test "invalid json structure w/ Ruby hash like" do
      assert_raise(Fluent::ConfigParseError) {
        create_driver %[
          geoip_lookup_keys host
          <record>
            invalid_json    {"foo" => 123}
          </record>
        ]
      }
    end

    test "invalid json structure w/ unquoted string literal" do
      assert_raise(Fluent::ConfigParseError) {
        create_driver %[
          geoip_lookup_keys host
          <record>
            invalid_json    {"foo" : string, "bar" : 123}
          </record>
        ]
      }
    end

    test "dotted key is not treated as nested attributes" do
      mock($log).warn("host.ip is not treated as nested attributes")
      create_driver %[
        geoip_lookup_keys host.ip
        <record>
          city ${city.names.en['host.ip']}
        </record>
      ]
    end

    test "nested attributes bracket style" do
      mock($log).warn(anything).times(0)
      create_driver %[
        geoip_lookup_keys  $["host"]["ip"]
        <record>
          geoip_city ${city.names.en['$["host"]["ip"]']}
        </record>
      ]
    end

    test "nested attributes dot style" do
      mock($log).warn(anything).times(0)
      create_driver %[
        geoip_lookup_keys  $.host.ip
        <record>
          geoip_city ${city['$.host.ip']}
        </record>
      ]
    end

    test "invalid placeholder attributes" do
      assert_raise(Fluent::ConfigParseError) do
        create_driver %[
          geoip_lookup_keys host
          backend_library geoip2_c

          <record>
            geoip.city_name       ${city.names.en["host]}
          </record>
        ]
      end
    end

    data(geoip: "geoip",
         geoip2_compat: "geoip2_compat")
    test "unsupported key" do |backend|
      assert_raise(Fluent::ConfigError.new("#{backend}: unsupported key unknown")) do
        create_driver %[
          backend_library #{backend}
          <record>
            city ${unknown["host"]}
          </record>
        ]
      end
    end

    data(geoip: ["geoip", '${city["host"]}'],
         geoip2_compat: ["geoip2_compat", '${city["host"]}'],
         geoip2_c: ["geoip2_c", '${city.names.en["host"]}'])
    test "supported backend" do |(backend, placeholder)|
      create_driver %[
        backend_library #{backend}
        <record>
          city #{placeholder}
        </record>
      ]
    end

    test "unsupported backend" do
      assert_raise(Fluent::ConfigError) do
        create_driver %[
          backend_library hive_geoip2
          <record>
            city ${city["host"]}
          </record>
        ]
      end
    end
  end

  sub_test_case "geoip2_c" do
    def test_filter_with_dot_key
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys ip.origin, ip.dest
        <record>
          origin_country  ${country.iso_code['ip.origin']}
          dest_country    ${country.iso_code['ip.dest']}
        </record>
      ]
      messages = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'}
      ]
      expected = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8',
         'origin_country' => 'US', 'dest_country' => 'US'}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_unknown_address
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys host
        <record>
          geoip_city      ${city.names.en['host']}
          geopoint        [${location.longitude['host']}, ${location.latitude['host']}]
        </record>
        skip_adding_null_record false
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]},
        {'host' => '0', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys host
        <record>
          geoip_city      ${city.names.en['host']}
          geopoint        [${location.longitude['host']}, ${location.latitude['host']}]
        </record>
        skip_adding_null_record true
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot',
         'geoip_city' => 'Mountain View', 'geopoint' => [-122.0574, 37.419200000000004]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys $.from.ip
        <record>
          from_city       ${city.names.en['$.from.ip']}
          from_country    ${country.names.en['$.from.ip']}
          latitude        ${location.latitude['$.from.ip']}
          longitude       ${location.longitude['$.from.ip']}
          float_concat    ${location.latitude['$.from.ip']},${location.longitude['$.from.ip']}
          float_array     [${location.longitude['$.from.ip']}, ${location.latitude['$.from.ip']}]
          float_nest      { "lat" : ${location.latitude['$.from.ip']}, "lon" : ${location.longitude['$.from.ip']}}
          string_concat   ${city.names.en['$.from.ip']},${country.names.en['$.from.ip']}
          string_array    [${city.names.en['$.from.ip']}, ${country.names.en['$.from.ip']}]
          string_nest     { "city" : ${city.names.en['$.from.ip']}, "country_name" : ${country.names.en['$.from.ip']}}
          unknown_city    ${city.names.en['unknown_key']}
          undefined       ${city.names.en['undefined']}
          broken_array1   [${location.longitude['$.from.ip']}, ${location.latitude['undefined']}]
          broken_array2   [${location.longitude['undefined']}, ${location.latitude['undefined']}]
        </record>
      ]
      messages = [
        { 'from' => {'ip' => '66.102.3.80'} },
        { 'message' => 'missing field' },
      ]
      expected = [
        {
          'from' => {'ip' => '66.102.3.80'},
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'latitude' => 37.419200000000004,
          'longitude' => -122.0574,
          'float_concat' => '37.419200000000004,-122.0574',
          'float_array' => [-122.0574, 37.419200000000004],
          'float_nest' => { 'lat' => 37.4192000000000004, 'lon' => -122.0574 },
          'string_concat' => 'Mountain View,United States',
          'string_array' => ["Mountain View", "United States"],
          'string_nest' => {"city" => "Mountain View", "country_name" => "United States"},
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [-122.0574, nil],
          'broken_array2' => [nil, nil]
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'latitude' => nil,
          'longitude' => nil,
          'float_concat' => ',',
          'float_array' => [nil, nil],
          'float_nest' => { 'lat' => nil, 'lon' => nil },
          'string_concat' => ',',
          'string_array' => [nil, nil],
          'string_nest' => { "city" => nil, "country_name" => nil },
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [nil, nil],
          'broken_array2' => [nil, nil]
        },
      ]
      filtered = filter(config, messages, syntax: :v0)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys $.from.ip, $.to.ip
        <record>
          from_city       ${city.names.en['$.from.ip']}
          to_city         ${city.names.en['$.to.ip']}
          from_country    ${country.names.en['$.from.ip']}
          to_country      ${country.names.en['$.to.ip']}
          string_array    [${country.names.en['$.from.ip']}, ${country.names.en['$.to.ip']}]
        </record>
      ]
      messages = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
        {'message' => 'missing field'}
      ]
      expected = [
        {
          'from' => { 'ip' => '66.102.3.80' },
          'to' => { 'ip' => '125.54.15.42' },
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'to_city' => 'Tokorozawa',
          'to_country' => 'Japan',
          'string_array' => ['United States', 'Japan']
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'to_city' => nil,
          'to_country' => nil,
          'string_array' => [nil, nil]
        }
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        backend_library   geoip2_c
        geoip_lookup_keys host
        <record>
          location_properties  '{ "country_code" : "${country.iso_code["host"]}", "lat": ${location.latitude["host"]}, "lon": ${location.longitude["host"]} }'
          location_string      ${location.latitude['host']},${location.longitude['host']}
          location_string2     ${country.iso_code["host"]}
          location_array       "[${location.longitude['host']},${location.latitude['host']}]"
          location_array2      '[${location.longitude["host"]},${location.latitude["host"]}]'
          peculiar_pattern     '[GEOIP] message => {"lat":${location.latitude["host"]}, "lon":${location.longitude["host"]}}'
        </record>
      ]
    end

    def test_filter_quoted_record
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.419200000000004,
            'lon' => -122.0574
          },
          'location_string' => '37.419200000000004,-122.0574',
          'location_string2' => 'US',
          'location_array' => [-122.0574, 37.419200000000004],
          'location_array2' => [-122.0574, 37.419200000000004],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_v1_config_compatibility
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.419200000000004,
            'lon' => -122.0574
          },
          'location_string' => '37.419200000000004,-122.0574',
          'location_string2' => 'US',
          'location_array' => [-122.0574, 37.419200000000004],
          'location_array2' => [-122.0574, 37.419200000000004],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys host
        <record>
          location_properties  {
            "city": "${city.names.en['host']}",
            "country_code": "${country.iso_code['host']}",
            "latitude": "${location.latitude['host']}",
            "longitude": "${location.longitude['host']}"
        }
        </record>
      ]
      messages = [
        { 'host' => '66.102.3.80', 'message' => 'valid ip' }
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          "location_properties" => {
            "city" => "Mountain View",
            "country_code" => "US",
            "latitude" => 37.419200000000004,
            "longitude" => -122.0574
          }
        }
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_when_latitude_longitude_is_nil
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys  host
        <record>
          latitude  ${location.latitude['host']}
          longitude ${location.longitude['host']}
        </record>
      ]
      messages = [
        { "host" => "180.94.85.84", "message" => "nil latitude and longitude" }
      ]
      expected = [
        {
          "host" => "180.94.85.84",
          "message" => "nil latitude and longitude",
          "latitude" => 0.0,
          "longitude" => 0.0
        }
      ]
      filtered = filter(config, messages) do |d|
        setup_geoip_mock(d)
      end
      assert_equal(expected, filtered)
    end

    def test_filter_nested_attr_bracket_style_double_quote
      config = %[
        backend_library geoip2_c
        geoip_lookup_keys  $["host"]["ip"]
        <record>
          geoip_city ${city.names.en['$["host"]["ip"]']}
        </record>
      ]
      messages = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'},
        {'message' => 'missing field'}
      ]
      expected = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip', 'geoip_city' => 'Mountain View'},
        {'message' => 'missing field', 'geoip_city' => nil}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_nested_attr_bracket_style_single_quote
      config = %[
        backend_library geoip2_c
        geoip_lookup_keys  $['host']['ip']
        <record>
          geoip_city ${city.names.en["$['host']['ip']"]}
        </record>
      ]
      messages = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'},
        {'message' => 'missing field'}
      ]
      expected = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip', 'geoip_city' => 'Mountain View'},
        {'message' => 'missing field', 'geoip_city' => nil}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end
  end

  sub_test_case "geoip2_compat" do
    def test_filter_with_dot_key
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys ip.origin, ip.dest
        <record>
          origin_country  ${country_code['ip.origin']}
          dest_country    ${country_code['ip.dest']}
        </record>
      ]
      messages = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'}
      ]
      expected = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8',
         'origin_country' => 'US', 'dest_country' => 'US'}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_unknown_address
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record false
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]},
        {'host' => '0', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record true
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot',
         'geoip_city' => 'Mountain View', 'geopoint' => [-122.0574, 37.419200000000004]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys $.from.ip
        <record>
          from_city       ${city['$.from.ip']}
          from_country    ${country_name['$.from.ip']}
          latitude        ${latitude['$.from.ip']}
          longitude       ${longitude['$.from.ip']}
          float_concat    ${latitude['$.from.ip']},${longitude['$.from.ip']}
          float_array     [${longitude['$.from.ip']}, ${latitude['$.from.ip']}]
          float_nest      { "lat" : ${latitude['$.from.ip']}, "lon" : ${longitude['$.from.ip']}}
          string_concat   ${city['$.from.ip']},${country_name['$.from.ip']}
          string_array    [${city['$.from.ip']}, ${country_name['$.from.ip']}]
          string_nest     { "city" : ${city['$.from.ip']}, "country_name" : ${country_name['$.from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['$.from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
      ]
      messages = [
        { 'from' => {'ip' => '66.102.3.80'} },
        { 'message' => 'missing field' },
      ]
      expected = [
        {
          'from' => {'ip' => '66.102.3.80'},
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'latitude' => 37.419200000000004,
          'longitude' => -122.0574,
          'float_concat' => '37.419200000000004,-122.0574',
          'float_array' => [-122.0574, 37.419200000000004],
          'float_nest' => { 'lat' => 37.4192000000000004, 'lon' => -122.0574 },
          'string_concat' => 'Mountain View,United States',
          'string_array' => ["Mountain View", "United States"],
          'string_nest' => {"city" => "Mountain View", "country_name" => "United States"},
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [-122.0574, nil],
          'broken_array2' => [nil, nil]
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'latitude' => nil,
          'longitude' => nil,
          'float_concat' => ',',
          'float_array' => [nil, nil],
          'float_nest' => { 'lat' => nil, 'lon' => nil },
          'string_concat' => ',',
          'string_array' => [nil, nil],
          'string_nest' => { "city" => nil, "country_name" => nil },
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [nil, nil],
          'broken_array2' => [nil, nil]
        },
      ]
      filtered = filter(config, messages, syntax: :v0)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys $.from.ip, $.to.ip
        <record>
          from_city       ${city['$.from.ip']}
          to_city         ${city['$.to.ip']}
          from_country    ${country_name['$.from.ip']}
          to_country      ${country_name['$.to.ip']}
          string_array    [${country_name['$.from.ip']}, ${country_name['$.to.ip']}]
        </record>
      ]
      messages = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
        {'message' => 'missing field'}
      ]
      expected = [
        {
          'from' => { 'ip' => '66.102.3.80' },
          'to' => { 'ip' => '125.54.15.42' },
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'to_city' => 'Tokorozawa',
          'to_country' => 'Japan',
          'string_array' => ['United States', 'Japan']
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'to_city' => nil,
          'to_country' => nil,
          'string_array' => [nil, nil]
        }
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        backend_library   geoip2_compat
        geoip_lookup_keys host
        <record>
          location_properties  '{ "country_code" : "${country_code["host"]}", "lat": ${latitude["host"]}, "lon": ${longitude["host"]} }'
          location_string      ${latitude['host']},${longitude['host']}
          location_string2     ${country_code["host"]}
          location_array       "[${longitude['host']},${latitude['host']}]"
          location_array2      '[${longitude["host"]},${latitude["host"]}]'
          peculiar_pattern     '[GEOIP] message => {"lat":${latitude["host"]}, "lon":${longitude["host"]}}'
        </record>
      ]
    end

    def test_filter_quoted_record
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.419200000000004,
            'lon' => -122.0574
          },
          'location_string' => '37.419200000000004,-122.0574',
          'location_string2' => 'US',
          'location_array' => [-122.0574, 37.419200000000004],
          'location_array2' => [-122.0574, 37.419200000000004],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_v1_config_compatibility
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.419200000000004,
            'lon' => -122.0574
          },
          'location_string' => '37.419200000000004,-122.0574',
          'location_string2' => 'US',
          'location_array' => [-122.0574, 37.419200000000004],
          'location_array2' => [-122.0574, 37.419200000000004],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys host
        <record>
          location_properties  {
            "city": "${city['host']}",
            "country_code": "${country_code['host']}",
            "latitude": "${latitude['host']}",
            "longitude": "${longitude['host']}"
        }
        </record>
      ]
      messages = [
        { 'host' => '66.102.3.80', 'message' => 'valid ip' }
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          "location_properties" => {
            "city" => "Mountain View",
            "country_code" => "US",
            "latitude" => 37.419200000000004,
            "longitude" => -122.0574
          }
        }
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_when_latitude_longitude_is_nil
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_keys  host
        <record>
          latitude  ${latitude['host']}
          longitude ${longitude['host']}
        </record>
      ]
      messages = [
        { "host" => "180.94.85.84", "message" => "nil latitude and longitude" }
      ]
      expected = [
        {
          "host" => "180.94.85.84",
          "message" => "nil latitude and longitude",
          "latitude" => 0.0,
          "longitude" => 0.0
        }
      ]
      filtered = filter(config, messages) do |d|
        setup_geoip_mock(d)
      end
      assert_equal(expected, filtered)
    end
  end

  sub_test_case "geoip legacy" do
    def test_filter
      config = %[
        backend_library geoip
        geoip_lookup_keys  host
        <record>
          geoip_city ${city['host']}
        </record>
      ]
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'},
        {'message' => 'missing field'},
      ]
      expected = [
        {'host' => '66.102.3.80', 'message' => 'valid ip', 'geoip_city' => 'Mountain View'},
        {'message' => 'missing field', 'geoip_city' => nil},
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_dot_key
      config = %[
        backend_library geoip
        geoip_lookup_keys ip.origin, ip.dest
        <record>
          origin_country  ${country_code['ip.origin']}
          dest_country    ${country_code['ip.dest']}
        </record>
      ]
      messages = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'}
      ]
      expected = [
        {'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8',
         'origin_country' => 'US', 'dest_country' => 'US'}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_nested_attr
      config = %[
        backend_library geoip
        geoip_lookup_keys  $.host.ip
        <record>
          geoip_city ${city['$.host.ip']}
        </record>
      ]
      messages = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'},
        {'message' => 'missing field'}
      ]
      expected = [
        {'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip', 'geoip_city' => 'Mountain View'},
        {'message' => 'missing field', 'geoip_city' => nil}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_unknown_address
      config = %[
        backend_library geoip
        geoip_lookup_keys host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record false
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]},
        {'host' => '0', 'message' => 'invalid ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        backend_library geoip
        geoip_lookup_keys host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record true
      ]
      # 203.0.113.1 is a test address described in RFC5737
      messages = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot'}
      ]
      expected = [
        {'host' => '203.0.113.1', 'message' => 'invalid ip'},
        {'host' => '0', 'message' => 'invalid ip'},
        {'host' => '66.102.3.80', 'message' => 'google bot',
         'geoip_city' => 'Mountain View', 'geopoint' => [-122.05740356445312, 37.4192008972168]}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_multiple_key
      config = %[
        backend_library geoip
        geoip_lookup_keys  $.from.ip, $.to.ip
        <record>
          from_city ${city['$.from.ip']}
          to_city   ${city['$.to.ip']}
        </record>
      ]
      messages = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
        {'message' => 'missing field'}
      ]
      expected = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'},
         'from_city' => 'Mountain View', 'to_city' => 'Tokorozawa'},
        {'message' => 'missing field', 'from_city' => nil, 'to_city' => nil}
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_multiple_key_multiple_record
      config = %[
        backend_library geoip
        geoip_lookup_keys  $.from.ip, $.to.ip
        <record>
          from_city    ${city['$.from.ip']}
          from_country ${country_name['$.from.ip']}
          to_city      ${city['$.to.ip']}
          to_country   ${country_name['$.to.ip']}
        </record>
      ]
      messages = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
        {'from' => {'ip' => '66.102.3.80'}},
        {'message' => 'missing field'}
      ]
      expected = [
        {
          'from' => {'ip' => '66.102.3.80'},
          'to' => {'ip' => '125.54.15.42'},
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'to_city' => 'Tokorozawa',
          'to_country' => 'Japan'
        },
        {
          'from' => {'ip' => '66.102.3.80'},
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'to_city' => nil,
          'to_country' => nil
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'to_city' => nil,
          'to_country' => nil
        }
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        backend_library geoip
        geoip_lookup_keys $.from.ip
        <record>
          from_city       ${city['$.from.ip']}
          from_country    ${country_name['$.from.ip']}
          latitude        ${latitude['$.from.ip']}
          longitude       ${longitude['$.from.ip']}
          float_concat    ${latitude['$.from.ip']},${longitude['$.from.ip']}
          float_array     [${longitude['$.from.ip']}, ${latitude['$.from.ip']}]
          float_nest      { "lat" : ${latitude['$.from.ip']}, "lon" : ${longitude['$.from.ip']}}
          string_concat   ${city['$.from.ip']},${country_name['$.from.ip']}
          string_array    [${city['$.from.ip']}, ${country_name['$.from.ip']}]
          string_nest     { "city" : ${city['$.from.ip']}, "country_name" : ${country_name['$.from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['$.from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
      ]
      messages = [
        { 'from' => {'ip' => '66.102.3.80'} },
        { 'message' => 'missing field' },
      ]
      expected = [
        {
          'from' => {'ip' => '66.102.3.80'},
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'latitude' => 37.4192008972168,
          'longitude' => -122.05740356445312,
          'float_concat' => '37.4192008972168,-122.05740356445312',
          'float_array' => [-122.05740356445312, 37.4192008972168],
          'float_nest' => { 'lat' => 37.4192008972168, 'lon' => -122.05740356445312 },
          'string_concat' => 'Mountain View,United States',
          'string_array' => ["Mountain View", "United States"],
          'string_nest' => {"city" => "Mountain View", "country_name" => "United States"},
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [-122.05740356445312, nil],
          'broken_array2' => [nil, nil]
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'latitude' => nil,
          'longitude' => nil,
          'float_concat' => ',',
          'float_array' => [nil, nil],
          'float_nest' => { 'lat' => nil, 'lon' => nil },
          'string_concat' => ',',
          'string_array' => [nil, nil],
          'string_nest' => { "city" => nil, "country_name" => nil },
          'unknown_city' => nil,
          'undefined' => nil,
          'broken_array1' => [nil, nil],
          'broken_array2' => [nil, nil]
        },
      ]
      filtered = filter(config, messages, syntax: :v0)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        backend_library geoip
        geoip_lookup_keys $.from.ip, $.to.ip
        <record>
          from_city       ${city['$.from.ip']}
          to_city         ${city['$.to.ip']}
          from_country    ${country_name['$.from.ip']}
          to_country      ${country_name['$.to.ip']}
          string_array    [${country_name['$.from.ip']}, ${country_name['$.to.ip']}]
        </record>
      ]
      messages = [
        {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
        {'message' => 'missing field'}
      ]
      expected = [
        {
          'from' => { 'ip' => '66.102.3.80' },
          'to' => { 'ip' => '125.54.15.42' },
          'from_city' => 'Mountain View',
          'from_country' => 'United States',
          'to_city' => 'Tokorozawa',
          'to_country' => 'Japan',
          'string_array' => ['United States', 'Japan']
        },
        {
          'message' => 'missing field',
          'from_city' => nil,
          'from_country' => nil,
          'to_city' => nil,
          'to_country' => nil,
          'string_array' => [nil, nil]
        }
      ]
      filtered = filter(config, messages, syntax: :v0)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        backend_library geoip
        geoip_lookup_keys host
        <record>
          location_properties  '{ "country_code" : "${country_code["host"]}", "lat": ${latitude["host"]}, "lon": ${longitude["host"]} }'
          location_string      ${latitude['host']},${longitude['host']}
          location_string2     ${country_code["host"]}
          location_array       "[${longitude['host']},${latitude['host']}]"
          location_array2      '[${longitude["host"]},${latitude["host"]}]'
          peculiar_pattern     '[GEOIP] message => {"lat":${latitude["host"]}, "lon":${longitude["host"]}}'
        </record>
      ]
    end

    def test_filter_quoted_record
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.4192008972168,
            'lon' => -122.05740356445312
          },
          'location_string' => '37.4192008972168,-122.05740356445312',
          'location_string2' => 'US',
          'location_array' => [-122.05740356445312, 37.4192008972168],
          'location_array2' => [-122.05740356445312, 37.4192008972168],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_v1_config_compatibility
      messages = [
        {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          'location_properties' => {
            'country_code' => 'US',
            'lat' => 37.4192008972168,
            'lon' => -122.05740356445312
          },
          'location_string' => '37.4192008972168,-122.05740356445312',
          'location_string2' => 'US',
          'location_array' => [-122.05740356445312, 37.4192008972168],
          'location_array2' => [-122.05740356445312, 37.4192008972168],
          'peculiar_pattern' => '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}'
        }
      ]
      filtered = filter(config_quoted_record, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        backend_library geoip
        geoip_lookup_keys host
        <record>
          location_properties  {
            "city": "${city['host']}",
            "country_code": "${country_code['host']}",
            "latitude": "${latitude['host']}",
            "longitude": "${longitude['host']}"
        }
        </record>
      ]
      messages = [
        { 'host' => '66.102.3.80', 'message' => 'valid ip' }
      ]
      expected = [
        {
          'host' => '66.102.3.80', 'message' => 'valid ip',
          "location_properties" => {
            "city" => "Mountain View",
            "country_code" => "US",
            "latitude" => 37.4192008972168,
            "longitude" => -122.05740356445312
          }
        }
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_when_latitude_longitude_is_nil
      config = %[
        backend_library   geoip
        geoip_lookup_keys  host
        <record>
          latitude  ${latitude['host']}
          longitude ${longitude['host']}
        </record>
      ]
      messages = [
        { "host" => "180.94.85.84", "message" => "nil latitude and longitude" }
      ]
      expected = [
        {
          "host" => "180.94.85.84",
          "message" => "nil latitude and longitude",
          "latitude" => 0.0,
          "longitude" => 0.0
        }
      ]
      filtered = filter(config, messages) do |d|
        setup_geoip_mock(d)
      end
      assert_equal(expected, filtered)
    end
  end
end

