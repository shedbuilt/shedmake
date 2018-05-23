#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKE_ROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/usr/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/template/.gitignore" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake/template/.gitignore" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/package.txt" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake/template/package.txt" &&
    install -v -m755 "${SHED_PKG_CONTRIB_DIR}/template/build.sh" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake/template/build.sh" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/LICENSE" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake/template/LICENSE" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake/shedmake.conf" &&
    chgrp -v -R shedmake "${SHED_FAKE_ROOT}/var/shedmake" "${SHED_FAKE_ROOT}/usr/share/defaults/shedmake"
fi
