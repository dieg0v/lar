#!/bin/sh
set -eu
nginx -t
exec nginx -g 'daemon off;'
