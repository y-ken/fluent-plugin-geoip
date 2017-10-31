require 'helper'

class GeoipFilterTest < Test::Unit::TestCase
  def setup
    omit_unless(Fluent.const_defined?(:Filter))
    Fluent::Test.setup
    @time = Fluent::Engine.now
  end

  def create_driver(conf='', tag='test', use_v1=false)
    Fluent::Test::FilterTestDriver.new(Fluent::GeoipFilter, tag).configure(conf, use_v1)
  end

  def filter(config, messages, use_v1=false, driver=nil)
    if driver.nil?
      driver = create_driver(config, 'test', use_v1)
    end

    driver.run {
      messages.each {|message|
        driver.filter(message, @time)
      }
    }

    filtered = driver.filtered_as_array
    filtered.map {|m| m[2]}
  end

  sub_test_case "configure" do
    test "empty" do
      assert_nothing_raised {
        create_driver('')
      }
    end

    test "missing required parameters" do
      assert_raise(Fluent::ConfigError) {
        create_driver('enable_key_cities')
      }
    end

    test "minimum" do
      d = create_driver %[
        enable_key_city   geoip_city
      ]
      assert_equal 'geoip_city', d.instance.config['enable_key_city']
    end

    test "multiple key config" do
      d = create_driver %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
      ]
      assert_equal 'from_city, to_city', d.instance.config['enable_key_city']
    end

    test "multiple key config (bad configure)" do
      assert_raise(Fluent::ConfigError) {
        create_driver %[
          geoip_lookup_key  from.ip, to.ip
          enable_key_city   from_city
          enable_key_region from_region
        ]
      }
    end

    test "invalid json structure w/ Ruby hash like" do
      assert_raise(Fluent::ConfigError) {
        create_driver %[
          geoip_lookup_key  host
          <record>
            invalid_json    {"foo" => 123}
          </record>
        ]
      }
    end

    test "invalid json structure w/ unquoted string literal" do
      assert_raise(Fluent::ConfigError) {
        create_driver %[
          geoip_lookup_key  host
          <record>
            invalid_json    {"foo" : string, "bar" : 123}
          </record>
        ]
      }
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
        geoip_lookup_key  ip.origin, ip.dest
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
        geoip_lookup_key  host
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        backend_library   geoip2_c
        geoip_lookup_key  host
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
          {'host' => '66.102.3.80', 'message' => 'google public dns'}
      ]
      expected = [
          {'host' => '203.0.113.1', 'message' => 'invalid ip'},
          {'host' => '0', 'message' => 'invalid ip'},
          {'host' => '66.102.3.80', 'message' => 'google public dns',
           'geoip_city' => 'Mountain View', 'geopoint' => [-122.0574, 37.419200000000004]}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        backend_library   geoip2_c
        geoip_lookup_key  from.ip
        <record>
          from_city       ${city.names.en['from.ip']}
          from_country    ${country.names.en['from.ip']}
          latitude        ${location.latitude['from.ip']}
          longitude       ${location.longitude['from.ip']}
          float_concat    ${location.latitude['from.ip']},${location.longitude['from.ip']}
          float_array     [${location.longitude['from.ip']}, ${location.latitude['from.ip']}]
          float_nest      { "lat" : ${location.latitude['from.ip']}, "lon" : ${location.longitude['from.ip']}}
          string_concat   ${city.names.en['from.ip']},${country.names.en['from.ip']}
          string_array    [${city.names.en['from.ip']}, ${country.names.en['from.ip']}]
          string_nest     { "city" : ${city.names.en['from.ip']}, "country_name" : ${country.names.en['from.ip']}}
          unknown_city    ${city.names.en['unknown_key']}
          undefined       ${city.names.en['undefined']}
          broken_array1   [${location.longitude['from.ip']}, ${location.latitude['undefined']}]
          broken_array2   [${location.longitude['undefined']}, ${location.latitude['undefined']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}},
          {'message' => 'missing field'},
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
              'float_nest' => {'lat' => 37.4192000000000004, 'lon' => -122.0574},
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
              'float_nest' => {'lat' => nil, 'lon' => nil},
              'string_concat' => ',',
              'string_array' => [nil, nil],
              'string_nest' => {"city" => nil, "country_name" => nil},
              'unknown_city' => nil,
              'undefined' => nil,
              'broken_array1' => [nil, nil],
              'broken_array2' => [nil, nil]
          },
      ]
      filtered = filter(config, messages)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        backend_library   geoip2_c
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city.names.en['from.ip']}
          to_city         ${city.names.en['to.ip']}
          from_country    ${country.names.en['from.ip']}
          to_country      ${country.names.en['to.ip']}
          string_array    [${country.names.en['from.ip']}, ${country.names.en['to.ip']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
          {'message' => 'missing field'}
      ]
      expected = [
          {
              'from' => {'ip' => '66.102.3.80'},
              'to' => {'ip' => '125.54.15.42'},
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        backend_library   geoip2_c
        geoip_lookup_key  host
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
      filtered = filter(config_quoted_record, messages, true)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        backend_library   geoip2_c
        geoip_lookup_key  host
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
          {'host' => '66.102.3.80', 'message' => 'valid ip'}
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
      filtered = filter(config, messages, true)
      assert_equal(expected, filtered)
    end
  end

  sub_test_case "geoip2_compat" do
    def test_filter_with_dot_key
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_key  ip.origin, ip.dest
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
        geoip_lookup_key  host
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_key  host
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
          {'host' => '66.102.3.80', 'message' => 'google public dns'}
      ]
      expected = [
          {'host' => '203.0.113.1', 'message' => 'invalid ip'},
          {'host' => '0', 'message' => 'invalid ip'},
          {'host' => '66.102.3.80', 'message' => 'google public dns',
           'geoip_city' => 'Mountain View', 'geopoint' => [-122.0574, 37.419200000000004]}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_key  from.ip
        <record>
          from_city       ${city['from.ip']}
          from_country    ${country_name['from.ip']}
          latitude        ${latitude['from.ip']}
          longitude       ${longitude['from.ip']}
          float_concat    ${latitude['from.ip']},${longitude['from.ip']}
          float_array     [${longitude['from.ip']}, ${latitude['from.ip']}]
          float_nest      { "lat" : ${latitude['from.ip']}, "lon" : ${longitude['from.ip']}}
          string_concat   ${city['from.ip']},${country_name['from.ip']}
          string_array    [${city['from.ip']}, ${country_name['from.ip']}]
          string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}},
          {'message' => 'missing field'},
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
              'float_nest' => {'lat' => 37.4192000000000004, 'lon' => -122.0574},
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
              'float_nest' => {'lat' => nil, 'lon' => nil},
              'string_concat' => ',',
              'string_array' => [nil, nil],
              'string_nest' => {"city" => nil, "country_name" => nil},
              'unknown_city' => nil,
              'undefined' => nil,
              'broken_array1' => [nil, nil],
              'broken_array2' => [nil, nil]
          },
      ]
      filtered = filter(config, messages)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city['from.ip']}
          to_city         ${city['to.ip']}
          from_country    ${country_name['from.ip']}
          to_country      ${country_name['to.ip']}
          string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
          {'message' => 'missing field'}
      ]
      expected = [
          {
              'from' => {'ip' => '66.102.3.80'},
              'to' => {'ip' => '125.54.15.42'},
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        backend_library   geoip2_compat
        geoip_lookup_key  host
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
      filtered = filter(config_quoted_record, messages, true)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        backend_library   geoip2_compat
        geoip_lookup_key  host
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
          {'host' => '66.102.3.80', 'message' => 'valid ip'}
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
      filtered = filter(config, messages, true)
      assert_equal(expected, filtered)
    end
  end

  sub_test_case "geoip legacy" do
    def test_filter
      config = %[
        geoip_lookup_key  host
        enable_key_city   geoip_city
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
        geoip_lookup_key  ip.origin, ip.dest
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
        geoip_lookup_key  host.ip
        enable_key_city   geoip_city
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
        geoip_lookup_key  host
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_with_skip_unknown_address
      config = %[
        geoip_lookup_key  host
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
          {'host' => '8.8.8.8', 'message' => 'google public dns'}
      ]
      expected = [
          {'host' => '203.0.113.1', 'message' => 'invalid ip'},
          {'host' => '0', 'message' => 'invalid ip'},
          {'host' => '8.8.8.8', 'message' => 'google public dns',
           'geoip_city' => 'Mountain View', 'geopoint' => [-122.08380126953125, 37.38600158691406]}
      ]
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_multiple_key
      config = %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_multiple_key_multiple_record
      config = %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
        enable_key_country_name from_country, to_country
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def test_filter_record_directive
      config = %[
        geoip_lookup_key  from.ip
        <record>
          from_city       ${city['from.ip']}
          from_country    ${country_name['from.ip']}
          latitude        ${latitude['from.ip']}
          longitude       ${longitude['from.ip']}
          float_concat    ${latitude['from.ip']},${longitude['from.ip']}
          float_array     [${longitude['from.ip']}, ${latitude['from.ip']}]
          float_nest      { "lat" : ${latitude['from.ip']}, "lon" : ${longitude['from.ip']}}
          string_concat   ${city['from.ip']},${country_name['from.ip']}
          string_array    [${city['from.ip']}, ${country_name['from.ip']}]
          string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}},
          {'message' => 'missing field'},
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
              'float_nest' => {'lat' => 37.4192008972168, 'lon' => -122.05740356445312},
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
              'float_nest' => {'lat' => nil, 'lon' => nil},
              'string_concat' => ',',
              'string_array' => [nil, nil],
              'string_nest' => {"city" => nil, "country_name" => nil},
              'unknown_city' => nil,
              'undefined' => nil,
              'broken_array1' => [nil, nil],
              'broken_array2' => [nil, nil]
          },
      ]
      filtered = filter(config, messages)
      # test-unit cannot calculate diff between large Array
      assert_equal(expected[0], filtered[0])
      assert_equal(expected[1], filtered[1])
    end

    def test_filter_record_directive_multiple_record
      config = %[
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city['from.ip']}
          to_city         ${city['to.ip']}
          from_country    ${country_name['from.ip']}
          to_country      ${country_name['to.ip']}
          string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
        </record>
      ]
      messages = [
          {'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}},
          {'message' => 'missing field'}
      ]
      expected = [
          {
              'from' => {'ip' => '66.102.3.80'},
              'to' => {'ip' => '125.54.15.42'},
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
      filtered = filter(config, messages)
      assert_equal(expected, filtered)
    end

    def config_quoted_record
      %[
        geoip_lookup_key  host
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
      filtered = filter(config_quoted_record, messages, true)
      assert_equal(expected, filtered)
    end

    def test_filter_multiline_v1_config
      config = %[
        geoip_lookup_key  host
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
          {'host' => '66.102.3.80', 'message' => 'valid ip'}
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
      filtered = filter(config, messages, true)
      assert_equal(expected, filtered)
    end

    def test_filter_updated_database
      db_test_normal_path = 'data/GeoLiteCity-Test-Normal.dat'
      db_test_uppercase_path = 'data/GeoLiteCity-Test-Uppercase.dat'
      db_test_tmp_path = 'data/GeoLiteCity-tmp.dat'
      if File.exist?(db_test_normal_path)
        FileUtils.copy(db_test_normal_path, db_test_tmp_path)
      else
        raise "File ${db_test_normal_path} doesn't exist in data directory"
      end

      # use filesystem database_read_type for testing purposes
      config = %[
        geoip_lookup_key  host
        database_refresh_check  true
        geoip_database  'data/GeoLiteCity-tmp.dat'
        database_read_type filesystem
        <record>
          location_properties  {
            "city": "${city['host']}",
            "country_code": "${country_code['host']}",
            "latitude": "${latitude['host']}",
            "longitude": "${longitude['host']}"
        }
        </record>
      ]
      messages1 = [
          {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      messages2 = [
          {'host' => '66.102.3.80', 'message' => 'valid ip'}
      ]
      expected_before_db_update = [
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
      expected_after_db_update = [
          {
              'host' => '66.102.3.80', 'message' => 'valid ip',
              "location_properties" => {
                  "city" => "MOUNTAIN VIEW",
                  "country_code" => "US",
                  "latitude" => 37.4192008972168,
                  "longitude" => -122.05740356445312
              }
          }
      ]

      # create two drivers with the same config to avoid filtered attribute cluttering
      driver1 = create_driver(config, 'test', true)
      driver2 = create_driver(config, 'test', true)

      filtered = filter(config, messages1, true, driver1)
      begin
        assert_equal(expected_before_db_update, filtered)
      rescue
        FileUtils.remove(db_test_tmp_path)
        raise
      end

      # overwrite database with different version
      FileUtils.copy(db_test_uppercase_path, db_test_tmp_path)

      filtered = filter(config, messages2, true, driver2)

      begin
        assert_equal(expected_after_db_update, filtered)
      rescue
        raise
      ensure
        FileUtils.remove(db_test_tmp_path)
      end
    end
  end
end

