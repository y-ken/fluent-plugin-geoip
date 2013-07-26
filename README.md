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
<match access>
  type geoip

  # merge options
  merge_record           true  (default false)
  merge_record_with_key  data  (none default)

  # geoip options
  city_with_key          city
  latitude_with_key      lat
  longitude_with_key     lon
  country_code3_with_key country3
  country_code_with_key  country
  country_name_with_key  country_name
  dma_code_with_key      dma
  area_code_with_key     area
  region_with_key        region
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
