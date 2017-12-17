#!/bin/bash
mkdir -pv ${SHED_FAKEROOT}/usr/bin
install -v -m755 ${SHED_CONTRIBDIR}/shedmake.sh ${SHED_FAKEROOT}/usr/bin/shedmake
mkdir -pv ${SHED_FAKEROOT}/etc/shedmake/template
install -v -m644 ${SHED_CONTRIBDIR}/template/.gitignore ${SHED_FAKEROOT}/etc/shedmake/template/
install -v -m644 ${SHED_CONTRIBDIR}/template/LICENSE ${SHED_FAKEROOT}/etc/shedmake/template/
install -v -m644 ${SHED_CONTRIBDIR}/shedmake.conf ${SHED_FAKEROOT}/etc/
