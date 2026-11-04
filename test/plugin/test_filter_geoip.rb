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
      assert_raise(Fluent::ConfigError) do
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

  sub_test_case "loading" do
    # geoip-c needs libGeoIP, which geoip2_c and geoip2_compat do not use (#94).
    def run_ruby(script)
      require "open3"
      lib = File.expand_path("../../lib", __dir__)
      out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", script)
      assert_true(status.success?, err)
      out
    end

    test "loading the plugin does not load geoip-c" do
      assert_equal("not loaded\n", run_ruby(<<~'RUBY'))
        require "fluent/plugin/filter_geoip"
        puts defined?(::GeoIP) ? "loaded" : "not loaded"
      RUBY
    end

    data(geoip2_c: "geoip2_c",
         geoip2_compat: "geoip2_compat")
    test "configuring a GeoIP2 backend does not load geoip-c" do |backend|
      assert_equal("not loaded\n", run_ruby(<<~RUBY))
        require "test/unit"
        Test::Unit::AutoRunner.need_auto_run = false
        require "fluent/test"
        require "fluent/test/driver/filter"
        require "fluent/plugin/filter_geoip"
        Fluent::Test.setup
        Fluent::Test::Driver::Filter.new(Fluent::Plugin::GeoipFilter).configure("backend_library #{backend}")
        puts defined?(::GeoIP) ? "loaded" : "not loaded"
      RUBY
    end

    test "the error shows why the gem cannot be loaded" do
      any_instance_of(Fluent::Plugin::GeoipFilter) do |klass|
        stub(klass).require(anything) do |name|
          raise LoadError, "libGeoIP.so.1: cannot open shared object file" if name == "geoip"
          Kernel.require(name)
        end
      end
      error = assert_raise(Fluent::ConfigError) do
        create_driver("backend_library geoip\n<record>\ncity ${city[\"host\"]}\n</record>\n")
      end
      assert_equal("Cannot load geoip-c gem. (LoadError: libGeoIP.so.1: cannot open shared object file)", error.message)
    end
  end

  sub_test_case "a value that is not an IP address" do
    # These values raised an error in the lookup (#95). Now they give the
    # same record as an IP address that is not in the database.
    NOT_IP_VALUES = {
      "dash" => "-",
      "word" => "unknown",
      "X-Forwarded-For" => "66.102.3.80, 203.0.113.1",
      "spaces" => " 66.102.3.80 ",
      "port" => "66.102.3.80:8080",
      "brackets" => "[2001:4860:4860::8888]",
      "CIDR" => "66.102.3.0/24",
      # Ruby's getaddrinfo reads these as an IP address, but libmaxminddb does not.
      "<any>" => "<any>",
      "<broadcast>" => "<broadcast>",
      "invalid UTF-8" => "-\xFF".dup.force_encoding("UTF-8"),
      "unknown zone" => "fe80::1%zz",
      "octet over 255" => "::ffff:999.1.1.1",
      "integer" => 6610238,
      "float" => 1.5,
      "true" => true,
      "array" => ["66.102.3.80"],
      "hash" => {"ip" => "66.102.3.80"},
    }
    BACKEND_CONFIGS = {
      "geoip2_c" => %[
        backend_library geoip2_c
        <record>
          city ${city.names.en["host"]}
          lat  ${location.latitude["host"]}
          geo  '[${location.longitude["host"]}, ${location.latitude["host"]}]'
        </record>
      ],
      "geoip2_compat" => %[
        backend_library geoip2_compat
        <record>
          city ${city["host"]}
          lat  ${latitude["host"]}
          geo  '[${longitude["host"]}, ${latitude["host"]}]'
        </record>
      ],
      "geoip" => %[
        backend_library geoip
        <record>
          city ${city["host"]}
          lat  ${latitude["host"]}
          geo  '[${longitude["host"]}, ${latitude["host"]}]'
        </record>
      ],
    }

    # The fields for a value that is not found, with every backend config.
    NOT_FOUND = {"city" => nil, "lat" => nil, "geo" => [nil, nil]}

    def run_filter(config, values)
      d = create_driver(config + "\n@log_level debug\n")
      yield d if block_given?
      d.run(default_tag: "input.access") do
        values.each {|value| d.feed(@time, {"host" => value, "message" => "m"}) }
      end
      d
    end

    def run_with_lookup_error(backend, error, value)
      run_filter(BACKEND_CONFIGS[backend], [value]) do |d|
        stub(d.instance.instance_variable_get(:@geoip)).lookup(anything) { raise error }
      end
    end

    def not_found_record(value)
      {"host" => value, "message" => "m"}.merge(NOT_FOUND)
    end

    data(BACKEND_CONFIGS.keys.map {|backend| [backend, backend] }.to_h)
    test "an IP address that is not in the database gives NOT_FOUND" do |backend|
      # 203.0.113.1 is a test address described in RFC5737
      d = run_filter(BACKEND_CONFIGS[backend], ["203.0.113.1"])
      assert_equal([not_found_record("203.0.113.1")], d.filtered_records)
    end

    data(BACKEND_CONFIGS.keys.product(NOT_IP_VALUES.keys).map {|backend, name|
           ["#{backend}: #{name}", [backend, NOT_IP_VALUES[name]]]
         }.to_h)
    test "is not found" do |(backend, value)|
      d = run_filter(BACKEND_CONFIGS[backend], [value])
      assert_equal([not_found_record(value)], d.filtered_records)
      assert_equal([], d.error_events)
      assert_equal([], d.logs.grep(/66\.102\.3\.80/))
    end

    data(BACKEND_CONFIGS.keys.map {|backend| [backend, backend] }.to_h)
    test "is skipped with skip_adding_null_record" do |backend|
      config = BACKEND_CONFIGS[backend] + "\nskip_adding_null_record true\n"
      d = run_filter(config, NOT_IP_VALUES.values)
      assert_equal(NOT_IP_VALUES.values.map {|value| {"host" => value, "message" => "m"} },
                   d.filtered_records)
      assert_equal([], d.error_events)
    end

    # geoip2_c raises ArgumentError for a string with a null byte. geoip2_compat
    # and geoip read it up to the null byte, and that does not change.
    test "a string with a null byte is not found with geoip2_c" do
      d = run_filter(BACKEND_CONFIGS["geoip2_c"], ["66.102.3.80\0"])
      assert_equal([not_found_record("66.102.3.80\0")], d.filtered_records)
      assert_equal([], d.error_events)
    end

    # geoip2_compat 0.0.3 reads mmdb_error, which libmaxminddb does not set
    # when getaddrinfo fails, so the message for "-" can be "lookup failed".
    # The check for a null byte of geoip2_c must not raise for UTF-16LE.
    compat_error = ["geoip2_compat", "GeoIP2Compat::Error", "geoip2_compat - lookup failed: Unknown error code"]
    data("geoip2_compat: dash" => compat_error + ["-"],
         "geoip2_compat: invalid UTF-8" => compat_error + ["-\xFF".dup.force_encoding("UTF-8")],
         "geoip2_compat: UTF-16LE" => compat_error + ["66.102.3.80".encode("UTF-16LE")],
         "geoip2_compat: octet over 255" => compat_error + ["::ffff:999.1.1.1"],
         "geoip2_compat: too many groups" => compat_error + ["1:2:3:4:5:6:7:8:9::"],
         "geoip2_compat: unknown zone" => compat_error + ["fe80::1%zz"],
         "geoip2_compat: brackets" => compat_error + ["[::1]"],
         "geoip2_compat: CIDR" => compat_error + ["66.102.3.0/24"],
         "geoip2_c: UTF-16LE" => ["geoip2_c", "ArgumentError", "string contains null byte", "66.102.3.80".encode("UTF-16LE")])
    test "an error for a value that is not an IP address is not found" do |(backend, error_class, message, value)|
      require(backend == "geoip2_c" ? "geoip2" : backend)
      d = run_with_lookup_error(backend, Object.const_get(error_class).new(message), value)
      assert_equal([not_found_record(value)], d.filtered_records)
      assert_equal([], d.error_events)
    end

    test "an empty Array is logged as before" do
      d = run_filter(BACKEND_CONFIGS["geoip2_c"], [[]])
      assert_equal(1, d.logs.grep(/\[warn\]: host is empty string/).size)
      assert_equal([], d.error_events)
    end

    # This error comes from the database, not from the value.
    data(geoip2_c: ["geoip2_c", "GeoIP2::Error", "lookup failed: The MaxMind DB file's search tree is corrupt"],
         geoip2_compat: ["geoip2_compat", "GeoIP2Compat::Error", "geoip2_compat - lookup failed: The MaxMind DB file's search tree is corrupt"])
    test "an error of the database is not treated as not found" do |(backend, error_class, message)|
      require(backend == "geoip2_c" ? "geoip2" : backend)
      error = Object.const_get(error_class).new(message)
      d = run_with_lookup_error(backend, error, "66.102.3.80")
      assert_equal([], d.filtered_records)
      assert_equal([error], d.error_events.map {|_tag, _time, _record, e| e })
    end

    test "does not change the lookup of an IPv4 and an IPv6 address" do
      d = run_filter(BACKEND_CONFIGS["geoip2_c"], ["66.102.3.80", "2001:4860:4860::8888"])
      assert_equal(["Mountain View", nil], d.filtered_records.map {|r| r["city"] })
      assert_equal([37.419200000000004, 37.751], d.filtered_records.map {|r| r["lat"] })
    end
  end

  sub_test_case "a placeholder next to a quote in a string" do
    def filter_one(record_section, host = "66.102.3.80")
      config = "backend_library geoip2_c\n<record>\n#{record_section}\n</record>\n"
      filter(config, [{"host" => host}]).first
    end

    test "keeps the quotes and replaces the placeholder" do
      record = filter_one(<<~'CONF')
        double  'City is "${city.names.en["host"]}"'
        single  "City is '${city.names.en['host']}'"
        before  'from "${country.iso_code["host"]}'
        after   "${city.names.en['host']}'s office"
        plain   City is ${city.names.en["host"]}
      CONF
      assert_equal('City is "Mountain View"', record["double"])
      assert_equal("City is 'Mountain View'", record["single"])
      assert_equal('from "US', record["before"])
      assert_equal("Mountain View's office", record["after"])
      assert_equal("City is Mountain View", record["plain"])
    end

    test "gives an empty string inside the quotes when the IP is not found" do
      # 203.0.113.1 is a test address described in RFC5737
      record = filter_one(%q(double  'City is "${city.names.en["host"]}"'), "203.0.113.1")
      assert_equal('City is ""', record["double"])
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

    def test_filter_with_empty_string
      config = %[
        backend_library   geoip2_c
        geoip_lookup_keys host
        <record>
          geoip_city      '${city.names.en["host"]}'
          geopoint        '[${location.longitude["host"]}, ${location.latitude["host"]}]'
        </record>
        skip_adding_null_record false
      ]
      messages = [
        {'host' => '', 'message' => 'empty string ip'},
      ]
      expected = [
        {'host' => '', 'message' => 'empty string ip', 'geoip_city' => nil, 'geopoint' => [nil, nil]},
      ]
      filtered = filter(config, messages)
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

