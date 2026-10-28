#!/bin/sh
set -eu
apachectl configtest
exec apachectl -D FOREGROUND
