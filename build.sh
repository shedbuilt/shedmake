#!/bin/bash
declare -A SHED_PKG_LOCAL_OPTIONS=${SHED_PKG_OPTIONS_ASSOC}

# Configure
for SHED_PKG_LOCAL_OPTION in "${!SHED_PKG_LOCAL_OPTIONS[@]}"; do
    case "$SHED_PKG_LOCAL_OPTION" in
        release|bootstrap|toolchain)
            SHED_PKG_LOCAL_BUILDMODE="$SHED_PKG_LOCAL_OPTION"
            ;;
        *)
            SHED_PKG_LOCAL_DEVICE="$SHED_PKG_LOCAL_OPTION"
            case "$SHED_PKG_LOCAL_DEVICE" in
                allh5cc|nanopik1plus|nanopineo2|nanopineoplus2|orangepipc2)
                    SHED_PKG_LOCAL_CPU_CORE='cortex-a53'
                    SHED_PKG_LOCAL_CPU_FEATURES='crypto'
                    SHED_PKG_LOCAL_NATIVE_TARGET='aarch64-unknown-linux-gnu'
                    ;;
                allh3cc|nanopineo|nanopim1plus|orangepione|orangepipc|orangepilite)
                    SHED_PKG_LOCAL_CPU_CORE='cortex-a7'
                    SHED_PKG_LOCAL_CPU_FEATURES='neon-vfpv4'
                    SHED_PKG_LOCAL_NATIVE_TARGET='armv7l-unknown-linux-gnueabihf'
                    ;;
            esac
            ;;
    esac
done

# Install
if [ -n "${SHED_PKG_LOCAL_OPTIONS[toolchain]}" ]; then
    SHED_PKG_LOCAL_INSTALLED_CONFIG="${SHED_FAKE_ROOT}/tools/etc/shedmake.conf"
    SHED_PKG_LOCAL_CONFIG_OPTIONS="${SHED_PKG_LOCAL_DEVICE} bootstrap !docs"
    SHED_PKG_LOCAL_IMPLICIT_BUILDDEPS=''
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/#!\/bin\/bash/#!\/tools\/bin\/bash/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    sed -i "s/CFGFILE=.*/CFGFILE=\/tools\/etc\/shedmake.conf/g" "${SHED_FAKE_ROOT}/tools/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf" "$SHED_PKG_LOCAL_INSTALLED_CONFIG" || exit 1
else
    SHED_PKG_LOCAL_INSTALLED_CONFIG="${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/etc/shedmake.conf"
    SHED_PKG_LOCAL_CONFIG_OPTIONS="${SHED_PKG_LOCAL_DEVICE} ${SHED_PKG_LOCAL_BUILDMODE} docs"
    SHED_PKG_LOCAL_IMPLICIT_BUILDDEPS='binutils gcc m4 ncurses bash bison bzip2 coreutils diffutils file findutils gawk gettext grep gzip make patch perl sed tar texinfo util-linux xz autoconf automake'
    install -v -Dm755 "${SHED_PKG_CONTRIB_DIR}/shedmake.sh" "${SHED_FAKE_ROOT}/usr/bin/shedmake" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/template/.gitignore" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/.gitignore" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/package.txt" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/package.txt" &&
    install -v -m755 "${SHED_PKG_CONTRIB_DIR}/template/build.sh" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/build.sh" &&
    install -v -m644 "${SHED_PKG_CONTRIB_DIR}/template/LICENSE" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/var/shedmake/template/LICENSE" &&
    install -v -Dm644 "${SHED_PKG_CONTRIB_DIR}/shedmake.conf" "${SHED_FAKE_ROOT}${SHED_PKG_DEFAULTS_INSTALL_DIR}/etc/shedmake.conf" || exit 1
fi

# Process the default config file
sed -i "s/CPU_CORE=.*/CPU_CORE=${SHED_PKG_LOCAL_CPU_CORE}/" "$SHED_PKG_LOCAL_INSTALLED_CONFIG" &&
sed -i "s/CPU_FEATURES=.*/CPU_FEATURES=${SHED_PKG_LOCAL_CPU_FEATURES}/" "$SHED_PKG_LOCAL_INSTALLED_CONFIG" &&
sed -i "s/NATIVE_TARGET=.*/NATIVE_TARGET=${SHED_PKG_LOCAL_NATIVE_TARGET}/" "$SHED_PKG_LOCAL_INSTALLED_CONFIG" &&
sed -i "s/OPTIONS=.*/OPTIONS=${SHED_PKG_LOCAL_CONFIG_OPTIONS}/" "$SHED_PKG_LOCAL_INSTALLED_CONFIG"
sed -i "s/IMPLICIT_BUILDDEPS=.*/IMPLICIT_BUILDDEPS=${SHED_PKG_LOCAL_IMPLICIT_BUILDDEPS}/" "$SHED_PKG_LOCAL_INSTALLED_CONFIG"
