# fluent-plugin-geoip

Fluentd Output plugin to adds information about geographical location of IP addresses with Maxmind GeoIP databases.

## Installation

install with `gem` or `fluent-gem` command as:

```
# for fluentd
$ gem install fluent-plugin-geoip

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-geoip
```

## Usage

```
<match access.apache>
  type geoip

  # buffering time
  flush_interval           1s

  # tag settings
  remove_tag_prefix        access.
  add_tag_prefix           geoip.
  include_tag_key          false

  # geoip settings
  geoip_lookup_key         host

  # record settings
  enable_key_city          geoip_city
  enbale_key_latitude      geoip_lat
  enbale_key_longitude     geoip_lon
  enbale_key_country_code3 geoip_country3
  enbale_key_country_code  geoip_country
  enbale_key_country_name  geoip_country_name
  enbale_key_dma_code      geoip_dma
  enbale_key_area_code     geoip_area
  enbale_key_region        geoip_region
</match>
```

## Tutorial

#### configuration

```
<source>
  type forward
</source>

<match test.geoip>
  type copy
  <store>
    type stdout
  </store>
  <store>
    type geoip
    geoip_lookup_key     host
    enable_key_city      city
    enbale_key_latitude  lat
    enbale_key_longitude lon
    remove_tag_prefix    test.
    add_tag_prefix       debug.
  </store>
</match>

<match debug.**>
  type stdout
</match>
```

#### result

```
# forward record with Google's ip address.
$ echo '{"host":"66.102.9.80","message":"test"}' | fluent-cat test.geoip

# check the result at stdout
$ tail /var/log/td-agent/td-agent.log
2013-08-04 16:21:32 +0900 test.geoip: {"host":"66.102.9.80","message":"test"}
2013-08-04 16:21:32 +0900 debug.geoip: {"host":"66.102.9.80","message":"test","city":"Mountain View","lat":37.4192008972168,"lon":-122.05740356445312}
```

## TODO

Pull requests are very welcome!!

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Copyright

Copyright (c) 2013- Kentaro Yoshida (@yoshi_ken)

## License

Apache License, Version 2.0

This product includes GeoLite data created by MaxMind, available from
<a href="http://www.maxmind.com">http://www.maxmind.com</a>.
