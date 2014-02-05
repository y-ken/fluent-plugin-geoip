require 'helper'

class GeoipOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    geoip_lookup_key  host
    enable_key_city   geoip_city
    remove_tag_prefix input.
    add_tag_prefix    geoip.
  ]

  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::GeoipOutput, tag).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('enable_key_cities')
    }
    d = create_driver %[
      enable_key_city geoip_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ]
    assert_equal 'geoip_city', d.instance.config['enable_key_city']
    assert_equal ['geoip_city'], d.instance.geoip_keys_map['city']

    # multiple key config
    d = create_driver %[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ]
    assert_equal 'from_city, to_city', d.instance.config['enable_key_city']
    assert_equal ['from_city', 'to_city'], d.instance.geoip_keys_map['city']

    # multiple key config (bad configure)
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        geoip_lookup_key  from.ip, to.ip
        enable_key_city   from_city
        enable_key_region from_region
        remove_tag_prefix input.
        add_tag_prefix    geoip.
      ]
    }
  end

  def test_emit
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      d1.emit({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['geoip_city']
    assert_equal nil, emits[1][2]['geoip_city']
  end

  def test_emit_nested_attr
    d1 = create_driver(%[
      geoip_lookup_key  host.ip
      enable_key_city   geoip_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ], 'input.access')
    d1.run do
      d1.emit({'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['geoip_city']
    assert_equal nil, emits[1][2]['geoip_city']
  end

  def test_emit_with_unknown_address
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      # 203.0.113.1 is a test address described in RFC5737
      d1.emit({'host' => '203.0.113.1', 'message' => 'invalid ip'})
      d1.emit({'host' => '0', 'message' => 'invalid ip'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal nil, emits[0][2]['geoip_city']
    assert_equal 'geoip.access', emits[1][0] # tag
    assert_equal nil, emits[1][2]['geoip_city']
  end

  def test_emit_multiple_key
    d1 = create_driver(%[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.95.42'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'Musashino', emits[0][2]['to_city']
    assert_equal nil, emits[1][2]['from_city']
    assert_equal nil, emits[1][2]['to_city']
  end

  def test_emit_multiple_key_multiple_record
    d1 = create_driver(%[
      geoip_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      enable_key_country_name from_country, to_country
      remove_tag_prefix input.
      add_tag_prefix    geoip.
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.95.42'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    p d1
    assert_equal 2, emits.length
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'United States', emits[0][2]['from_country']
    assert_equal 'Musashino', emits[0][2]['to_city']
    assert_equal 'Japan', emits[0][2]['to_country']
    assert_equal nil, emits[1][2]['from_city']
    assert_equal nil, emits[1][2]['to_city']
  end

end
