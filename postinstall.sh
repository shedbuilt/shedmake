#!/bin/bash
if [ ! -e /etc/shedmake/shedmake.conf ]; then
    install -v -m644 /etc/shedmake/shedmake.default /etc/shedmake/shedmake.conf
    sed -i "s/HWCONFIG=.*/HWCONFIG=${SHED_HWCONFIG}/g" /etc/shedmake/shedmake.conf
fi
