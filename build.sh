#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}
for SHED_PKG_LOCAL_OPTION in "${!SHED_PKG_LOCAL_OPTIONS[@]}"; do
    case "$SHED_PKG_LOCAL_OPTION" in
        release|bootstrap|toolchain)
            continue
            ;;
        *)
            SHED_PKG_LOCAL_DEVICE="$SHED_PKG_LOCAL_OPTION"
            ;;
    esac
done
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_PKG_LOCAL_DEVICE}" "${SHED_FAKE_ROOT}/tools/etc/shedmake.conf" &&
    sed -i "s/OPTIONS=.*/OPTIONS=${SHED_PKG_LOCAL_DEVICE} bootstrap !docs/g" "${SHED_FAKE_ROOT}/tools/etc/shedmake.conf"
else
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/usr/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/template/.gitignore" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/.gitignore" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/package.txt" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/package.txt" &&
    install -v -m755 "${SHED_PKG_CONTRIB_DIR}/template/build.sh" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/build.sh" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/LICENSE" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/LICENSE" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf.${SHED_PKG_LOCAL_DEVICE}" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/etc/shedmake.conf"
fi
