#!/bin/bash


envsubst < /etc/logstash/conf.d/logstash.conf
# Download updated translation maps
cd /etc/listbot 
git pull --all --depth=1
cd /
