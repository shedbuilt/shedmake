#!/bin/bash
if [ "$SHED_BUILDMODE" == 'toolchain' ]; then
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/tools/bin/shedmake"
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKEROOT}/tools/bin/shedmake"    
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKEROOT}/tools/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/usr/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/template/.gitignore" "${SHED_FAKEROOT}/var/shedmake/template/.gitignore"
    install -v -m644 "${SHED_CONTRIBDIR}/template/package.txt" "${SHED_FAKEROOT}/var/shedmake/template/package.txt"
    install -v -m755 "${SHED_CONTRIBDIR}/template/build.sh" "${SHED_FAKEROOT}/var/shedmake/template/build.sh"
    install -v -m644 "${SHED_CONTRIBDIR}/template/LICENSE" "${SHED_FAKEROOT}/var/shedmake/template/LICENSE"
    install -v -Dm644 "${SHED_CONTRIBDIR}/shedmake.conf.${SHED_DEVICE}" "${SHED_FAKEROOT}/etc/shedmake.conf.default"
    chgrp -v -R shedmake "${SHED_FAKEROOT}/var/shedmake"
    chmod -v -R g+s "${SHED_FAKEROOT}/var/shedmake"
fi
