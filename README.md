# fluent-plugin-geoip [![Build Status](https://travis-ci.org/y-ken/fluent-plugin-geoip.png?branch=master)](https://travis-ci.org/y-ken/fluent-plugin-geoip)

Fluentd Output plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.

fluent-plugin-geoip has bundled cost-free [GeoLite City database](http://dev.maxmind.com/geoip/legacy/geolite/) by default.<br />
Also you can use purchased [GeoIP City database](http://www.maxmind.com/en/city) ([lang:ja](http://www.maxmind.com/ja/city)) which costs starting from $50.

The accuracy details for GeoLite City (free) and GeoIP City (purchased) has described at the page below.

* http://www.maxmind.com/en/geolite_city_accuracy ([lang:ja](http://www.maxmind.com/ja/geolite_city_accuracy))
* http://www.maxmind.com/en/city_accuracy ([lang:ja](http://www.maxmind.com/ja/city_accuracy))

## Requirements

| fluent-plugin-geoip | fluentd    | ruby   |
|---------------------|------------|--------|
| >= 1.0.0            | >= v1.0.2  | >= 2.1 |
| < 1.0.0             | >= v0.12.0 | >= 1.9 |

If you want to use this plugin with Fluentd v0.12.x or earlier use 0.6.x.

### Compatibility notice

We've used Fluentd v1 API in this plugin since 1.0.0.
So we have dropped some features.

See also [official document](http://docs.fluentd.org/v1.0/articles/plugin-update-from-v12)

#### Fluent::Mixin::RewriteTagName

* `${tag}`, `__TAG__`

    Alternative: Use `${tag}` placeholder

* `${tag_parts[n]}`, `__TAG_PARTS[n]__`

    Alternative: Use `${tag[n]}` placeholder

* `${hostname}`, `__HOSTNAME__`

    Alternative1: Use filter before this plugin and chunk keys:
    ```
    <filter>
      @type record_transformer
      <record>
        hostname ${hostname}
      </record>
    </filter>
    <match **>
      @type geoip
      tag geoip.${tag[1]}.${hostname}
      <record>
        city ${city["host"]}
      </record>
      <buffer tag, hostname>
        flush_interval 1s
      </buffer>
    </match>
    ```

    Alternative2: Just inject hostname into record you can use `<inject>` section instead:
    ```
    <match **>
      @type geoip
      tag geoip.${tag[1]}.${hostname}
      <record>
        city ${city["host"]}
      </record>
      <inject>
        hostname_key hostname
      </inject>
    </match>
    ```

## Dependency

before use, install dependent library as:

```bash
# for RHEL/CentOS
$ sudo yum group install "Development Tools"
$ sudo yum install geoip-devel --enablerepo=epel

# for Ubuntu/Debian
$ sudo apt-get install build-essential
$ sudo apt-get install libgeoip-dev

# for OS X
$ brew install geoip
$ bundle config build.geoip-c --with-geoip-dir=/usr/local/include/
```

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

### For GeoipOutput

```xml
<match access.apache>
  @type geoip

  # Specify one or more geoip lookup field which has ip address (default: host)
  # in the case of accessing nested value, delimit keys by dot like 'host.ip'.
  geoip_lookup_key  host

  # Specify optional geoip database (using bundled GeoLiteCity databse by default)
  geoip_database    "/path/to/your/GeoIPCity.dat"
  # Specify optional geoip2 database
  # geoip2_database   "/path/to/your/GeoLite2-City.mmdb"
  # Specify backend library (geoip, geoip2_compat, geoip2_c)
  backend_library geoip

  # Set adding field with placeholder (more than one settings are required.)
  <record>
    latitude        ${latitude["host"]}
    longitude       ${longitude["host"]}
    country_code3   ${country_code3["host"]}
    country         ${country_code["host"]}
    country_name    ${country_name["host"]}
    dma             ${dma_code["host"]}
    area            ${area_code["host"]}
    region          ${region["host"]}
    city            ${city["host"]}
  </record>

  # Settings for tag
  tag               geoip.${tag[1]}

  # To avoid get stacktrace error with `[null, null]` array for elasticsearch.
  skip_adding_null_record  true

  # Set log_level for fluentd-v0.10.43 or earlier (default: warn)
  log_level         info

  <buffer tag>
    # Set buffering time (default: 0s)
    flush_interval    1s
  </buffer>
</match>
```

#### Tips: how to geolocate multiple key

```xml
<match access.apache>
  @type geoip
  geoip_lookup_key  user1_host, user2_host
  <record>
    user1_city      ${city["user1_host"]}
    user2_city      ${city["user2_host"]}
  </record>
  tag               geoip.${tag[1]}
</match>
```

#### Advanced config samples

It is a sample to get friendly geo point recdords for elasticsearch with Yajl (JSON) parser.<br />

**Notice** v0 config will be deprecated in the future.

```
<match access.apache>
  @type                  geoip
  geoip_lookup_key       host
  <record>
    # lat lon as properties
    # ex. {"lat" => 37.4192008972168, "lon" => -122.05740356445312 }
    location_properties  '{ "lat" : ${latitude["host"]}, "lon" : ${longitude["host"]} }'
  
    # lat lon as string
    # ex. "37.4192008972168,-122.05740356445312"
    location_string      ${latitude["host"]},${longitude["host"]}
    
    # GeoJSON (lat lon as array) is useful for Kibana's bettermap.
    # ex. [-122.05740356445312, 37.4192008972168]
    location_array       '[${longitude["host"]},${latitude["host"]}]'
  </record>
  tag                    geoip.${tag[1]}

  # To avoid get stacktrace error with `[null, null]` array for elasticsearch.
  skip_adding_null_record  true
</match>
```

On the case of using td-agent3 (v1-config), it have to quote `{ ... }` or `[ ... ]` block with quotation like below.

```
<match access.apache>
  @type                  geoip
  geoip_lookup_key       host
  <record>
    location_properties  '{ "lat" : ${latitude["host"]}, "lon" : ${longitude["host"]} }'
    location_string      ${latitude["host"]},${longitude["host"]}
    location_array       '[${longitude["host"]},${latitude["host"]}]'
  </record>
  remove_tag_prefix      access.
  tag                    geoip.${tag}
  skip_adding_null_record  true
</match>
```

### For GeoipFilter

Note that filter version of geoip plugin does not have handling tag feature.

```xml
<filter access.apache>
  @type geoip

  # Specify one or more geoip lookup field which has ip address (default: host)
  # in the case of accessing nested value, delimit keys by dot like 'host.ip'.
  geoip_lookup_key  host

  # Specify optional geoip database (using bundled GeoLiteCity databse by default)
  geoip_database    "/path/to/your/GeoIPCity.dat"
  # Specify optional geoip2 database
  # geoip2_database   "/path/to/your/GeoLite2-City.mmdb"
  # Specify backend library (geoip, geoip2_compat, geoip2_c)
  backend_library geoip

  # Set adding field with placeholder (more than one settings are required.)
  <record>
    city            ${city["host"]}
    latitude        ${latitude["host"]}
    longitude       ${longitude["host"]}
    country_code3   ${country_code3["host"]}
    country         ${country_code["host"]}
    country_name    ${country_name["host"]}
    dma             ${dma_code["host"]}
    area            ${area_code["host"]}
    region          ${region["host"]}
  </record>

  # To avoid get stacktrace error with `[null, null]` array for elasticsearch.
  skip_adding_null_record  true

  # Set log_level for fluentd-v0.10.43 or earlier (default: warn)
  log_level         info
</filter>
```

## Tutorial

### For GeoipOutput

#### configuration

```xml
<source>
  @type forward
</source>

<match test.geoip>
  @type copy
  <store>
    @type stdout
  </store>
  <store>
    @type    geoip
    geoip_lookup_key  host
    <record>
      lat     ${latitude["host"]}
      lon     ${longitude["host"]}
      country ${country_code["host"]}
    </record>
    tag     debug.${tag[1]}
  </store>
</match>

<match debug.**>
  @type stdout
</match>
```

#### result

```bash
# forward record with Google's ip address.
$ echo '{"host":"66.102.9.80","message":"test"}' | fluent-cat test.geoip

# check the result at stdout
$ tail /var/log/td-agent/td-agent.log
2013-08-04 16:21:32 +0900 test.geoip: {"host":"66.102.9.80","message":"test"}
2013-08-04 16:21:32 +0900 debug.geoip: {"host":"66.102.9.80","message":"test","lat":37.4192008972168,"lon":-122.05740356445312,"country":"US"}
```

For more details of geoip data format is described at the page below in section `GeoIP City Edition CSV Database Fields`.<br />
http://dev.maxmind.com/geoip/legacy/csv/

### For GeoipFilter

#### configuration

```xml
<source>
  @type forward
</source>

<filter test.geoip>
  @type    geoip
  geoip_lookup_key  host
  <record>
    city  ${city["host"]}
    lat   ${latitude["host"]}
    lon   ${longitude["host"]}
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

For more details of geoip data format is described at the page below in section `GeoIP City Edition CSV Database Fields`.<br />
http://dev.maxmind.com/geoip/legacy/csv/

## Placeholders

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

## Parameters

### GeoipOutput

* `include_tag_key` (default: false)
* `tag_key`

Add original tag name into filtered record using SetTagKeyMixin.<br />
Further details are written at http://docs.fluentd.org/articles/in_exec

* `skip_adding_null_record` (default: false)

Skip adding geoip fields when this valaues to `true`.
On the case of getting nothing of GeoIP info (such as local IP), it will output the original record without changing anything.

* `tag`

On using this option with tag placeholder like `tag geoip.${tag}` (test code is available at [test_out_geoip.rb](https://github.com/y-ken/fluent-plugin-geoip/blob/master/test/plugin/test_out_geoip.rb)).

* `flush_interval` (default: 0 sec)

Set buffering time to execute bulk lookup geoip.

### GeoipFilter

Note that filter version of `geoip` plugin does not have handling `tag` feature.

* `include_tag_key` (default: false)

Add original tag name into filtered record using SetTagKeyMixin.<br />
Further details are written at http://docs.fluentd.org/articles/in_exec

* `skip_adding_null_record` (default: false)

Skip adding geoip fields when this valaues to `true`.
On the case of getting nothing of GeoIP info (such as local IP), it will output the original record without changing anything.

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

* support [GeoIP2](http://dev.maxmind.com/geoip/geoip2/whats-new-in-geoip2/)

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
