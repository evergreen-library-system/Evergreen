#!/bin/sh

PID=$$

BINDIR/autogen.sh $@ |tee /tmp/.eg-cache-generator.$PID

(
  date +%Y%m%d
  for i in `grep -- '->' /tmp/.eg-cache-generator.$PID| awk '{print $2}'`; do
    ls $i >/dev/null 2>/dev/null && md5sum $i
  done
) | md5sum | cut -f1 -d' ' | colrm 1 26 > SYSCONFDIR/eg_cache_hash

echo
echo -n "Current Evergreen cache key: "
cat SYSCONFDIR/eg_cache_hash

rm /tmp/.eg-cache-generator.$PID

