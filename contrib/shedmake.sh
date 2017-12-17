#!/bin/bash

# Shedmake Defaults
SHOULDSTRIP=true
CFGFILE=/etc/shedmake/shedmake.conf
export SHED_ISUPGRADE=true

# Shedmake Config
export SHED_NUMJOBS=$(sed -n 's/^NUMJOBS=//p' ${CFGFILE})
export SHED_HWCONFIG=$(sed -n 's/^HWCONFIG=//p' ${CFGFILE})

#Verify existence of directory and package metadata
export SHED_PKGDIR=$(readlink -f -n $2)
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
    if [ "${SRCFILE}" == '' ]; then
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
    find ${SHED_FAKEROOT}/{,usr/}{bin,lib,sbin} -type f -exec strip --strip-unneeded {} \;
}

shed_init () {
    # Copy template files not present in directory
    echo "Unimplemented"
}

shed_tag () {
   cd ${SHED_PKGDIR}
   git tag -f ${NAME}-${VERSION}-${REVISION}
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
        tar xf ${SRCCACHEDIR}/${SRCFILE} -C ${TMPDIR}
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
    tar -cf ${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar -C $SHED_FAKEROOT .
    rm -rf $TMPDIR
}

shed_install () {
    echo "Shedmake is preparing to install $NAME $VERSION-$REVISION..."
    export SHED_BINARCH=${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar
    # Pre-Installation
    if [ -a ${SHED_PKGDIR}/preinstall.sh ]; then
        source ${SHED_PKGDIR}/preinstall.sh
    fi
    # Installation
    if [ -a ${SHED_PKGDIR}/install.sh ]; then
        source ${SHED_PKGDIR}/install.sh
    else
        if [ -a $SHED_BINARCH ]; then
            tar xvf $SHED_BINARCH -C /
        else
            echo "Missing binary archive ${NAME}-${VERSION}-${REVISION}.tar"
            return 1
        fi
    fi
    # Post-Installation
    if [ -a ${SHED_PKGDIR}/postinstall.sh ]; then
        echo "Running post-install script for $NAME $VERSION-$REVISION..."
        source ${SHED_PKGDIR}/postinstall.sh
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
        shed_install || exit 1
        ;;
    tag)
        shed_read_package_meta || exit 1
        shed_tag
        ;;
    *)
        echo "Unrecognized command: $1"
        ;;
esac
