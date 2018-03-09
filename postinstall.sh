#!/bin/bash
if [ ! -e /etc/shedmake.conf ]; then
    install -v -m644 /etc/shedmake.conf.default /etc/shedmake.conf
fi
