# fluent-plugin-geoip [![Build Status](https://travis-ci.org/y-ken/fluent-plugin-geoip.png?branch=master)](https://travis-ci.org/y-ken/fluent-plugin-geoip)

Fluentd Output plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.

fluent-plugin-geoip has bundled cost-free [GeoLite City database](http://dev.maxmind.com/geoip/legacy/geolite/) by default.  
Also you can use purchased [GeoIP City database](http://www.maxmind.com/en/city) ([lang:ja](http://www.maxmind.com/ja/city)) which costs starting from $50.  

The accuracy details for GeoLite City (free) and GeoIP City (purchased) has described at the page below.

* http://www.maxmind.com/en/geolite_city_accuracy ([lang:ja](http://www.maxmind.com/ja/geolite_city_accuracy))
* http://www.maxmind.com/en/city_accuracy ([lang:ja](http://www.maxmind.com/ja/city_accuracy))

## Dependency

before use, install dependent library as:

```bash
# for RHEL/CentOS
$ sudo yum install geoip-devel --enablerepo=epel

# for Ubuntu/Debian
$ sudo apt-get install libgeoip-dev
```

## Installation

install with `gem` or `fluent-gem` command as:

```bash
# for fluentd
$ gem install fluent-plugin-geoip

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-geoip
```

## Usage

```xml
<match access.apache>
  type geoip

  # Specify geoip lookup field (default: host)
  # in the case of accessing nested value, delimit keys by dot like 'host.ip'.
  geoip_lookup_key         host

  # Specify geoip database (using bundled GeoLiteCity databse by default)
  geoip_database           'data/GeoLiteCity.dat'

  # Set adding field of geolocate results (more than one settings are required.)
  enable_key_city          geoip_city
  enable_key_latitude      geoip_lat
  enable_key_longitude     geoip_lon
  enable_key_country_code3 geoip_country3
  enable_key_country_code  geoip_country
  enable_key_country_name  geoip_country_name
  enable_key_dma_code      geoip_dma
  enable_key_area_code     geoip_area
  enable_key_region        geoip_region

  # Settings for tag
  remove_tag_prefix        access.
  tag                      geoip.

  # Buffering time (default: 0s)
  flush_interval           1s
</match>
```

#### Tips: how to geolocate multiple key

```xml
<match access.apache>
  type geoip

  # Set ip address key to geolocate
  geoip_lookup_key        user1_host, user2_host

  # Set adding field of geolocate results
  enable_key_city         user1_city, user2_city
  enable_key_country_name user1_country, user2_country

  # Setting for tag
  remove_tag_prefix       access.
  add_tag_prefix          geoip.

  # Buffering time
  flush_interval          1s
</match>
```

## Tutorial

#### configuration

```xml
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
    enable_key_latitude  lat
    enable_key_longitude lon
    remove_tag_prefix    test.
    add_tag_prefix       debug.
    flush_interval       5s
  </store>
</match>

<match debug.**>
  type stdout
</match>
```

#### result

```bash
# forward record with Google's ip address.
$ echo '{"host":"66.102.9.80","message":"test"}' | fluent-cat test.geoip

# check the result at stdout
$ tail /var/log/td-agent/td-agent.log
2013-08-04 16:21:32 +0900 test.geoip: {"host":"66.102.9.80","message":"test"}
2013-08-04 16:21:32 +0900 debug.geoip: {"host":"66.102.9.80","message":"test","city":"Mountain View","lat":37.4192008972168,"lon":-122.05740356445312}
```

For more details of geoip data format is described at the page below in section `GeoIP City Edition CSV Database Fields`.  
http://dev.maxmind.com/geoip/legacy/csv/

## Parameters

* `enable_key_*` (example: enable_key_city)
  * city
  * latitude
  * longitude
  * country_code3
  * country_code
  * country_name
  * dma_code
  * area_code
  * region

Set adding field of geolocate results (more than one settings are required.)

* `include_tag_key` (default: false)
* `tag_key`

Add original tag name into filtered record using SetTagKeyMixin.<br />
Further details are written at http://docs.fluentd.org/articles/in_exec

* `remove_tag_prefix`
* `remove_tag_suffix`
* `add_tag_prefix`
* `add_tag_suffix`

Set one or more option are required unless using `tag` option for editing tag name. (HandleTagNameMixin feature)

* `tag`

On using this option with tag placeholder like `tag geoip.${tag}` (test code is available at [test_out_geoip.rb](https://github.com/y-ken/fluent-plugin-geoip/blob/master/test/plugin/test_out_geoip.rb)), it will be overwrite after these options affected. which are remove_tag_prefix, remove_tag_suffix, add_tag_prefix and add_tag_suffix.

* `flush_interval` (default: 0 sec)

Set buffering time to execute bulk lookup geoip.

## Articles

* [IPアドレスを元に位置情報をリアルタイムに付与する fluent-plugin-geoip v0.0.1をリリースしました #fluentd - Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-has-released)  
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-has-released

* [初の安定版 fluent-plugin-geoip v0.0.3 をリリースしました #fluentd- Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.3)  
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.3

* [fluent-plugin-geoip v0.0.4 をリリースしました。ElasticSearch＋Kibanaの世界地図に位置情報をプロットするために必要なFluentdの設定サンプルも紹介します- Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.4)  
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.4

* [Released GeoIP plugin to work together with ElasticSearch + Kibana v3](https://groups.google.com/d/topic/fluentd/OVIcH_SKBwM/discussion)  
https://groups.google.com/d/topic/fluentd/OVIcH_SKBwM/discussion

* [Fluentd、Amazon RedshiftとTableauを用いたカジュアルなデータ可視化 | SmartNews開発者ブログ](http://developer.smartnews.be/blog/2013/10/03/easy-data-analysis-using-fluentd-redshift-and-tableau/)  
http://developer.smartnews.be/blog/2013/10/03/easy-data-analysis-using-fluentd-redshift-and-tableau/

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
