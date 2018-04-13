#!/bin/bash
if [ "$SHED_BUILD_MODE" == 'toolchain' ]; then
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKE_ROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/usr/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/template/.gitignore" "${SHED_FAKE_ROOT}/var/shedmake/template/.gitignore" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/package.txt" "${SHED_FAKE_ROOT}/var/shedmake/template/package.txt" &&
    install -v -m755 "${SHED_PKG_CONTRIB_DIR}/template/build.sh" "${SHED_FAKE_ROOT}/var/shedmake/template/build.sh" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/LICENSE" "${SHED_FAKE_ROOT}/var/shedmake/template/LICENSE" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKE_ROOT}/etc/shedmake.conf.default" &&
    chgrp -v -R shedmake "${SHED_FAKE_ROOT}/var/shedmake" &&
    chmod -v -R g+s "${SHED_FAKE_ROOT}/var/shedmake"
fi
