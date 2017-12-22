#!/bin/bash
install -v -Dm755 "${SHED_CONTRIBDIR}/shedmake.sh" "${SHED_FAKEROOT}/usr/bin/shedmake"
install -v -Dm644 "${SHED_CONTRIBDIR}/template/.gitignore" "${SHED_FAKEROOT}/etc/shedmake/template/.gitignore"
install -v -m644 "${SHED_CONTRIBDIR}/template/LICENSE" "${SHED_FAKEROOT}/etc/shedmake/template/LICENSE"
install -v -m644 "${SHED_CONTRIBDIR}/shedmake.conf" "${SHED_FAKEROOT}/etc/shedmake/shedmake.conf"
