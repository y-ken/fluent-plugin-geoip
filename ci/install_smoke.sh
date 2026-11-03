#!/bin/sh
# Install smoke test: reproduces the README install steps inside the official
# fluent/fluentd Debian image to verify the geoip-c and geoip2_c native
# extensions actually build and the plugin loads. Guards against the
# "requires native extensions" class of breakage reported in #94 / #99 / #100.
set -eux

GEM_FILE="${GEM_FILE:-/workspace/pkg/fluent-plugin-geoip.gem}"

# The README steps for Ubuntu/Debian. pkg-config is the bit that minimal images
# lack: geoip2_c builds its bundled libmaxminddb, whose configure needs it.
apt-get update
apt-get install -y build-essential libgeoip-dev libmaxminddb-dev pkg-config

# Installing the gem compiles the native extensions; this fails loudly if the
# headers are missing, which is exactly what we want to catch.
gem install "$GEM_FILE"

# Confirm the installed plugin (and both native extensions) load at runtime.
ruby "$(dirname "$0")/verify_plugin_load.rb"
