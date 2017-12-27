#!/bin/bash

# Shedmake Defaults
INSTALLROOT=/
SHOULDSTRIP=true
DELETESOURCE=true
DELETEBINARY=true
CFGFILE=/etc/shedmake/shedmake.conf

# Shedmake Config
export SHED_NUMJOBS=$(sed -n 's/^NUMJOBS=//p' ${CFGFILE})
export SHED_HWCONFIG=$(sed -n 's/^HWCONFIG=//p' ${CFGFILE})
REPODIR=$(sed -n 's/^REPODIR=//p' ${CFGFILE})
read -ra REMOTEREPOS <<< $(sed -n 's/^REMOTEREPOS=//p' ${CFGFILE})
read -ra LOCALREPOS <<< $(sed -n 's/^LOCALREPOS=//p' ${CFGFILE})
export SHED_RELEASE=$(sed -n 's/^RELEASE=//p' ${CFGFILE})
if [ "$(sed -n 's/^KEEPSRC=//p' ${CFGFILE})" == 'yes' ]; then
    DELETESOURCE=false
fi
if [ "$(sed -n 's/^KEEPBIN=//p' ${CFGFILE})" == 'yes' ]; then
    DELETEBINARY=false
fi

shed_read_package_meta () {
    #Verify existence of directory and package metadata
    unset SHED_PKGDIR
    if [ -d "$1" ]; then
        export SHED_PKGDIR=$(readlink -f -n "$1")
    else
        local REPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        local REPO
        cd "$REPODIR"
        for REPO in "${REPOS[@]}"; do
            if [ ! -d "$REPO" ]; then
                continue
            elif [ -d "${REPO}/${1}" ]; then
                export SHED_PKGDIR=$(readlink -f -n "${REPO}/${1}")
                break
            fi
        done
    fi

    if [ "$SHED_PKGDIR" == '' ]; then
        echo "$1 is not a package directory"
        return 1
    fi

    SRCCACHEDIR="${SHED_PKGDIR}/source"
    BINCACHEDIR="${SHED_PKGDIR}/binary"
    PKGMETAFILE="${SHED_PKGDIR}/package.txt"
    export SHED_PATCHDIR="${SHED_PKGDIR}/patch"
    export SHED_CONTRIBDIR="${SHED_PKGDIR}/contrib"
    export SHED_LOGDIR="${SHED_PKGDIR}/install"

    if [ ! -r ${PKGMETAFILE} ]; then
        echo "Cannot read from package.txt in package directory $SHED_PKGDIR"
        return 1
    fi

    # Package Metadata
    NAME=$(sed -n 's/^NAME=//p' ${PKGMETAFILE})
    VERSION=$(sed -n 's/^VERSION=//p' ${PKGMETAFILE})
    REVISION=$(sed -n 's/^REVISION=//p' ${PKGMETAFILE})
    export SHED_INSTALLLOG="${SHED_LOGDIR}/${VERSION}-${REVISION}.log"
    SRC=$(sed -n 's/^SRC=//p' ${PKGMETAFILE})
    SRCFILE=$(sed -n 's/^SRCFILE=//p' ${PKGMETAFILE})
    if [ "${SRCFILE}" == '' -a "$SRC" != '' ]; then
        SRCFILE="$(basename ${SRC})"
    fi
    REPOREF=$(sed -n 's/^REF=//p' ${PKGMETAFILE})
    SRCMD5=$(sed -n 's/^SRCMD5=//p' ${PKGMETAFILE})
    if [ "$(sed -n 's/^STRIP=//p' ${PKGMETAFILE})" == 'no' ]; then
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
    SHED_LOGDIR="${2}/install" \
    SHED_RELEASE="$SHED_RELEASE" \
    SHED_INSTALLLOG="${2}/install/${VERSION}-${REVISION}.log" \
    /bin/bash "${2}/${3}"
}

shed_get () {
    local REPOURL="$1"
    local REPOBRANCH="$2"
    local REPOFILE="$(basename $REPOURL)"
    local REPONAME="$(basename $REPOFILE .git)"
    cd "$REPODIR"
    local REPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
    local REPO
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "$REPO" ]; then
            continue
        elif [ -d "${REPO}/${REPONAME}" ]; then
            echo "Package '$REPONAME' is already present in '$REPO' package repository."
            return 1
        fi
    done
    cd "${LOCALREPOS[0]}"
    git submodule add -b "$REPOBRANCH" "$REPOURL" || return 1
    git submodule init || return 1

    echo "Added '$REPONAME' to '${LOCALREPOS[0]}' package repository."
}

shed_build () {
    TMPDIR=/var/tmp/${NAME}-${VERSION}-${REVISION}
    rm -rf "$TMPDIR"
    mkdir "$TMPDIR"
    export SHED_FAKEROOT=${TMPDIR}/fakeroot
    echo "Shedmake is preparing to build $NAME $VERSION-$REVISION..."

    if [ "$SRC" != '' ]; then
        if [ ! -d "${SRCCACHEDIR}" ]; then
            mkdir "${SRCCACHEDIR}"
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

            # Clean Up
            if $DELETESOURCE ; then
                rm -rf "${SRCCACHEDIR}/${REPOREF}"
            fi
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

            # Clean Up
            if $DELETESOURCE ; then
                rm "${SRCCACHEDIR}/${SRCFILE}"
            fi
        fi
    fi
    
    # Determine Source Root Dir
    cd "$TMPDIR"
    SRCDIR=$(ls -d */)
    if [ $? -eq 0 ]; then
        if [ -d "${SRCDIR}" ]; then
            export SHED_SRCDIR="${TMPDIR}/${SRCDIR}"
            cd "${SRCDIR}"
        else
            export SHED_SRCDIR="${TMPDIR}"
        fi
    else
        export SHED_SRCDIR="${TMPDIR}"
    fi

    # Build Source
    mkdir "${SHED_FAKEROOT}"
    if [ -a "${SHED_PKGDIR}/build.sh" ]; then
        source "${SHED_PKGDIR}/build.sh"
    else
        echo "Missing build script for $NAME $VERSION-$REVISION"
        return 1
    fi

    if [ ! -d "${BINCACHEDIR}" ]; then
        mkdir "${BINCACHEDIR}"
    fi
    
    # Strip Binaries
    if $SHOULDSTRIP ; then
        shed_strip_binaries
    fi

    # Archive Build Product
    tar -cJf "${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar.xz" -C "$SHED_FAKEROOT" .
    rm -rf $TMPDIR

    echo "Successfully built $NAME $VERSION-$REVISION"
}

shed_install () {
    if [[ $EUID -ne 0 ]]; then
       echo "Installation must be performed as the root user." 
       return 1
    fi
    export SHED_INSTALLROOT="$1"
    echo "Shedmake is preparing to install $NAME $VERSION-$REVISION to ${SHED_INSTALLROOT}..."
    export SHED_BINARCH=${BINCACHEDIR}/${NAME}-${VERSION}-${REVISION}.tar.xz
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')

    if [ ! -d "${SHED_LOGDIR}" ]; then
        mkdir "${SHED_LOGDIR}"
    fi
    
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
            echo "Installing files from binary archive ${NAME}-${VERSION}-${REVISION}.tar.xz..."
            tar xvhf "$SHED_BINARCH" -C "$SHED_INSTALLROOT" > "$SHED_INSTALLLOG" || return 1
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
    echo "${VERSION}-${REVISION}" > "${SHED_LOGDIR}/installed"

    # Clean Up
    if $DELETEBINARY ; then
        rm "$SHED_BINARCH"
    fi

    echo "Successfully installed $NAME $VERSION-$REVISION"
}

shed_update_repos () {
    local -n REPOS=$1
    local TYPE="$2"
    local REPO
    cd "$REPODIR"
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "$REPO" ]; then
            continue
        fi
        cd "$REPO"
        echo "Updating $TYPE repository '$REPO'..."
        if [ $TYPE == 'local' ]; then
            git submodule update --remote
            # This cannot be enabled until git is configured for the root user
            # git commit -a -m "Updating to the latest package revisions"
        elif [ $TYPE == 'remote' ]; then
            git pull
            git submodule update
        fi
        cd ..
    done
}

shed_clean () {
   shed_read_package_meta "$1" || return 1
   echo "Cleaning package '$NAME'..."
   rm -rf "$SRCCACHEDIR"
   rm -rf "$BINCACHEDIR"
}

shed_clean_repos () {
    local -n REPOS=$1
    local REPO
    local PACKAGE
    cd "$REPODIR"
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "$REPO" ]; then
            continue
        fi
        cd "$REPO"
        echo "Cleaning packages in '$REPO' repository..."
        for PACKAGE in *; do
            if [ ! -d "$PACKAGE" ]; then
                continue
            fi
            shed_clean "${REPODIR}/${REPO}/${PACKAGE}"
        done
        cd ..
    done
}

shed_upgrade () {
    shed_read_package_meta "$1" || return 1
    if [ -e "${SHED_LOGDIR}/installed" ]; then
        grep -Fxq "${VERSION}-${REVISION}" "${SHED_LOGDIR}/installed"
        if [ $? -eq 0 ]; then
            echo "Package ${NAME} is already up-to-date (${VERSION}-${REVISION})"
            return 0
        fi
    else
        echo "Package ${NAME} is not installed"
        return 1
    fi
    shed_install "$INSTALLROOT" || return 1
}

shed_upgrade_repos () {
    local -n REPOS=$1
    local REPO
    local PACKAGE
    cd "$REPODIR"
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "$REPO" ]; then
            continue
        fi
        cd "$REPO"
        for PACKAGE in *; do
            if [ ! -d "$PACKAGE" ]; then
                continue
            fi
            shed_upgrade "${REPODIR}/${REPO}/${PACKAGE}"
        done
        cd ..
    done
}

# Command switch
case $1 in
    get)
        TRACK="$SHED_RELEASE"
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
    clean)
        shed_clean "$2" || exit 1
        ;;
    clean-repo)
        REPOSTOCLEAN=("$2")
        shed_clean_repos REPOSTOCLEAN || exit 1
        ;;
    clean-all)
        REPOSTOCLEAN=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        shed_clean_repos REPOSTOCLEAN || exit 1
        ;;
    install)
        shed_read_package_meta "$2" || exit 1
        # Check for installation outside of root
        if [ $# -gt 2 ]; then
            INSTALLROOT="$3"
        fi
        shed_install "$INSTALLROOT" || exit 1
        ;;
    update-local)
        shed_update_repos LOCALREPOS local || exit 1
        ;;
    update-remote)
        shed_update_repos REMOTEREPOS remote || exit 1
        ;;
    update-all)
        shed_update_repos REMOTEREPOS remote || exit 1
        shed_update_repos LOCALREPOS local || exit 1
        ;;
    upgrade)
        shed_upgrade "$2" || exit 1
        ;;
    upgrade-local)
        shed_upgrade_repos LOCALREPOS || exit 1
        ;;
    upgrade-remote)
        shed_upgrade_repos REMOTEREPOS || exit 1
        ;;
    upgrade-all)
        shed_upgrade_repos REMOTEREPOS || exit 1
        shed_upgrade_repos LOCALREPOS || exit 1
        ;;
    *)
        echo "Unrecognized command: $1"
        ;;
esac
