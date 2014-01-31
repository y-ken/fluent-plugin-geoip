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
    puts d.instance.inspect
    assert_equal 'geoip_city', d.instance.config['enable_key_city']
  end

  def test_emit
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      d1.emit({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    # p emits[0]
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['geoip_city']
    # p emits[1]
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
    p emits[0]
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['geoip_city']
    p emits[1]
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
    # p emits[0]
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal nil, emits[0][2]['geoip_city']
    # p emits[1]
    assert_equal 'geoip.access', emits[1][0] # tag
    assert_equal nil, emits[1][2]['geoip_city']
  end

  def test_emit_lonlat
    d1 = create_driver(%[
      geoip_lookup_key     host
      enable_key_latitude  geoip_lat
      enable_key_longitude geoip_lon
      enable_key_lonlat    geoip_lonlat
      remove_tag_prefix    input.
      add_tag_prefix       geoip.
    ], 'input.access')
    d1.run do
      d1.emit({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    p emits[0]
    assert_equal 'geoip.access', emits[0][0] # tag
    assert_equal 37.4192008972168, emits[0][2]['geoip_lat']
    assert_equal -122.05740356445312, emits[0][2]['geoip_lon']
    assert_equal [-122.05740356445312, 37.4192008972168], emits[0][2]['geoip_lonlat']
    p emits[1]
    assert_equal nil, emits[1][2]['geoip_lat']
    assert_equal nil, emits[1][2]['geoip_lon']
    assert_equal nil, emits[1][2]['geoip_lonlat']
  end

end
