#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    echo "Post-install should not be performed for toolchain builds"
    exit 1
fi
if [ ! -e /etc/shedmake.conf ]; then
    ln -sfv /usr/share/defaults/shedmake/shedmake.conf /etc/shedmake.conf
fi
if [ ! -d /var/shedmake/template ]; then
    ln -sfv /usr/share/defaults/shedmake/template /var/shedmake/template
fi
