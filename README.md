# fluent-plugin-geoip [![Build Status](https://travis-ci.org/y-ken/fluent-plugin-geoip.png?branch=master)](https://travis-ci.org/y-ken/fluent-plugin-geoip)

Fluentd Filter plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.

fluent-plugin-geoip has bundled cost-free [GeoLite2 Free Downloadable Databases](https://dev.maxmind.com/geoip/geoip2/geolite2/) and [GeoLite City database](http://dev.maxmind.com/geoip/legacy/geolite/) by default.<br />
Also you can use purchased [GeoIP City database](http://www.maxmind.com/en/city) ([lang:ja](http://www.maxmind.com/ja/city)) which costs starting from $50.

The accuracy details for GeoLite City (free) and GeoIP City (purchased) has described at the page below.

* http://www.maxmind.com/en/geolite_city_accuracy ([lang:ja](http://www.maxmind.com/ja/geolite_city_accuracy))
* http://www.maxmind.com/en/city_accuracy ([lang:ja](http://www.maxmind.com/ja/city_accuracy))

## Requirements

| fluent-plugin-geoip | fluentd    | ruby   |
|---------------------|------------|--------|
| >= 1.0.0            | >= v1.0.2  | >= 2.1 |
| < 1.0.0             | >= v0.12.0 | >= 1.9 |

If you want to use this plugin with Fluentd v0.12.x or earlier use 0.8.x.

### Compatibility notice

We've removed GeoipOutput since 1.3.0, because GeoipFilter is enough to add information about geographical location of IP addresse.

## Dependency

before use, install dependent library as:

```bash
# for RHEL/CentOS
$ sudo yum groupinstall "Development Tools"
$ sudo yum install geoip-devel --enablerepo=epel

# for Ubuntu/Debian
$ sudo apt-get install build-essential
$ sudo apt-get install libgeoip-dev

# for OS X
$ brew install geoip
$ bundle config build.geoip-c --with-geoip-dir=/usr/local/include/
```

See [geoip2_c](https://github.com/okkez/geoip2_c#build-requirements), if you failed to install geoip2_c.

## Installation

install with `gem` or td-agent provided command as:

```bash
# for fluentd
$ gem install fluent-plugin-geoip

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-geoip

# for td-agent2
$ sudo td-agent-gem install fluent-plugin-geoip
```

## Usage

### For GeoipFilter

Note that filter version of geoip plugin does not have handling tag feature.

```xml
<filter access.apache>
  @type geoip

  # Specify one or more geoip lookup field which has ip address (default: host)
  geoip_lookup_keys host

  # Specify optional geoip database (using bundled GeoLiteCity databse by default)
  # geoip_database    "/path/to/your/GeoIPCity.dat"
  # Specify optional geoip2 database
  # geoip2_database   "/path/to/your/GeoLite2-City.mmdb" (using bundled GeoLite2-City.mmdb by default)
  # Specify backend library (geoip2_c, geoip, geoip2_compat)
  backend_library geoip2_c

  # Set adding field with placeholder (more than one settings are required.)
  <record>
    city            ${city.names.en["host"]}
    latitude        ${location.latitude["host"]}
    longitude       ${location.longitude["host"]}
    country         ${country.iso_code["host"]}
    country_name    ${country.names.en["host"]}
    postal_code     ${postal.code["host"]}
  </record>

  # To avoid get stacktrace error with `[null, null]` array for elasticsearch.
  skip_adding_null_record  true

  # Set @log_level (default: warn)
  @log_level         info
</filter>
```

#### Tips: how to geolocate multiple key

```xml
<filter access.apache>
  @type geoip
  geoip_lookup_keys user1_host, user2_host
  <record>
    user1_city      ${city.names.en["user1_host"]}
    user2_city      ${city.names.en["user2_host"]}
  </record>
</filter>
```

#### Tips: Modify records without city information

```
<filter access.apache>
  @type geoip
  geoip_lookup_keys remote_addr
  <record>
    city         ${city.names.en["remote_addr"]}     # skip adding fields if this field is null
    latitude     ${location.latitude["remote_addr"]}
    longitude    ${location.longitude["remote_addr"]}
    country      ${country.iso_code["remote_addr"]}
    country_name ${country.names.en["remote_addr"]}
    postal_code  ${postal.code["remote_addr"]}
  </record>
  skip_adding_null_record true
</filter>
```

Skip adding fields if incoming `remote_addr`'s GeoIP data is like following:

```ruby
# the record does not have "city" field
{"continent"=>
  {"code"=>"NA",
   "geoname_id"=>6255149,
   "names"=>
    {"de"=>"Nordamerika",
     "en"=>"North America",
     "es"=>"Norteamérica",
     "fr"=>"Amérique du Nord",
     "ja"=>"北アメリカ",
     "pt-BR"=>"América do Norte",
     "ru"=>"Северная Америка",
     "zh-CN"=>"北美洲"}},
 "country"=>
  {"geoname_id"=>6252001,
   "iso_code"=>"US",
   "names"=>
    {"de"=>"USA",
     "en"=>"United States",
     "es"=>"Estados Unidos",
     "fr"=>"États-Unis",
     "ja"=>"アメリカ合衆国",
     "pt-BR"=>"Estados Unidos",
     "ru"=>"США",
     "zh-CN"=>"美国"}},
 "location"=>
  {"accuracy_radius"=>1000, "latitude"=>37.751, "longitude"=>-97.822},
 "registered_country"=>
  {"geoname_id"=>6252001,
   "iso_code"=>"US",
   "names"=>
    {"de"=>"USA",
     "en"=>"United States",
     "es"=>"Estados Unidos",
     "fr"=>"États-Unis",
     "ja"=>"アメリカ合衆国",
     "pt-BR"=>"Estados Unidos",
     "ru"=>"США",
     "zh-CN"=>"美国"}}}
```

We can avoid this behavior changing field order in `<record>` like following:

```
<filter access.apache>
  @type geoip
  geoip_lookup_keys remote_addr
  <record>
    latitude     ${location.latitude["remote_addr"]} # this field must not be null
    longitude    ${location.longitude["remote_addr"]}
    country      ${country.iso_code["remote_addr"]}
    country_name ${country.names.en["remote_addr"]}
    postal_code  ${postal.code["remote_addr"]}
    city         ${city.names.en["remote_addr"]}     # adding fields even if this field is null
  </record>
  skip_adding_null_record true
</filter>
```

#### Tips: nested attributes for geoip_lookup_keys

See [Record Accessor Plugin Helper](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-record_accessor)

**NOTE** Since v1.3.0 does not interpret `host.ip` as nested attribute.

#### Advanced config samples

It is a sample to get friendly geo point recdords for elasticsearch with Yajl (JSON) parser.<br />

```
<filter access.apache>
  @type                  geoip
  geoip_lookup_keys      host
  <record>
    # lat lon as properties
    # ex. {"lat" => 37.4192008972168, "lon" => -122.05740356445312 }
    location_properties  '{ "lat" : ${location.latitude["host"]}, "lon" : ${location.longitude["host"]} }'
  
    # lat lon as string
    # ex. "37.4192008972168,-122.05740356445312"
    location_string      ${location.latitude["host"]},${location.longitude["host"]}
    
    # GeoJSON (lat lon as array) is useful for Kibana's bettermap.
    # ex. [-122.05740356445312, 37.4192008972168]
    location_array       '[${location.longitude["host"]},${location.latitude["host"]}]'
  </record>

  # To avoid get stacktrace error with `[null, null]` array for elasticsearch.
  skip_adding_null_record  true
</filter>
```

On the case of using td-agent3 (v1-config), it have to quote `{ ... }` or `[ ... ]` block with quotation like below.

```
<filter access.apache>
  @type                  geoip
  geoip_lookup_keys      host
  <record>
    location_properties  '{ "lat" : ${location.latitude["host"]}, "lon" : ${location.longitude["host"]} }'
    location_string      ${location.latitude["host"]},${location.longitude["host"]}
    location_array       '[${location.longitude["host"]},${location.latitude["host"]}]'
  </record>
  skip_adding_null_record  true
</filter>
```

## Tutorial

### For GeoipFilter

#### configuration

```xml
<source>
  @type forward
</source>

<filter test.geoip>
  @type    geoip
  geoip_lookup_keys  host
  <record>
    city  ${city.names.en["host"]}
    lat   ${location.latitude["host"]}
    lon   ${location.longitude["host"]}
  </record>
</filter>

<match test.**>
  @type stdout
</match>
```

#### result

```bash
# forward record with Google's ip address.
$ echo '{"host":"66.102.9.80","message":"test"}' | fluent-cat test.geoip

# check the result at stdout
$ tail /var/log/td-agent/td-agent.log
2016-02-01 12:04:37 +0900 test.geoip: {"host":"66.102.9.80","message":"test","city":"Mountain View","lat":37.4192008972168,"lon":-122.05740356445312}
```

You can check geoip data format using [utils/dump.rb](https://github.com/okkez/fluent-plugin-geoip/utils/dump.rb).

```
$ bundle exec ruby urils/dump.rb geoip2 66.102.3.80
$ bundle exec ruby urils/dump.rb geoip2_compat 66.102.3.80
$ bundle exec ruby urils/dump.rb geoip 66.102.3.80
```

## Placeholders

### GeoIP2

You can get any fields in the
[GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/) database and
[GeoIP2 Downloadable Databases](http://dev.maxmind.com/geoip/geoip2/downloadable/).

For example(geoip2_c backend):

| placeholder attributes                   | output example     | note |
|------------------------------------------|--------------------|------|
| ${city.names.en[lookup_field]}           | "Mountain View"    | -    |
| ${location.latitude[lookup_field]}       | 37.419200000000004 | -    |
| ${location.longitude[lookup_field]}      | -122.0574          | -    |
| ${country.iso_code[lookup_field]}        | "US"               | -    |
| ${country.names.en[lookup_field]}        | "United States"    | -    |
| ${postal.code[lookup_field]}             | "94043"            | -    |
| ${subdivisions.0.iso_code[lookup_field]} | "CA"               | -    |
| ${subdivisions.0.names.en[lookup_field]} | "California"       | -    |

For example(geoip2_compat backend):

| placeholder attributes        | output example     | note |
|-------------------------------|--------------------|------|
| ${city[lookup_field]}         | "Mountain View"    | -    |
| ${latitude[lookup_field]}     | 37.419200000000004 | -    |
| ${longitude[lookup_field]}    | -122.0574          | -    |
| ${country_code[lookup_field]} | "US"               | -    |
| ${country_name[lookup_field]} | "United States"    | -    |
| ${postal_code[lookup_field]}  | "94043"            |      |
| ${region[lookup_field]}       | "CA"               | -    |
| ${region_name[lookup_field]}  | "California"       | -    |

**NOTE**: geoip2_compat backend supports only above fields.

Related configurations:

* `backend_library`: `geoip2_compat` or `geoip2_c`
* `geoip2_database`: path to your GeoLite2-City.mmdb

### GeoIP legacy

Provides these placeholders for adding field of geolocate results.<br />
For more example of geolocating, you can try these websites like [Geo IP Address View](http://www.geoipview.com/) or [View my IP information](http://www.geoiptool.com/en/).

| placeholder attributes         | output example    | type         | note |
|--------------------------------|-------------------|--------------|------|
| ${city[lookup_field]}          | "Ithaca"          | varchar(255) |  -   |
| ${latitude[lookup_field]}      | 42.4277992248535  | decimal      |  -   |
| ${longitude[lookup_field]}     | -76.4981994628906 | decimal      |  -   |
| ${country_code3[lookup_field]} | "USA"             | varchar(3)   |  -   |
| ${country_code[lookup_field]}  | "US"              | varchar(2)   | A two-character ISO 3166-1 country code      |
| ${country_name[lookup_field]}  | "United States"   | varchar(50)  |  -   |
| ${dma_code[lookup_field]}      | 555               | unsigned int | **only for US**  |
| ${area_code[lookup_field]}     | 607               | char(3)      | **only for US**  |
| ${region[lookup_field]}        | "NY"              | char(2)      | A two character ISO-3166-2 or FIPS 10-4 code |

Further more specification available at http://dev.maxmind.com/geoip/legacy/csv/#GeoIP_City_Edition_CSV_Database_Fields

Related configurations:

* `backend_library`: `geoip` (default)
* `geoip_database`: path to your GeoLiteCity.dat

## Parameters

### GeoipFilter

Note that filter version of `geoip` plugin does not have handling `tag` feature.

#### Plugin helpers

* [compat_parameters](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-compat_parameters)
* [inject](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-inject)

See also [Filter Plugin Overview](https://docs.fluentd.org/filter)

#### Supported sections

* [Inject section configurations](https://docs.fluentd.org/configuration/inject-section)

#### Parameters

[Plugin Common Paramteters](https://docs.fluentd.org/configuration/plugin-common-parameters)

**geoip_database** (string) (optional)

* Default value: bundled database `GeoLiteCity.dat`

Path to GeoIP database file.

**geoip2_database** (string) (optional)

* Default value: bundled database `GeoLite2-City.mmdb`.

Path to GeoIP2 database file.

**geoip_lookup_keys** (array) (optional)

* Default_value: `["host"]`

Specify one or more geoip lookup field which has IP address.

**geoip_lookup_key** (string) (optional) (deprecated)

* Default value: `nil`.

Use geoip_lookup_keys instead.

**skip_adding_null_record** (bool) (optional)

* Default value: `nil`

Skip adding geoip fields when this valaues to `true`.
On the case of getting nothing of GeoIP info (such as local IP), it will output the original record without changing anything.

**backend_library** (enum) (optional)

* Available values: `geoip`, `geoip2_compat`, `geoip2_c`
* Default value: `geoip2_c`.

Set backend library.

## Articles

* [IPアドレスを元に位置情報をリアルタイムに付与する fluent-plugin-geoip v0.0.1をリリースしました #fluentd - Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-has-released)<br />
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-has-released

* [初の安定版 fluent-plugin-geoip v0.0.3 をリリースしました #fluentd- Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.3)<br />
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.3

* [fluent-plugin-geoip v0.0.4 をリリースしました。ElasticSearch＋Kibanaの世界地図に位置情報をプロットするために必要なFluentdの設定サンプルも紹介します- Y-Ken Studio](http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.4)<br />
http://y-ken.hatenablog.com/entry/fluent-plugin-geoip-v0.0.4

* [Released GeoIP plugin to work together with ElasticSearch + Kibana v3](https://groups.google.com/d/topic/fluentd/OVIcH_SKBwM/discussion)<br />
https://groups.google.com/d/topic/fluentd/OVIcH_SKBwM/discussion

* [Fluentd、Amazon RedshiftとTableauを用いたカジュアルなデータ可視化 | SmartNews開発者ブログ](http://developer.smartnews.be/blog/2013/10/03/easy-data-analysis-using-fluentd-redshift-and-tableau/)<br />
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

Copyright (c) 2013- Kentaro Yoshida ([@yoshi_ken](https://twitter.com/yoshi_ken))

## License

Apache License, Version 2.0

This product includes GeoLite data created by MaxMind, available from
<a href="http://www.maxmind.com">http://www.maxmind.com</a>.
