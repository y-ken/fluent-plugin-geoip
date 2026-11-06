# fluent-plugin-geoip [![CI](https://github.com/y-ken/fluent-plugin-geoip/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/y-ken/fluent-plugin-geoip/actions/workflows/ci.yml)

Fluentd Filter plugin to add information about geographical location of IP addresses with Maxmind GeoIP databases.

fluent-plugin-geoip has bundled cost-free [GeoLite2 Free Downloadable Databases](https://dev.maxmind.com/geoip/geoip2/geolite2/) and the legacy GeoLite City database by default.<br />
Also you can use the purchased [GeoIP City database](https://www.maxmind.com/en/geoip-databases) with `geoip2_database`.

The bundled databases are from December 2017, so they do not have many IP addresses that are in use now, and some locations are out of date.
MaxMind [no longer updates](https://blog.maxmind.com/discontinuation-of-the-geolite-legacy-databases/) the legacy GeoLite City database (`GeoLiteCity.dat`).
[Since December 30, 2019](https://blog.maxmind.com/significant-changes-to-accessing-and-using-geolite-databases/), downloading the GeoLite2 databases needs a free MaxMind account, and they are under the [GeoLite2 End User License Agreement](https://www.maxmind.com/en/geolite2/eula), which includes a Creative Commons license and adds further conditions, so this plugin does not bundle newer databases.
To use an up-to-date database, download `GeoLite2-City.mmdb` with [geoipupdate](https://github.com/maxmind/geoipupdate), and set its path to `geoip2_database`.
The directory depends on how geoipupdate is installed. It is `DatabaseDirectory` in `GeoIP.conf`:

```
<filter access.apache>
  @type geoip
  geoip_lookup_keys host
  geoip2_database   /usr/share/GeoIP/GeoLite2-City.mmdb
  <record>
    city ${city.names.en["host"]}
  </record>
</filter>
```

Run `geoipupdate` regularly, for example with cron.
This plugin reads the database when Fluentd starts, so restart or reload Fluentd after `geoipupdate` updates the file.
If you update the file in another way, write a new file in the same directory and rename it, as `geoipupdate` does. Changing the `.mmdb` file in place while Fluentd is running can break lookups or crash Fluentd.

With `backend_library geoip`, the plugin reads only the legacy `.dat` file in `geoip_database`, and ignores `geoip2_database`.
The purchased GeoIP Legacy databases were also [retired in 2022](https://blog.maxmind.com/geoip-legacy-databases-have-been-retired/), so no legacy database gets updates.
So set `geoip2_database` as above, change `backend_library` to `geoip2_c`, and rewrite the placeholders in the [GeoIP2](#geoip2) form.
For example, `${city["host"]}` becomes `${city.names.en["host"]}`, `${latitude["host"]}` becomes `${location.latitude["host"]}`, and `${country_code["host"]}` becomes `${country.iso_code["host"]}`.
With the legacy placeholders, `geoip2_c` does not raise an error, but the values are wrong.
For example, for `66.102.3.80`, `${latitude["host"]}` becomes `0.0`, `${country_code["host"]}` becomes `null`, and `${city["host"]}` becomes a Hash.

MaxMind compares the accuracy of its current City databases, purchased and free, at the page below.

* https://www.maxmind.com/en/geoip-accuracy-comparison

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
$ sudo apt-get install pkg-config

# for OS X
$ brew install geoip
$ bundle config build.geoip-c --with-geoip-dir=/usr/local/include/
```

`geoip-devel` is not in EPEL 9 or 10. On RHEL 9 and 10 and their clones, such as Rocky Linux and AlmaLinux, the `yum install geoip-devel` line above fails, and installing this plugin then fails while building geoip-c (`Failed to build gem native extension`). Build the GeoIP C library from source instead:

```bash
$ curl -fLO https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz
$ tar xzf GeoIP-1.6.12.tar.gz
$ cd GeoIP-1.6.12
$ ./configure && make && sudo make install
$ echo /usr/local/lib | sudo tee /etc/ld.so.conf.d/geoip.conf && sudo ldconfig
```

geoip-c is planned to become an optional dependency in v1.4.0 ([#108](https://github.com/y-ken/fluent-plugin-geoip/issues/108)).

[geoip2_c](https://github.com/fluent-plugins-nursery/geoip2_c) does not need libmaxminddb installed on the system. When it is installed, it downloads the source of [libmaxminddb](https://github.com/maxmind/libmaxminddb) from GitHub and builds it. So installing this plugin needs:

* access to `github.com`. Without it, the installation fails with `Failed to open TCP connection to github.com:443`.
* a C compiler and `pkg-config`. "Development Tools" of RHEL/CentOS includes both. Without `pkg-config`, it fails with `pkg-config not found`.

`libmaxminddb-dev` (`libmaxminddb-devel`) is not needed. geoip2_compat also builds the libmaxminddb that it bundles.

See [geoip2_c](https://github.com/fluent-plugins-nursery/geoip2_c), if you failed to install geoip2_c.

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

#### Tips: values that are not found

When the value of a lookup key is not found in the database, every placeholder for it becomes `null`.
This happens for private and reserved IP addresses such as `10.0.0.1`, for IP addresses that the database does not have, and for values that are not an IP address, such as `-`, `1.2.3.4, 5.6.7.8` (X-Forwarded-For) or `1.2.3.4:8080`.
Note that `geoip2_c` and `geoip2_compat` read some other forms as an IPv4 address, such as `1113195344` (`66.90.3.80`), and on Linux, `066.102.3.80` (`54.102.3.80`, in octal).
In a string, `null` becomes an empty string, so `${location.latitude["host"]},${location.longitude["host"]}` becomes `,`.
Elasticsearch rejects such a value for a `geo_point` field.
Set `skip_adding_null_record true` to output such records without adding the fields of `<record>`.

When the IP address is found but the database has no location for it, `latitude` and `longitude` become `0.0`, not `null`.
`skip_adding_null_record` checks only the first placeholder in `<record>` (with more than one key in `geoip_lookup_keys`, the first placeholder whose key is found), so the result depends on the order:

```
<filter access.apache>
  @type geoip
  geoip_lookup_keys host
  <record>
    city     ${city.names.en["host"]}
    location ${location.latitude["host"]},${location.longitude["host"]}
  </record>
  skip_adding_null_record true
</filter>
```

| host             | found          | output                                                          |
|------------------|----------------|-----------------------------------------------------------------|
| `66.102.3.80`    | with a city    | `{"host":"66.102.3.80","city":"Mountain View","location":"37.419200000000004,-122.0574"}` |
| `193.56.131.219` | no location    | `{"host":"193.56.131.219"}`                                     |
| `10.0.0.1`       | not found      | `{"host":"10.0.0.1"}`                                           |
| `-`              | not an IP      | `{"host":"-"}`                                                  |

If `location` comes first instead, the record for `193.56.131.219` gets `"location":"0.0,0.0"` and `"city":null`.

#### Tips: nested attributes for geoip_lookup_keys

See [Record Accessor Plugin Helper](https://docs.fluentd.org/plugin-helper-overview/api-plugin-helper-record_accessor)

**NOTE** Since v1.3.0 does not interpret `host.ip` as nested attribute.

#### Advanced config samples

It is a sample to get friendly geo point recdords for elasticsearch with JSON parser.<br />

```
<filter access.apache>
  @type                  geoip
  geoip_lookup_keys      host
  <record>
    # lat lon as properties
    # ex. {"lat" => 37.419200000000004, "lon" => -122.0574 }
    location_properties  '{ "lat" : ${location.latitude["host"]}, "lon" : ${location.longitude["host"]} }'
  
    # lat lon as string
    # ex. "37.419200000000004,-122.0574"
    location_string      ${location.latitude["host"]},${location.longitude["host"]}
    
    # GeoJSON (lat lon as array) is useful for Kibana's bettermap.
    # ex. [-122.0574, 37.419200000000004]
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
2016-02-01 12:04:37 +0900 test.geoip: {"host":"66.102.9.80","message":"test","city":"Mountain View","lat":37.419200000000004,"lon":-122.0574}
```

You can check geoip data format using [utils/dump.rb](https://github.com/y-ken/fluent-plugin-geoip/blob/master/utils/dump.rb).

```
$ bundle exec ruby utils/dump.rb geoip2 66.102.3.80
$ bundle exec ruby utils/dump.rb geoip2_compat 66.102.3.80
$ bundle exec ruby utils/dump.rb geoip 66.102.3.80
```

## Placeholders

### GeoIP2

You can get any fields in the [GeoLite2](http://dev.maxmind.com/geoip/geoip2/geolite2/) database and [GeoIP2 Downloadable Databases](https://dev.maxmind.com/geoip/docs/databases/city-and-country/).

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

* `backend_library`: `geoip2_c` (default) or `geoip2_compat`
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

See [the archived MaxMind page](https://web.archive.org/web/20181228225721/https://dev.maxmind.com/geoip/legacy/csv/#GeoIP_Legacy_City_CSV_Database_Fields) for more details.

Related configurations:

* `backend_library`: `geoip`
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

* Default value: `false`

Skip adding geoip fields when this value is `true`.
It checks the first placeholder in `<record>` whose lookup key is found in the database.
When no lookup key is found, such as for a local IP, or that placeholder is `null`, it does not add any field of `<record>`, even one without a placeholder. The fields of `<inject>` are still added.

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
