#!/bin/bash

# Shedmake Defaults
SHEDMAKEVER=0.5.7
export SHED_INSTALLROOT='/'
SHOULDSTRIP=true
DELETESOURCE=true
DELETEBINARY=true
SHOULDPREINSTALL=true
SHOULDINSTALL=true
SHOULDPOSTINSTALL=true
CFGFILE=/etc/shedmake/shedmake.conf
REQUIREROOT=false
export SHED_VERBOSE=false
export SHED_BUILDMODE=release

shed_set_binary_archive_compression () {
    case "$1" in
    ''|none)
        BINARCHEXT="tar"
        ;;
    bz2|xz)
        BINARCHEXT="tar.${1}"
        ;;
    *)
        echo "Invalid compression option: $1"
        return 1
        ;;
    esac
}

# Shedmake Config
export SHED_NUMJOBS=$(sed -n 's/^NUMJOBS=//p' ${CFGFILE})
export SHED_HWCONFIG=$(sed -n 's/^HWCONFIG=//p' ${CFGFILE})
TMPDIR=$(sed -n 's/^TMPDIR=//p' ${CFGFILE})
REPODIR=$(sed -n 's/^REPODIR=//p' ${CFGFILE})
shed_set_binary_archive_compression "$(sed -n 's/^COMPRESSION=//p' ${CFGFILE})"
read -ra REMOTEREPOS <<< $(sed -n 's/^REMOTEREPOS=//p' ${CFGFILE})
read -ra LOCALREPOS <<< $(sed -n 's/^LOCALREPOS=//p' ${CFGFILE})
export SHED_RELEASE=$(sed -n 's/^RELEASE=//p' ${CFGFILE})
export SHED_TARGET=$(sed -n 's/^TARGET=//p' ${CFGFILE})
export SHED_TOOLCHAIN_TARGET=$(sed -n 's/^TOOLCHAIN_TARGET=//p' ${CFGFILE})
if [ "$(sed -n 's/^KEEPSRC=//p' ${CFGFILE})" == 'yes' ]; then
    DELETESOURCE=false
fi
if [ "$(sed -n 's/^KEEPBIN=//p' ${CFGFILE})" == 'yes' ]; then
    DELETEBINARY=false
fi

shed_parse_yes_no () {
    case "$1" in
        yes) echo 'true';;
        no) echo 'false';;
        *) return 1;;
    esac
}

shed_parse_args () {
    local OPTION
    local OPTVAL
    while (( $# )); do
        OPTION="$1"
        shift
        # Check for unary options
        case "$OPTION" in
            -v|--verbose)
                SHED_VERBOSE=true
                continue
                ;;
            -k|--skip-preinstall)
                SHOULDPREINSTALL=false
                continue
                ;;
            -K|--skip-postinstall)
                SHOULDPOSTINSTALL=false
                continue
                ;;
            -I|--skip-install)
                SHOULDINSTALL=false
                continue
                ;;
            *)
                # Option is binary
                if [ $# -gt 0 ]; then
                    OPTVAL="$1"
                    shift
                else
                    echo "Missing argument to option: '$OPTION'"
                    return 1
                fi
                ;;    
        esac
        
        case "$OPTION" in
            -c|--compression)
                shed_set_binary_archive_compression "$OPTVAL" || return 1
                ;;
            -i|--install-root)
                SHED_INSTALLROOT="$OPTVAL"
                ;;
            -j|--jobs)
                SHED_NUMJOBS="$OPTVAL"
                ;;
            -m|--mode)
                SHED_BUILDMODE="$OPTVAL"
                ;;
            -h|--hwconfig)
                SHED_HWCONFIG="$OPTVAL"
                ;;
            -s|--strip)
                OPTVAL=$(shed_parse_yes_no "$OPTVAL")
                if [ $? -eq 0 ]; then
                    SHOULDSTRIP=$OPTVAL
                else
                    echo "Invalid argument for '$OPTION' Please specify 'yes' or 'no'"
                    return 1
                fi
                ;;
            -t|--target)
                SHED_TARGET="$OPTVAL"
                ;;
            -T|--toolchain-target)
                SHED_TOOLCHAIN_TARGET="$OPTVAL"
                ;;
            *)
                echo "Unknown option: '$OPTION'"
                return 1
                ;;
        esac    
    done
}

shed_binary_archive_name () {
    echo "${NAME}-${VERSION}-${SHED_RELEASE}-${REVISION}-${SHED_BUILDMODE}.${BINARCHEXT}"
}

shed_locate_package () {
    #Verify existence of directory and package metadata
    local COULDBEPATH="$2"
    local PKGDIR

    if $COULDBEPATH && [ -d "$1" ]; then
        PKGDIR=$(readlink -f -n "$1")
    else
        local REPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        local REPO
        cd "$REPODIR"
        for REPO in "${REPOS[@]}"; do
            if [ ! -d "$REPO" ]; then
                continue
            elif [ -d "${REPO}/${1}" ]; then
                PKGDIR=$(readlink -f -n "${REPO}/${1}")
                break
            fi
        done
    fi

    if [ "$PKGDIR" == '' ]; then
        return 1
    else
        echo $PKGDIR
    fi
}

shed_read_package_meta () {
    export SHED_PKGDIR=$(shed_locate_package "$1" 'true')
    if [ -z "$SHED_PKGDIR" ]; then
        echo "$1 is not a package directory"
        return 1
    fi                    
    
    if [[ $SHED_PKGDIR =~ ^$REPODIR ]]; then
        # Actions on packages in managed repositories require root privileges
        REQUIREROOT=true
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
    read -ra BUILDDEPS <<< $(sed -n 's/^BUILDDEPS=//p' ${PKGMETAFILE})
    read -ra INSTALLDEPS <<< $(sed -n 's/^INSTALLDEPS=//p' ${PKGMETAFILE})
    read -ra RUNDEPS <<< $(sed -n 's/^RUNDEPS=//p' ${PKGMETAFILE})
    export SHED_PKGINSTALLED=false
    if [ -e "${SHED_LOGDIR}/installed" ]; then
        SHED_PKGINSTALLED=true
    fi

    if [ -z "$NAME" ] || [ -z "$VERSION" ] || [ -z "$REVISION" ]; then
        echo "Required fields missing from package metadata."
        return 1
    fi
}

shed_read_package_ver () {
    if [ -e "${1}/install/installed" ]; then
        tail "${1}/install/installed"
    else
        return 1
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
    SHED_BUILDMODE="$SHED_BUILDMODE" \
    SHED_TARGET="$SHED_TARGET" \
    SHED_INSTALLROOT='/' \
    SHED_INSTALLLOG="${2}/install/${VERSION}-${REVISION}.log" \
    bash "${2}/${3}"
}

shed_add () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to track a new package repository."
        return 1
    fi

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

shed_fetch_source () {
   if [ -n "$SRC" ]; then
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
                git fetch --depth=1 "$SRC" "$REPOREF" || return 1
                git checkout "$REPOREF" || return 1
            fi
            
            # TODO: Use signature for verification
        else 
            # Source is an archive
            if [ ! -r ${SRCCACHEDIR}/${SRCFILE} ]; then
                shed_download_source
                if [ $? -ne 0 ]; then
                    echo "Unable to locate source archive ${SRCFILE}"
                    return 1
                fi
            fi

            # Verify Source Archive MD5
            shed_verify_source
            if [ $? -ne 0 ]; then
                echo "Source archive ${SRCFILE} does not match expected checksum"
                return 1
            fi
        fi
    fi
}

shed_build () {
    
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to build this package."
        return 1
    fi

    # Dependency resolution
    local DEP
    for DEP in "${BUILDDEPS[@]}"; do
        echo "Searching for build dependency '$DEP'..."
        local DEPPKGLOC
        DEPPKGLOC=$(shed_locate_package "$DEP" "false")
        if [ $? -ne 0 ]; then
            echo "Build dependency '${DEP}' is not present in a managed package repository"
            return 1
        fi
        echo "Checking installed version at ${DEPPKGLOC}..."
        if ! shed_read_package_ver "$DEPPKGLOC"; then
            echo "Package for dependency '${DEP}' is present but not installed"
            return 1
        fi
    done
    
    WORKDIR="${TMPDIR%/}/${NAME}"
    rm -rf "$WORKDIR"
    mkdir "$WORKDIR"
    export SHED_FAKEROOT="${WORKDIR}/fakeroot"
    echo "Shedmake is preparing to build $NAME $VERSION-$REVISION..."

    # Source acquisition and unpacking
    shed_fetch_source || return 1
    if [ -n "$SRC" ]; then
        if [ "${SRC: -4}" == ".git" ]; then
            # Source is a git repository
            # Copy repository files to build directory 
            cp -R "${SRCCACHEDIR}/${REPOREF}" "$WORKDIR" 
        else 
            # Source is an archive or other file
            # Unarchive Source
            tar xf "${SRCCACHEDIR}/${SRCFILE}" -C "$WORKDIR" || \
                cp "${SRCCACHEDIR}/${SRCFILE}" "$WORKDIR"
        fi
    fi
    
    # Determine Source Root Dir
    cd "$WORKDIR"
    SRCDIR=$(ls -d */)
    if [ $? -eq 0 ]; then
        if [ -d "$SRCDIR" ]; then
            export SHED_SRCDIR="${WORKDIR}/${SRCDIR}"
            cd "$SRCDIR"
        else
            export SHED_SRCDIR="$WORKDIR"
        fi
    else
        export SHED_SRCDIR="$WORKDIR"
    fi

    # Build Source
    mkdir "${SHED_FAKEROOT}"
    if [ -a "${SHED_PKGDIR}/build.sh" ]; then
        bash "${SHED_PKGDIR}/build.sh"
    else
        echo "Missing build script for $NAME $VERSION-$REVISION"
        return 1
    fi

    if [ $? -ne 0 ]; then
        echo "Failed to build $NAME $VERSION-$REVISION"
        rm -rf "$WORKDIR"
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
    tar -caf "${BINCACHEDIR}/$(shed_binary_archive_name)" -C "$SHED_FAKEROOT" .
    rm -rf "$WORKDIR"

    # Clean Up
    if $DELETESOURCE && [ -n "$SRC" ]; then
        if [ "${SRC: -4}" == ".git" ]; then
            rm -rf "${SRCCACHEDIR}/${REPOREF}"
        else
            rm "${SRCCACHEDIR}/${SRCFILE}"
        fi
    fi

    echo "Successfully built $NAME $VERSION-$REVISION"
}

shed_install () {
    
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to install this package."
        return 1
    fi

    echo "Shedmake is preparing to install $NAME $VERSION-$REVISION to ${SHED_INSTALLROOT}..."
    BINARCHIVE="${BINCACHEDIR}/$(shed_binary_archive_name)"
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')

    if [ ! -d "${SHED_LOGDIR}" ]; then
        mkdir "${SHED_LOGDIR}"
    fi
    
    # Pre-Installation
    if [ -a "${SHED_PKGDIR}/preinstall.sh" ]; then
        if $SHOULDPREINSTALL; then
            if [ $SHED_INSTALLROOT == '/' ]; then
                bash "${SHED_PKGDIR}/preinstall.sh" || return 1
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" preinstall.sh || return 1
            fi
        else
            echo "Skipping the pre-install phase."
        fi
    fi
    
    # Installation
    if $SHOULDINSTALL; then
        if [ -a "${SHED_PKGDIR}/install.sh" ]; then
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                bash "${SHED_PKGDIR}/install.sh" || return 1
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" install.sh || return 1
            fi
        else
            if [ ! -r "$BINARCHIVE" ]; then
                # TODO: Download from the URL specified by BIN
                # Or, failing that, build it from scratch
                shed_build || return 1
            fi

            if [ -r "$BINARCHIVE" ]; then
                echo "Installing files from binary archive ${NAME}-${VERSION}-${SHED_RELEASE}-${REVISION}-${SHED_BUILDMODE}.tar.xz..."
                tar xvhf "$BINARCHIVE" -C "$SHED_INSTALLROOT" > "$SHED_INSTALLLOG" || return 1
            else
                echo "Unable to obtain binary archive ${NAME}-${VERSION}-${SHED_RELEASE}-${REVISION}-${SHED_BUILDMODE}.tar.xz"
                return 1
            fi
        fi
    else
        echo "Skipping the install phase."
    fi

    # Post-Installation
    if [ -a "${SHED_PKGDIR}/postinstall.sh" ]; then
        if $SHOULDPOSTINSTALL; then
            echo "Running post-install script for $NAME $VERSION-$REVISION..."
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                bash "${SHED_PKGDIR}/postinstall.sh" || return 1
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" postinstall.sh || return 1
            fi
        else
            echo "Skipping the post-install phase."
        fi
    fi
    
    # Record Installation
    echo "${VERSION}-${REVISION}" > "${SHED_LOGDIR}/installed"

    # Clean Up
    if $DELETEBINARY ; then
        rm "$BINARCHIVE"
    fi

    echo "Successfully installed $NAME $VERSION-$REVISION"
}

shed_string_in_array () {
    local -n HAYSTACK=$1
    local NEEDLE="$2"
    local ELEMENT
    for ELEMENT in "${HAYSTACK[@]}"; do
        if [ "$ELEMENT" == "$NEEDLE" ]; then
            return 0
        fi
    done
    return 1
}

shed_update_repo () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to update managed repositories."
        return 1
    fi
                    
    local REPO="$1"
    local TYPE
    if shed_string_in_array REMOTEREPOS $REPO; then
        TYPE='remote'
    elif shed_string_in_array LOCALREPOS $REPO; then
        TYPE='local'
    fi
    if [ "$TYPE" == '' ]; then
        echo "Could not find '$REPO' among managed remote and local package repositories."
        return 1
    fi
    cd "$REPODIR"
    if [ ! -d "$REPO" ]; then
        echo "Could not find folder for $TYPE managed repository '$REPO'."
        return 1
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
}

shed_update_repos () {
    local -n REPOS=$1
    for REPO in "${REPOS[@]}"; do
        shed_update_repo "$REPO" || return 1
    done
}

shed_clean () {
   shed_read_package_meta "$1" || return 1
   if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
       echo "Root privileges are required to clean this package."
       return 1
   fi
   echo "Cleaning package '$NAME'..."
   rm -rf "$SRCCACHEDIR"
   rm -rf "$BINCACHEDIR"
}

shed_clean_repos () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to clean managed repositories."
        return 1
    fi
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
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
            echo "Root privileges are required to upgrade this package."
            return 1
    fi
    if $SHED_PKGINSTALLED; then
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

shed_upgrade_repo () {
    local REPO=$1
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to upgrade packages in managed repositories."
        return 1
    fi
    cd "$REPODIR"
    if [ ! -d "$REPO" ]; then
        echo "Could not find folder for managed repository '$REPO'."
        return 1
    fi
    cd "$REPO"
    local PACKAGE
    for PACKAGE in *; do
        if [ ! -d "$PACKAGE" ]; then
            continue
        fi
        shed_upgrade "${REPODIR}/${REPO}/${PACKAGE}" || return 1
    done
}

shed_upgrade_repos () {
    local -n REPOS=$1
    local REPO
    for REPO in "${REPOS[@]}"; do
        shed_upgrade_repo "$REPO" || return 1
    done
}

# Command switch
if [ $# -gt 0 ]; then
    SHEDCMD=$1
    shift
else
    SHEDCMD=version
fi

case $SHEDCMD in
    add)
        TRACK="$SHED_RELEASE"
        if [ $# -lt 1 ]; then
            echo "Too few arguments to 'add'. Usage: shedmake add <REPO_URL> <REPO_BRANCH>"
            exit 1
        elif [ $# -gt 1 ]; then
            TRACK="$2"
        fi
        shed_add "$1" "$TRACK" || exit 1
        ;;
    build)
        shed_read_package_meta "$1" && \
        shift && \
        shed_parse_args "$@" && \
        shed_build
        ;;
    clean)
        shed_clean "$1"
        ;;
    clean-repo)
        REPOSTOCLEAN=("$1")
        shed_clean_repos REPOSTOCLEAN
        ;;
    clean-all)
        REPOSTOCLEAN=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        shed_clean_repos REPOSTOCLEAN
        ;;
    fetch-source)
        shed_read_package_meta "$1" && \
        shed_fetch_source
        ;;
    install)
        shed_read_package_meta "$1" && \
        shift && \
        shed_parse_args "$@" && \
        shed_install
        ;;
    update-repo)
        shed_update_repo "$1"
        ;;
    update-all)
        REPOSTOUPDATE=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        shed_update_repos REPOSTOUPDATE
        ;;
    upgrade)
        shed_upgrade "$1"
        ;;
    upgrade-repo)
        shed_upgrade_repo "$1"
        ;;
    upgrade-all)
        REPOSTOUPGRADE=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
        shed_upgrade_repos REPOSTOUPGRADE
        ;;
    version)
        echo "Shedmake v${SHEDMAKEVER} - A trivial package management tool for Shedbuilt GNU/Linux"
        ;;
    *)
        echo "Unrecognized command: $1"
        ;;
esac
