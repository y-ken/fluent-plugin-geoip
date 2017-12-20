require 'helper'
require 'fluent/plugin/out_geoip'
require 'fluent/test/driver/output'

class GeoipOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    geoip_lookup_key  host
    enable_key_city   geoip_city
    tag               geoip.${tag[1]}
  ]

  def create_driver(conf = CONFIG, syntax: :v1)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::GeoipOutput).configure(conf, syntax: syntax)
  end

  sub_test_case "configure" do
    test "empty" do
      assert_nothing_raised do
        create_driver('')
      end
    end

    test "missing required parameters" do
      assert_raise(Fluent::ConfigError) {
        create_driver('enable_key_cities')
      }
    end

    test "minimum" do
      d = create_driver %[
        enable_key_city   geoip_city
        tag               geoip.${tag[1]}
      ]
      assert_equal 'geoip_city', d.instance.config['enable_key_city']
    end

    test "invalid key name" do
      assert_raise(Fluent::ConfigError.new("geoip: unsupported key cities")) do
        create_driver('enable_key_cities')
      end
    end

    test "multiple key config" do
      d = create_driver %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
        tag               geoip.${tag[1]}
      ]
      assert_equal 'from_city, to_city', d.instance.config['enable_key_city']
    end

    test "multiple key config (bad configure)" do
      assert_raise(Fluent::ConfigError) do
        create_driver %[
          geoip_lookup_key  from.ip, to.ip
          enable_key_city   from_city
          enable_key_region from_region
          tag               geoip.${tag[1]}
        ]
      end
    end

    test "invalid json structure w/ Ruby hash like" do
      assert_raise(Fluent::ConfigParseError) do
        create_driver %[
          geoip_lookup_key  host
          <record>
            invalid_json    {"foo" => 123}
          </record>
          tag               geoip.${tag[1]}
        ]
      end
    end

    test "invalid json structure w/ unquoted string literal" do
      assert_raise(Fluent::ConfigParseError) do
        create_driver %[
          geoip_lookup_key  host
          <record>
            invalid_json    {"foo" : string, "bar" : 123}
          </record>
          tag               geoip.${tag[1]}
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
          tag               geoip.${tag[1]}
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
        tag               geoip.${tag[1]}
      ]
    end

    test "unsupported backend" do
      assert_raise(Fluent::ConfigError) do
        create_driver %[
          backend_library hive_geoip2
          <record>
            city ${city["host"]}
          </record>
          tag               geoip.${tag[1]}
        ]
      end
    end
  end

  sub_test_case "geoip2_c" do
    def test_emit_tag_option
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  host
        <record>
          geoip_city      ${city.names.en['host']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_tag_parts
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  host
        <record>
          geoip_city      ${city.names.en['host']}
        </record>
        tag               geoip.${tag[1]}.${tag[2]}.${tag[3]}
      ])
      d1.run(default_tag: '0.1.2.3') do
        d1.feed({'host' => '66.102.3.80'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.1.2.3', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
    end

    def test_emit_with_dot_key
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  ip.origin, ip.dest
        <record>
          origin_country  ${country.iso_code['ip.origin']}
          dest_country    ${country.iso_code['ip.dest']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'US', events[0][2]['origin_country']
      assert_equal 'US', events[0][2]['dest_country']
    end

    def test_emit_with_unknown_address
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  host
        <record>
          geoip_city      ${city.names.en['host']}
          geopoint        [${location.longitude['host']}, ${location.latitude['host']}]
        </record>
        skip_adding_null_record false
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_with_skip_unknown_address
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  host
        <record>
          geoip_city      ${city.names.en['host']}
          geopoint        [${location.longitude['host']}, ${location.latitude['host']}]
        </record>
        skip_adding_null_record true
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
        d1.feed({'host' => '66.102.3.80', 'message' => 'google bot'})
      end
      events = d1.events
      assert_equal 3, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal nil, events[0][2]['geopoint']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
      assert_equal nil, events[1][2]['geopoint']
      assert_equal 'Mountain View', events[2][2]['geoip_city']
      assert_equal [-122.0574, 37.419200000000004], events[2][2]['geopoint']
    end

    def test_emit_record_directive
      d1 = create_driver(%[
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
          string_concat   ${location.latitude['from.ip']},${location.longitude['from.ip']}
          string_array    [${city.names.en['from.ip']}, ${country.names.en['from.ip']}]
          string_nest     { "city" : ${city.names.en['from.ip']}, "country_name" : ${country.names.en['from.ip']}}
          unknown_city    ${city.names.en['unknown_key']}
          undefined       ${city.names.en['undefined']}
          broken_array1   [${location.longitude['from.ip']}, ${location.latitude['undefined']}]
          broken_array2   [${location.longitude['undefined']}, ${location.latitude['undefined']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 37.419200000000004, events[0][2]['latitude']
      assert_equal(-122.0574, events[0][2]['longitude'])
      assert_equal '37.419200000000004,-122.0574', events[0][2]['float_concat']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['float_array']
      float_nest = {"lat" => 37.419200000000004, "lon" => -122.0574 }
      assert_equal float_nest, events[0][2]['float_nest']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['string_concat']
      assert_equal ["Mountain View", "United States"], events[0][2]['string_array']
      string_nest = {"city" => "Mountain View", "country_name" => "United States"}
      assert_equal string_nest, events[0][2]['string_nest']
      assert_equal nil, events[0][2]['unknown_city']
      assert_equal nil, events[0][2]['undefined']
      assert_equal [-122.0574, nil], events[0][2]['broken_array1']
      assert_equal [nil, nil], events[0][2]['broken_array2']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['latitude']
      assert_equal nil, events[1][2]['longitude']
      assert_equal ',', events[1][2]['float_concat']
      assert_equal [nil, nil], events[1][2]['float_array']
      float_nest = {"lat" => nil, "lon" => nil}
      assert_equal float_nest, events[1][2]['float_nest']
      assert_equal ',', events[1][2]['string_concat']
      assert_equal [nil, nil], events[1][2]['string_array']
      string_nest = {"city" => nil, "country_name" => nil}
      assert_equal string_nest, events[1][2]['string_nest']
      assert_equal nil, events[1][2]['unknown_city']
      assert_equal nil, events[1][2]['undefined']
      assert_equal [nil, nil], events[1][2]['broken_array1']
      assert_equal [nil, nil], events[1][2]['broken_array2']
    end

    def test_emit_record_directive_multiple_record
      d1 = create_driver(%[
        backend_library   geoip2_c
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city.names.en['from.ip']}
          to_city         ${city.names.en['to.ip']}
          from_country    ${country.names.en['from.ip']}
          to_country      ${country.names.en['to.ip']}
          string_array    [${country.names.en['from.ip']}, ${country.names.en['to.ip']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 'Tokorozawa', events[0][2]['to_city']
      assert_equal 'Japan', events[0][2]['to_country']
      assert_equal ['United States','Japan'], events[0][2]['string_array']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['to_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['to_country']
      assert_equal [nil, nil], events[1][2]['string_array']
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
      tag               geoip.${tag[1]}
      ]
    end

    def test_emit_quoted_record
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.419200000000004, "lon"=> -122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}', events[0][2]['peculiar_pattern']
    end

    def test_emit_v1_config_compatibility
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.419200000000004, "lon"=> -122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}', events[0][2]['peculiar_pattern']
    end

    def test_emit_multiline_v1_config
      d1 = create_driver(%[
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
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "city"=>"Mountain View", "country_code"=>"US", "latitude"=>37.419200000000004, "longitude"=>-122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
    end
  end

  sub_test_case "geoip2_compat" do
    def test_emit_tag_option
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_tag_parts
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
        </record>
        tag               geoip.${tag[1]}.${tag[2]}.${tag[3]}
      ])
      d1.run(default_tag: '0.1.2.3') do
        d1.feed({'host' => '66.102.3.80'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.1.2.3', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
    end

    def test_emit_with_dot_key
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  ip.origin, ip.dest
        <record>
          origin_country  ${country_code['ip.origin']}
          dest_country    ${country_code['ip.dest']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'US', events[0][2]['origin_country']
      assert_equal 'US', events[0][2]['dest_country']
    end

    def test_emit_with_unknown_address
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record false
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_with_skip_unknown_address
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record true
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
        d1.feed({'host' => '66.102.3.80', 'message' => 'google bot'})
      end
      events = d1.events
      assert_equal 3, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal nil, events[0][2]['geopoint']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
      assert_equal nil, events[1][2]['geopoint']
      assert_equal 'Mountain View', events[2][2]['geoip_city']
      assert_equal [-122.0574, 37.419200000000004], events[2][2]['geopoint']
    end

    def test_emit_record_directive
      d1 = create_driver(%[
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
          string_concat   ${latitude['from.ip']},${longitude['from.ip']}
          string_array    [${city['from.ip']}, ${country_name['from.ip']}]
          string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 37.419200000000004, events[0][2]['latitude']
      assert_equal(-122.0574, events[0][2]['longitude'])
      assert_equal '37.419200000000004,-122.0574', events[0][2]['float_concat']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['float_array']
      float_nest = {"lat" => 37.419200000000004, "lon" => -122.0574 }
      assert_equal float_nest, events[0][2]['float_nest']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['string_concat']
      assert_equal ["Mountain View", "United States"], events[0][2]['string_array']
      string_nest = {"city" => "Mountain View", "country_name" => "United States"}
      assert_equal string_nest, events[0][2]['string_nest']
      assert_equal nil, events[0][2]['unknown_city']
      assert_equal nil, events[0][2]['undefined']
      assert_equal [-122.0574, nil], events[0][2]['broken_array1']
      assert_equal [nil, nil], events[0][2]['broken_array2']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['latitude']
      assert_equal nil, events[1][2]['longitude']
      assert_equal ',', events[1][2]['float_concat']
      assert_equal [nil, nil], events[1][2]['float_array']
      float_nest = {"lat" => nil, "lon" => nil}
      assert_equal float_nest, events[1][2]['float_nest']
      assert_equal ',', events[1][2]['string_concat']
      assert_equal [nil, nil], events[1][2]['string_array']
      string_nest = {"city" => nil, "country_name" => nil}
      assert_equal string_nest, events[1][2]['string_nest']
      assert_equal nil, events[1][2]['unknown_city']
      assert_equal nil, events[1][2]['undefined']
      assert_equal [nil, nil], events[1][2]['broken_array1']
      assert_equal [nil, nil], events[1][2]['broken_array2']
    end

    def test_emit_record_directive_multiple_record
      d1 = create_driver(%[
        backend_library   geoip2_compat
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city['from.ip']}
          to_city         ${city['to.ip']}
          from_country    ${country_name['from.ip']}
          to_country      ${country_name['to.ip']}
          string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 'Tokorozawa', events[0][2]['to_city']
      assert_equal 'Japan', events[0][2]['to_country']
      assert_equal ['United States','Japan'], events[0][2]['string_array']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['to_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['to_country']
      assert_equal [nil, nil], events[1][2]['string_array']
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
      tag               geoip.${tag[1]}
      ]
    end

    def test_emit_quoted_record
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.419200000000004, "lon"=> -122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}', events[0][2]['peculiar_pattern']
    end

    def test_emit_v1_config_compatibility
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.419200000000004, "lon"=> -122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.419200000000004,-122.0574', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array']
      assert_equal [-122.0574, 37.419200000000004], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.419200000000004, "lon":-122.0574}', events[0][2]['peculiar_pattern']
    end

    def test_emit_multiline_v1_config
      d1 = create_driver(%[
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
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "city"=>"Mountain View", "country_code"=>"US", "latitude"=>37.419200000000004, "longitude"=>-122.0574 }
      assert_equal location_properties, events[0][2]['location_properties']
    end
  end

  sub_test_case "geoip legacy" do
    def test_emit
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        enable_key_city   geoip_city
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_tag_option
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_tag_parts
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
        </record>
        tag               geoip.${tag[1]}.${tag[2]}.${tag[3]}
      ])
      d1.run(default_tag: '0.1.2.3') do
        d1.feed({'host' => '66.102.3.80'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.1.2.3', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
    end

    def test_emit_with_dot_key
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  ip.origin, ip.dest
        <record>
          origin_country  ${country_code['ip.origin']}
          dest_country    ${country_code['ip.dest']}
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'ip.origin' => '66.102.3.80', 'ip.dest' => '8.8.8.8'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'US', events[0][2]['origin_country']
      assert_equal 'US', events[0][2]['dest_country']
    end

    def test_emit_nested_attr
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host.ip
        enable_key_city   geoip_city
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['geoip_city']
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_with_unknown_address
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record false
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
    end

    def test_emit_with_skip_unknown_address
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          geoip_city      ${city['host']}
          geopoint        [${longitude['host']}, ${latitude['host']}]
        </record>
        skip_adding_null_record true
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        # 203.0.113.1 is a test address described in RFC5737
        d1.feed({'host' => '203.0.113.1', 'message' => 'invalid ip'})
        d1.feed({'host' => '0', 'message' => 'invalid ip'})
        d1.feed({'host' => '66.102.3.80', 'message' => 'google bot'})
      end
      events = d1.events
      assert_equal 3, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal nil, events[0][2]['geoip_city']
      assert_equal nil, events[0][2]['geopoint']
      assert_equal 'geoip.access', events[1][0] # tag
      assert_equal nil, events[1][2]['geoip_city']
      assert_equal nil, events[1][2]['geopoint']
      assert_equal 'Mountain View', events[2][2]['geoip_city']
      assert_equal [-122.05740356445312, 37.4192008972168], events[2][2]['geopoint']
    end

    def test_emit_multiple_key
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'Tokorozawa', events[0][2]['to_city']
      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['to_city']
    end

    def test_emit_multiple_key_multiple_record
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city, to_city
        enable_key_country_name from_country, to_country
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
        d1.feed({'from' => {'ip' => '66.102.3.80'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 3, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 'Tokorozawa', events[0][2]['to_city']
      assert_equal 'Japan', events[0][2]['to_country']

      assert_equal 'Mountain View', events[1][2]['from_city']
      assert_equal 'United States', events[1][2]['from_country']
      assert_equal nil, events[1][2]['to_city']
      assert_equal nil, events[1][2]['to_country']

      assert_equal nil, events[2][2]['from_city']
      assert_equal nil, events[2][2]['from_country']
      assert_equal nil, events[2][2]['to_city']
      assert_equal nil, events[2][2]['to_country']
    end

    def test_emit_record_directive
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  from.ip
        <record>
          from_city       ${city['from.ip']}
          from_country    ${country_name['from.ip']}
          latitude        ${latitude['from.ip']}
          longitude       ${longitude['from.ip']}
          float_concat    ${latitude['from.ip']},${longitude['from.ip']}
          float_array     [${longitude['from.ip']}, ${latitude['from.ip']}]
          float_nest      { "lat" : ${latitude['from.ip']}, "lon" : ${longitude['from.ip']}}
          string_concat   ${latitude['from.ip']},${longitude['from.ip']}
          string_array    [${city['from.ip']}, ${country_name['from.ip']}]
          string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
          unknown_city    ${city['unknown_key']}
          undefined       ${city['undefined']}
          broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
          broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 37.4192008972168, events[0][2]['latitude']
      assert_equal(-122.05740356445312, events[0][2]['longitude'])
      assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['float_concat']
      assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['float_array']
      float_nest = {"lat" => 37.4192008972168, "lon" => -122.05740356445312 }
      assert_equal float_nest, events[0][2]['float_nest']
      assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['string_concat']
      assert_equal ["Mountain View", "United States"], events[0][2]['string_array']
      string_nest = {"city" => "Mountain View", "country_name" => "United States"}
      assert_equal string_nest, events[0][2]['string_nest']
      assert_equal nil, events[0][2]['unknown_city']
      assert_equal nil, events[0][2]['undefined']
      assert_equal [-122.05740356445312, nil], events[0][2]['broken_array1']
      assert_equal [nil, nil], events[0][2]['broken_array2']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['latitude']
      assert_equal nil, events[1][2]['longitude']
      assert_equal ',', events[1][2]['float_concat']
      assert_equal [nil, nil], events[1][2]['float_array']
      float_nest = {"lat" => nil, "lon" => nil}
      assert_equal float_nest, events[1][2]['float_nest']
      assert_equal ',', events[1][2]['string_concat']
      assert_equal [nil, nil], events[1][2]['string_array']
      string_nest = {"city" => nil, "country_name" => nil}
      assert_equal string_nest, events[1][2]['string_nest']
      assert_equal nil, events[1][2]['unknown_city']
      assert_equal nil, events[1][2]['undefined']
      assert_equal [nil, nil], events[1][2]['broken_array1']
      assert_equal [nil, nil], events[1][2]['broken_array2']
    end

    def test_emit_record_directive_multiple_record
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  from.ip, to.ip
        <record>
          from_city       ${city['from.ip']}
          to_city         ${city['to.ip']}
          from_country    ${country_name['from.ip']}
          to_country      ${country_name['to.ip']}
          string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
        </record>
        tag               geoip.${tag[1]}
      ], syntax: :v0)
      d1.run(default_tag: 'input.access') do
        d1.feed({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.15.42'}})
        d1.feed({'message' => 'missing field'})
      end
      events = d1.events
      assert_equal 2, events.length

      assert_equal 'geoip.access', events[0][0] # tag
      assert_equal 'Mountain View', events[0][2]['from_city']
      assert_equal 'United States', events[0][2]['from_country']
      assert_equal 'Tokorozawa', events[0][2]['to_city']
      assert_equal 'Japan', events[0][2]['to_country']
      assert_equal ['United States','Japan'], events[0][2]['string_array']

      assert_equal nil, events[1][2]['from_city']
      assert_equal nil, events[1][2]['to_city']
      assert_equal nil, events[1][2]['from_country']
      assert_equal nil, events[1][2]['to_country']
      assert_equal [nil, nil], events[1][2]['string_array']
    end

    def config_quoted_record
      %[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          location_properties  '{ "country_code" : "${country_code["host"]}", "lat": ${latitude["host"]}, "lon": ${longitude["host"]} }'
          location_string      ${latitude['host']},${longitude['host']}
          location_string2     ${country_code["host"]}
          location_array       "[${longitude['host']},${latitude['host']}]"
          location_array2      '[${longitude["host"]},${latitude["host"]}]'
          peculiar_pattern     '[GEOIP] message => {"lat":${latitude["host"]}, "lon":${longitude["host"]}}'
        </record>
        tag               geoip.${tag[1]}
      ]
    end

    def test_emit_quoted_record
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.4192008972168, "lon"=> -122.05740356445312 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array']
      assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}', events[0][2]['peculiar_pattern']
    end

    def test_emit_v1_config_compatibility
      d1 = create_driver(config_quoted_record)
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "country_code" => "US", "lat" => 37.4192008972168, "lon"=> -122.05740356445312 }
      assert_equal location_properties, events[0][2]['location_properties']
      assert_equal '37.4192008972168,-122.05740356445312', events[0][2]['location_string']
      assert_equal 'US', events[0][2]['location_string2']
      assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array']
      assert_equal [-122.05740356445312, 37.4192008972168], events[0][2]['location_array2']
      assert_equal '[GEOIP] message => {"lat":37.4192008972168, "lon":-122.05740356445312}', events[0][2]['peculiar_pattern']
    end

    def test_emit_multiline_v1_config
      d1 = create_driver(%[
        backend_library geoip
        geoip_lookup_key  host
        <record>
          location_properties  {
            "city": "${city['host']}",
            "country_code": "${country_code['host']}",
            "latitude": "${latitude['host']}",
            "longitude": "${longitude['host']}"
          }
        </record>
        tag               geoip.${tag[1]}
      ])
      d1.run(default_tag: 'input.access') do
        d1.feed({'host' => '66.102.3.80', 'message' => 'valid ip'})
      end
      events = d1.events
      assert_equal 1, events.length
      assert_equal 'geoip.access', events[0][0] # tag
      location_properties = { "city"=>"Mountain View", "country_code"=>"US", "latitude"=>37.4192008972168, "longitude"=>-122.05740356445312 }
      assert_equal location_properties, events[0][2]['location_properties']
    end
  end
end
