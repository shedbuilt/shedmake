#!/bin/bash

# Shedmake Defaults
INSTALLROOT=/
SHOULDSTRIP=true
CFGFILE=/etc/shedmake/shedmake.conf

# Shedmake Config
export SHED_NUMJOBS=$(sed -n 's/^NUMJOBS=//p' ${CFGFILE})
export SHED_HWCONFIG=$(sed -n 's/^HWCONFIG=//p' ${CFGFILE})
export SHED_SYSDIR=$(sed -n 's/^SYSDIR=//p' ${CFGFILE})

shed_read_package_meta () {
    #Verify existence of directory and package metadata
    if [ -d "$1" ]; then
        export SHED_PKGDIR=$(readlink -f -n "$1")
    elif [ -d "${SHED_SYSDIR}/${1}" ]; then
        export SHED_PKGDIR="${SHED_SYSDIR}/${1}"
    else
        echo "$1 is not a package directory"
        return 1
    fi

    SRCCACHEDIR=${SHED_PKGDIR}/source
    BINCACHEDIR=${SHED_PKGDIR}/binary
    PKGMETAFILE=${SHED_PKGDIR}/package.txt
    export SHED_PATCHDIR=${SHED_PKGDIR}/patch
    export SHED_CONTRIBDIR=${SHED_PKGDIR}/contrib

    if [ ! -r ${PKGMETAFILE} ]; then
        echo "Cannot read from package.txt in package directory $SHED_PKGDIR"
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
    REPOREF=$(sed -n 's/^REF=//p' ${PKGMETAFILE})
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

shed_run_chroot_script () {
    chroot "$1" /usr/bin/env -i \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='\u:\w\$ '              \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin \
    SHED_HWCONFIG="$SHED_HWCONFIG" \
    SHED_PKGDIR="$2" \
    SHED_CONTRIBDIR="${2}/contrib" \
    SHED_PATCHDIR="${2}/patch" \
    /bin/bash "${2}/${3}"
}

shed_get () {
    cd "$SHED_SYSDIR"
    local REPOURL="$1"
    local REPOBRANCH="$2"
    local REPOFILE="$(basename $REPOURL)"
    local REPONAME="$(basename $REPOFILE .git)"
    if [ -d "$REPONAME" ]; then
        echo "Package repository $REPONAME is already present in $SHED_SYSDIR"
        return 1
    fi
    git submodule add -b "$REPOBRANCH" "$REPOURL" || return 1
    git submodule init || return 1
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

        if [ ${SRC: -4} == ".git" ]; then
            # Source is a git repository
            if [ ! -d "${SRCCACHEDIR}/${REPOREF}" ]; then
                cd "$SRCCACHEDIR"
                mkdir "${SRCCACHEDIR}/${REPOREF}"
                cd "${SRCCACHEDIR}/${REPOREF}"
                git init
                git fetch --depth=1 "$SRC" "$REPOREF"
                git checkout "$REPOREF"
            fi
            
            # Rely on PGP for verification

            # Copy repository files to build directory 
            cp -R "${SRCCACHEDIR}/${REPOREF}" "$TMPDIR" 
        else 
            # Source is an archive
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
            source ${SHED_PKGDIR}/preinstall.sh || return 1
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" preinstall.sh || return 1
        fi
    fi

    # Installation
    if [ -a ${SHED_PKGDIR}/install.sh ]; then
        if [ $SHED_INSTALLROOT == "/" ]; then
            source ${SHED_PKGDIR}/install.sh || return 1
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" install.sh || return 1
        fi
    else
        if [ ! -r "$SHED_BINARCH" ]; then
            # Download from the URL specified by BIN
            # Or, failing that, build it from scratch
            shed_build || return 1
        fi

        if [ -r "$SHED_BINARCH" ]; then
            tar xvhf "$SHED_BINARCH" -C "$SHED_INSTALLROOT" || return 1
        else
            echo "Unable to obtain binary archive ${NAME}-${VERSION}-${REVISION}.tar.xz"
            return 1
        fi
    fi

    # Post-Installation
    if [ -a ${SHED_PKGDIR}/postinstall.sh ]; then
        echo "Running post-install script for $NAME $VERSION-$REVISION..."
        if [ $SHED_INSTALLROOT == "/" ]; then
            source ${SHED_PKGDIR}/postinstall.sh || return 1
        else
            shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" postinstall.sh || return 1
        fi
    fi

    # Record Installation
    grep -Fxq "$NAME" "${SHED_SYSDIR}/install.lst"
    if [ $? -ne 0 ]; then
        echo "$NAME" >> "${SHED_SYSDIR}/install.lst"
    fi
}

shed_update() {
    cd "$SHED_SYSDIR"
    git pull --recurse-submodules
    git submodule update --remote
}

shed_upgrade() {
   echo "Unimplemented"
}

# Command switch
case $1 in
    get)
        TRACK=master
        if [ $# -lt 2 ]; then
            echo "Too few arguments to get. Usage: shedmake get <REPO_URL> <REPO_BRANCH>"
            exit 1
        elif [ $# -gt 2 ]; then
            TRACK="$3"
        fi
        shed_get "$2" "$TRACK" || exit 1
        ;;
    build)
        shed_read_package_meta "$2" || exit 1
        shed_build || exit 1
        ;;
    install)
        shed_read_package_meta "$2" || exit 1
        # Check for installation outside of root
        if [ $# -gt 2 ]; then
            INSTALLROOT="$3"
        fi
        shed_install "$INSTALLROOT" || exit 1
        ;;
    update)
        shed_update || exit 1
        ;;
    upgrade)
        shed_upgrade || exit 1
        ;;
    *)
        echo "Unrecognized command: $1"
        ;;
esac
