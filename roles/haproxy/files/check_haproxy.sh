#!/bin/sh
# check_haproxy.sh — exit 0 while the haproxy process is running.
pidof haproxy >/dev/null 2>&1
