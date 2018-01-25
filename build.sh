#!/bin/bash
if [ "$SHED_BUILDMODE" == 'toolchain' ]; then
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/tools/bin/shedmake"
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKEROOT}/tools/bin/shedmake"    
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKEROOT}/tools/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/shedmake.default.${SHED_DEVICE}" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/usr/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/template/.gitignore" "${SHED_FAKEROOT}/etc/shedmake/template/.gitignore"
    install -v -m644 "${SHED_CONTRIBDIR}/template/LICENSE" "${SHED_FAKEROOT}/etc/shedmake/template/LICENSE"
    install -v -m644 "${SHED_CONTRIBDIR}/shedmake.default.${SHED_DEVICE}" "${SHED_FAKEROOT}/etc/shedmake/shedmake.conf.default"
fi
