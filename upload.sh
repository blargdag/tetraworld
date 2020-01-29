#!/bin/sh
#
# Simple upload script for updating website files.
#

SERVER=eusebeia
PORT=62222

scp -CP${PORT} \
	www/index.html \
	screenshots/2020-01-28a.gif \
	$SERVER:/var/www/tetraworld/
