#!/bin/bash
if [ "$SHED_BUILDMODE" == 'toolchain' ]; then
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/tools/bin/shedmake"
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKEROOT}/tools/bin/shedmake"    
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKEROOT}/tools/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/shedmake.conf" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
    sed -i "s/HWCONFIG=.*/HWCONFIG=${SHED_HWCONFIG}/g" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
    sed -i "s/NATIVE_TARGET=.*/NATIVE_TARGET=${SHED_NATIVE_TARGET}/g" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
    sed -i "s/TOOLCHAIN_TARGET=.*/TOOLCHAIN_TARGET=${SHED_TOOLCHAIN_TARGET}/g" "${SHED_FAKEROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/usr/bin/shedmake"
    install -v -Dm644 "${SHED_CONTRIBDIR}/template/.gitignore" "${SHED_FAKEROOT}/etc/shedmake/template/.gitignore"
    install -v -m644 "${SHED_CONTRIBDIR}/template/LICENSE" "${SHED_FAKEROOT}/etc/shedmake/template/LICENSE"
    install -v -m644 "${SHED_CONTRIBDIR}/shedmake.conf" "${SHED_FAKEROOT}/etc/shedmake/shedmake.default"
fi
