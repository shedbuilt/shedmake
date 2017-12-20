#!/bin/bash

# Shedmake Defaults
INSTALLROOT=/
SHOULDSTRIP=true
CFGFILE=/etc/shedmake/shedmake.conf

# Shedmake Config
export SHED_NUMJOBS=$(sed -n 's/^NUMJOBS=//p' ${CFGFILE})
export SHED_HWCONFIG=$(sed -n 's/^HWCONFIG=//p' ${CFGFILE})
export SHED_SYSDIR=$(sed -n 's/^SYSDIR=//p' ${CFGFILE})

#Verify existence of directory and package metadata
export SHED_PKGDIR=$(readlink -f -n "$2")
if [ ! -d ${SHED_PKGDIR} ]; then
    echo "$2 is not a package directory"
    exit 1
fi
SRCCACHEDIR=${SHED_PKGDIR}/source
BINCACHEDIR=${SHED_PKGDIR}/binary
PKGMETAFILE=${SHED_PKGDIR}/package.txt
export SHED_PATCHDIR=${SHED_PKGDIR}/patch
export SHED_CONTRIBDIR=${SHED_PKGDIR}/contrib

shed_read_package_meta () {
    if [ ! -r ${PKGMETAFILE} ]; then
        echo "Cannot read from package.txt in package directory $2"
        return 1
    fi

    # Package Metadata
    NAME=$(sed -n 's/^NAME=//p' ${PKGMETAFILE})
    VERSION=$(sed -n 's/^VERSION=//p' ${PKGMETAFILE})
    REVISION=$(sed -n 's/^REVISION=//p' ${PKGMETAFILE})
    SRC=$(sed -n 's/^SRC=//p' ${PKGMETAFILE})
    SRCFILE=$(sed -n 's/^SRCFILE=//p' ${PKGMETAFILE})
    if [ "${SRCFILE}" == '' -a "$SRC" != '' ]; then
        SRCFILE="$(basename ${SRC})"
    fi
    SRCMD5=$(sed -n 's/^SRCMD5=//p' ${PKGMETAFILE})
    STRIP=$(sed -n 's/^STRIP=//p' ${PKGMETAFILE})
    if [ "$STRIP" == 'yes' ]; then
        SHOULDSTRIP=true
    elif [ "$STRIP" == 'no' ]; then
        SHOULDSTRIP=false
    fi
}

shed_download_source () {
    cd ${SRCCACHEDIR}
    wget -O ${SRCFILE} ${SRC}
    if [ ! -r ${SRCCACHEDIR}/${SRCFILE} ]; then
        return 1
    fi
    return 0                                                            
}

shed_verify_source () {
    if [ "$(md5sum ${SRCCACHEDIR}/${SRCFILE} | awk '{print $1}')" != "$SRCMD5" ]; then
        return 1
    fi
    return 0
}

shed_strip_binaries () {
    # Strip all binaries and libraries, except explicitly created .dbg symbol files
    find "${SHED_FAKEROOT}/usr/lib" -type f -name \*.a \
        -exec strip --strip-debug {} ';'
    find "${SHED_FAKEROOT}/lib" "${SHED_FAKEROOT}/usr/lib" -type f \( -name \*.so* -a ! -name \*dbg \) \
        -exec strip --strip-unneeded {} ';'
    find ${SHED_FAKEROOT}/{bin,sbin} ${SHED_FAKEROOT}/usr/{bin,sbin,libexec} -type f \
         -exec strip --strip-all {} ';'
}

shed_init () {
    # Copy template files not present in directory
    echo "Unimplemented"
}

shed_tag () {
   cd ${SHED_PKGDIR}
   git tag -f ${NAME}-${VERSION}-${REVISION}
}

shed_run_chroot_script () {
    chroot "$1" /usr/bin/env -i \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='\u:\w\$ '              \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin \
    /bin/bash "$2"
}

shed_build () {
    TMPDIR=/var/tmp/${NAME}-${VERSION}-${REVISION}
    rm -rf "$TMPDIR"
    mkdir "$TMPDIR"    
    export SHED_FAKEROOT=${TMPDIR}/fakeroot
    echo "Shedmake is preparing to build $NAME $VERSION-$REVISION..."

    if [ "$SRC" != '' ]; then
        if [ ! -d ${SRCCACHEDIR} ]; then
            mkdir ${SRCCACHEDIR}
        fi
    
        # Source Acquisition
        if [ ! -r ${SRCCACHEDIR}/${SRCFILE} ]; then
            shed_download_source
            if [ $? -ne 0 ]; then
                echo "Unable to locate source archive ${SRCFILE}"
                exit 1
            fi
        fi

        # Verify Source Archive MD5
        shed_verify_source
        if [ $? -ne 0 ]; then
            echo "Source archive ${SRCFILE} does not match expected checksum"
            exit 1
        fi

        # Unarchive Source
        tar xf "${SRCCACHEDIR}/${SRCFILE}" -C "${TMPDIR}" || cp "${SRCCACHEDIR}/${SRCFILE}" "$TMPDIR"
    fi
    
    # Determine Source Root Dir
    cd "$TMPDIR"
    SRCDIR=$(ls -d */)
    if [ $? -eq 0 ]; then
        if [ -d ${SRCDIR} ]; then
            export SHED_SRCDIR=${TMPDIR}/${SRCDIR}
            cd ${SRCDIR}
        else
            export SHED_SRCDIR=${TMPDIR}
        fi
    else
        export SHED_SRCDIR=${TMPDIR}
    fi

    # Build Source
    mkdir ${SHED_FAKEROOT}
    if [ -a ${SHED_PKGDIR}/build.sh ]; then
        source ${SHED_PKGDIR}/build.sh
    else
        echo "Missing build script for $NAME $VERSION-$REVISION"
        return 1
    fi

    if [ ! -d ${BINCACHEDIR} ]; then
        mkdir ${BINCACHEDIR}
    fi
    
    # Strip Binaries
    if $SHOULDSTRIP ; then
        shed_strip_binaries
    fi

    # Archive Build Product
    tar -cJf ${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar.xz -C $SHED_FAKEROOT .
    rm -rf $TMPDIR
}

shed_install () {
    export SHED_INSTALLROOT="$1"
    echo "Shedmake is preparing to install $NAME $VERSION-$REVISION to ${SHED_INSTALLROOT}..."
    export SHED_BINARCH=${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar.xz
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')
    
    # Pre-Installation
    if [ -a ${SHED_PKGDIR}/preinstall.sh ]; then
        if [ $SHED_INSTALLROOT == "/" ]; then
            source ${SHED_PKGDIR}/preinstall.sh
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "${SHED_CHROOT_PKGDIR}/preinstall.sh"
        fi
    fi

    # Installation
    if [ -a ${SHED_PKGDIR}/install.sh ]; then
        if [ $SHED_INSTALLROOT == "/" ]; then
            source ${SHED_PKGDIR}/install.sh
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "${SHED_CHROOT_PKGDIR}/install.sh"
        fi
    else
        if [ ! -r "$SHED_BINARCH" ]; then
            # Download from the URL specified by BIN
            # Or, failing that, build it from scratch
            shed_build || return 1
        fi

        if [ -r "$SHED_BINARCH" ]; then
            tar xvf "$SHED_BINARCH" -C "$SHED_INSTALLROOT"
        else
            echo "Unable to obtain binary archive ${NAME}-${VERSION}-${REVISION}.tar.xz"
            return 1
        fi
    fi

    # Post-Installation
    if [ -a ${SHED_PKGDIR}/postinstall.sh ]; then
        echo "Running post-install script for $NAME $VERSION-$REVISION..."
        if [ $SHED_INSTALLROOT == "/" ]; then
            source ${SHED_PKGDIR}/postinstall.sh
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "${SHED_CHROOT_PKGDIR}/postinstall.sh"
        fi
    fi
}

# Command switch
case $1 in
    build)
        shed_read_package_meta || exit 1
        shed_build || exit 1
        ;;
    init)
        shed_init
        ;;
    install)
        shed_read_package_meta || exit 1
        # Check for installation outside of root
        if [ $# -gt 2 ]; then
            INSTALLROOT="$3"
        fi
        shed_install "$INSTALLROOT" || exit 1
        ;;
    tag)
        shed_read_package_meta || exit 1
        shed_tag
        ;;
    *)
        echo "Unrecognized command: $1"
        ;;
esac
