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

TODO: Write usage instructions here

```
<match access.apache>
  type geoip

  # tag options
  tag_prefix               geoip
  remove_tag_prefix        access

  # merge options
  merge_record             true  (default false)
  merge_record_with_key    data  (none default)

  # selectable geoip record
  enable_key_city          city
  enbale_key_latitude      lat
  enbale_key_longitude     lon
  enbale_key_country_code3 country3
  enbale_key_country_code  country
  enbale_key_country_name  country_name
  enbale_key_dma_code      dma
  enbale_key_area_code     area
  enbale_key_region        region
</match>
```

## TODO

patches welcome!

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
