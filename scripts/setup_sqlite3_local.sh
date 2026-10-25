#!/usr/bin/env bash
set -e
mkdir -p /tmp/sqlite_dl ~/.local/lib
cd /tmp/sqlite_dl
apt-get download libsqlite3-0 2>/dev/null || apt-get download libsqlite3-0
dpkg -x libsqlite3-0*.deb extracted
find extracted -name "libsqlite3.so*" -exec cp -a {} ~/.local/lib/ \;
cd ~/.local/lib
# 统一提供一个无版本号符号链接
SO=$(ls libsqlite3.so.0* | head -1)
ln -sf "$SO" libsqlite3.so
ls -la ~/.local/lib/
