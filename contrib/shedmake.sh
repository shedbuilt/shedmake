#!/bin/bash

# Shedmake: A trivial package manager for Shedbuilt GNU/Linux
# Copyright 2018 Auston Stewart

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
# associated documentation files (the "Software"), to deal in the Software without restriction, including 
# without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
# copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to 
# the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial 
# portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT 
# LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN 
# NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Shedmake Defines
SHEDMAKEVER=0.7.0
CFGFILE=/etc/shedmake.conf

shed_parse_yes_no () {
    case "$1" in
        yes) echo 'true';;
        no) echo 'false';;
        *) return 1;;
    esac
}

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

# Shedmake Config File Defaults
if [ ! -r "$CFGFILE" ]; then
    echo "Unable to read from config file: '$CFGFILE'"
    exit 1
fi
DEFAULT_NUMJOBS="$(sed -n 's/^NUMJOBS=//p' $CFGFILE)"
DEFAULT_DEVICE="$(sed -n 's/^DEVICE=//p' $CFGFILE)"
TMPDIR="$(sed -n 's/^TMPDIR=//p' $CFGFILE)"
REPODIR="$(sed -n 's/^REPODIR=//p' $CFGFILE)"
DEFAULT_COMPRESSION="$(sed -n 's/^COMPRESSION=//p' $CFGFILE)"
read -ra REMOTEREPOS <<< "$(sed -n 's/^REMOTE_REPOS=//p' $CFGFILE)"
read -ra LOCALREPOS <<< "$(sed -n 's/^LOCAL_REPOS=//p' $CFGFILE)"
export SHED_RELEASE="$(sed -n 's/^RELEASE=//p' $CFGFILE)"
export SHED_CPU_CORE="$(sed -n 's/^CPU_CORE=//p' $CFGFILE)"
export SHED_CPU_FEATURES="$(sed -n 's/^CPU_FEATURES=//p' $CFGFILE)"
export SHED_NATIVE_TARGET="$(sed -n 's/^NATIVE_TARGET=//p' $CFGFILE)"
export SHED_TOOLCHAIN_TARGET="$(sed -n 's/^TOOLCHAIN_TARGET=//p' $CFGFILE)"
DEFAULT_KEEPSOURCE=$(shed_parse_yes_no "$(sed -n 's/^KEEPSRC=//p' $CFGFILE)")
DEFAULT_KEEPBINARY=$(shed_parse_yes_no "$(sed -n 's/^KEEPBIN=//p' $CFGFILE)")
                                                                            
shed_load_defaults () {
    SHOULDSTRIP=true
    KEEPSOURCE="$DEFAULT_KEEPSOURCE"
    KEEPBINARY="$DEFAULT_KEEPBINARY"
    SHOULDPREINSTALL=true
    SHOULDINSTALL=true
    SHOULDPOSTINSTALL=true
    REQUIREROOT=false
    export SHED_VERBOSE=false
    export SHED_BUILDMODE=release
    export SHED_TARGET=native
    export SHED_HOST=native
    export SHED_INSTALLROOT='/'
    export SHED_NUMJOBS="$DEFAULT_NUMJOBS"
    export SHED_HWCONFIG="$DEFAULT_DEVICE"
    export SHED_DEVICE="$DEFAULT_DEVICE"
    shed_set_binary_archive_compression "$DEFAULT_COMPRESSION"
}

shed_parse_args () {
    PARSEDARGS=( "$@" )
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
            -h|--host)
                SHED_HOST="$OPTVAL"
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
            -d|--device)
                SHED_HWCONFIG="$OPTVAL"
                SHED_DEVICE="$OPTVAL"
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
            *)
                echo "Unknown option: '$OPTION'"
                return 1
                ;;
        esac    
    done
}

shed_binary_archive_name () {
    if [ -n "$BINFILE" ]; then
        eval echo "$BINFILE"
    else
        echo "${NAME}_${VERSION}_${REVISION}_${SHED_RELEASE}_${SHED_BUILDMODE}_${SHED_CPU_CORE}_${SHED_CPU_FEATURES}.${BINARCHEXT}"
    fi
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

    if [ -z "$PKGDIR" ]; then
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
    
    if [[ $SHED_PKGDIR =~ ^$REPODIR.* ]]; then
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
    if [ -z "$SRCFILE" ] && [ -n "$SRC" ]; then
        SRCFILE=$(basename $SRC)
    fi
    REPOREF=$(sed -n 's/^REF=//p' ${PKGMETAFILE})
    SRCMD5=$(sed -n 's/^SRCMD5=//p' ${PKGMETAFILE})
    if [ "$(sed -n 's/^STRIP=//p' ${PKGMETAFILE})" = 'no' ]; then
        SHOULDSTRIP=false
    fi
    BIN=$(sed -n 's/^BIN=//p' ${PKGMETAFILE})
    BINFILE=$(sed -n 's/^BINFILE=//p' ${PKGMETAFILE})
    if [ -z "$BINFILE" ] && [ -n "$BIN" ]; then
        BINFILE=$(basename $BIN)
    fi
    read -ra BUILDDEPS <<< $(sed -n 's/^BUILDDEPS=//p' ${PKGMETAFILE})
    read -ra INSTALLDEPS <<< $(sed -n 's/^INSTALLDEPS=//p' ${PKGMETAFILE})
    read -ra RUNDEPS <<< $(sed -n 's/^RUNDEPS=//p' ${PKGMETAFILE})
    export SHED_INSTALLED_PKGVER=''
    if [ -e "${SHED_LOGDIR}/installed" ]; then
        SHED_INSTALLED_PKGVER=$(<"${SHED_LOGDIR}/installed")
    fi
    if [ -z "$NAME" ] || [ -z "$VERSION" ] || [ -z "$REVISION" ]; then
        echo "Required fields missing from package metadata."
        return 1
    fi
}

shed_resolve_dependencies () {
    local -n DEPS=$1
    local DEPACTION=$2
    local DEPTYPE=$3
    local DEP
    echo "Resolving $DEPTYPE dependencies for '$NAME'..."
    for DEP in "${DEPS[@]}"; do
        local DEPARGS=( "$DEPACTION" "$DEP" "${PARSEDARGS[@]}" )
        shedmake "${DEPARGS[@]}"
        case "$DEPACTION" in
            install|upgrade)
                if [ $? -ne 0 ]; then
                    return 1
                fi
            ;;
            status)
                # Ensure package is installed, if not up-to-date
                if [ $? -ne 0 ] && [ $? -ne 2 ]; then
                    return 1
                fi
            ;;
        esac
    done
    # Ensure retval is 0, as shedmake status may have returned a non-zero value
    return 0
}

shed_download_source () {
    if [ ! -d "$SRCCACHEDIR" ]; then
        mkdir "$SRCCACHEDIR"
    fi
    cd "$SRCCACHEDIR"
    wget -O "$SRCFILE" "$SRC"
}

shed_download_binary () {
    if [ ! -d "$BINCACHEDIR" ]; then
        mkdir "$BINCACHEDIR"
    fi
    cd "$BINCACHEDIR"
    local BINURL=$(eval echo "$BIN")
    wget -O "$(shed_binary_archive_name)" "$BINURL"
}

shed_verify_source () {
    if [ -n "$SRCMD5" ]; then
        if [ "$(md5sum ${SRCCACHEDIR}/${SRCFILE} | awk '{print $1}')" != "$SRCMD5" ]; then
            return 1
        fi
    else
        echo 'WARNING: Skipping verification of source archive because SRCMD5 is absent from package metadata'
    fi
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
    SHED_DEVICE="$SHED_DEVICE" \
    SHED_PKGDIR="$2" \
    SHED_CONTRIBDIR="${2}/contrib" \
    SHED_PATCHDIR="${2}/patch" \
    SHED_LOGDIR="${2}/install" \
    SHED_RELEASE="$SHED_RELEASE" \
    SHED_BUILDMODE="$SHED_BUILDMODE" \
    SHED_HOST="$SHED_HOST" \
    SHED_TARGET="$SHED_TARGET" \
    SHED_NATIVE_TARGET="$SHED_NATIVE_TARGET" \
    SHED_TOOLCHAIN_TARGET="$SHED_TOOLCHAIN_TARGET" \
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
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            if [ ! -d "${SRCCACHEDIR}/${NAME}-git" ]; then
                mkdir -p "${SRCCACHEDIR}/${NAME}-git"
                cd "${SRCCACHEDIR}/${NAME}-git"
                git init
                git remote add origin "$SRC"
            else
                cd "${SRCCACHEDIR}/${NAME}-git"
            fi
            # Perform a shallow fetch of the desired refspec
            local LOCALREPOREF="$(sed -e "s/^refs\/heads\//refs\/remotes\/origin\//g" <<< $REPOREF)"
            git fetch --depth=1 origin +${REPOREF}:${LOCALREPOREF} && \
            git checkout --quiet FETCH_HEAD || return 1
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
    echo "Shedmake is preparing to build '$NAME' (${VERSION}-${REVISION})..."

    # Working directory management
    WORKDIR="${TMPDIR%/}/${NAME}"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
    export SHED_FAKEROOT="${WORKDIR}/fakeroot"

    # Source acquisition and unpacking
    shed_fetch_source || return 1
    if [ -n "$SRC" ]; then
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            # Copy repository files to build directory 
            cp -R "${SRCCACHEDIR}/${NAME}-git" "$WORKDIR" 
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
    echo "Successfully built $NAME $VERSION-$REVISION"
    
    if [ ! -d "$BINCACHEDIR" ]; then
        mkdir "$BINCACHEDIR"
    fi
    
    # Strip Binaries
    if $SHOULDSTRIP ; then
        echo 'Stripping binaries...'
        shed_strip_binaries
    fi

    # Archive Build Product
    echo -n "Creating binary archive $(shed_binary_archive_name)..."
    tar -caf "${BINCACHEDIR}/$(shed_binary_archive_name)" -C "$SHED_FAKEROOT" . || return 1
    echo 'done'
    
    # Clean Up
    cd "$TMPDIR"
    rm -rf "$WORKDIR"
    if ! $KEEPSOURCE && [ -n "$SRC" ]; then
        if [ "${SRC: -4}" = '.git' ]; then
            rm -rf "${SRCCACHEDIR}/${NAME}-git"
        else
            rm "${SRCCACHEDIR}/${SRCFILE}"
        fi
    fi
}

shed_install () {
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to install this package."
        return 1
    fi
    echo "Shedmake is preparing to install '$NAME' (${VERSION}-${REVISION}) to ${SHED_INSTALLROOT}..."

    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')
    if [ ! -d "${SHED_LOGDIR}" ]; then
        mkdir "${SHED_LOGDIR}"
    fi
    
    # Pre-Installation
    if [ -a "${SHED_PKGDIR}/preinstall.sh" ]; then
        if $SHOULDPREINSTALL; then
            if [ "$SHED_INSTALLROOT" = '/' ]; then
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
            if [ "$SHED_INSTALLROOT" = '/' ]; then
                bash "${SHED_PKGDIR}/install.sh" || return 1
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" install.sh || return 1
            fi
        else
            BINARCHIVE="${BINCACHEDIR}/$(shed_binary_archive_name)"
            if [ ! -r "$BINARCHIVE" ]; then
                if [ -n "$BIN" ]; then
                    # Download from the URL specified by BIN
                    shed_download_binary
                fi
                if [ ! -r "$BINARCHIVE" ]; then
                    # Or, failing that, build it from scratch
                    shedmake build "${SHED_PKGDIR}" "${PARSEDARGS[@]}"
                fi
            fi
            if [ -r "$BINARCHIVE" ]; then
                echo "Installing files from binary archive $(shed_binary_archive_name)..."
                tar xvhf "$BINARCHIVE" -C "$SHED_INSTALLROOT" > "$SHED_INSTALLLOG" || return 1
                echo 'done'
                if ! $KEEPBINARY; then
                    rm "$BINARCHIVE"
                fi
            else
                echo "Unable to produce or obtain binary archive: $(shed_binary_archive_name)"
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
            if [ "$SHED_INSTALLROOT" = '/' ]; then
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

    echo "Successfully installed '$NAME' (${VERSION}-${REVISION})"
}

shed_string_in_array () {
    local -n HAYSTACK=$1
    local NEEDLE="$2"
    local ELEMENT
    for ELEMENT in "${HAYSTACK[@]}"; do
        if [ "$ELEMENT" = "$NEEDLE" ]; then
            return 0
        fi
    done
    return 1
}

shed_update_repos () {
    local -n REPOS=$1
    local REPO
    local TYPE
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to update managed repositories."
        return 1
    fi               
    for REPO in "${REPOS[@]}"; do
        if shed_string_in_array REMOTEREPOS $REPO; then
            TYPE='remote'
        elif shed_string_in_array LOCALREPOS $REPO; then
            TYPE='local'
        fi
        if [ -z "$TYPE" ]; then
            echo "Could not find '$REPO' among managed remote and local package repositories."
            return 1
        fi
        if [ ! -d "${REPODIR}/${REPO}" ]; then
            echo "Could not find folder for $TYPE managed repository '$REPO'."
            return 1
        fi
        cd "${REPODIR}/${REPO}"
        echo "Updating $TYPE repository '$REPO'..."
        if [ "$TYPE" = 'local' ]; then
            git submodule update --remote
            # This cannot be enabled until git is configured for the root user
            # git commit -a -m "Updating to the latest package revisions"
        elif [ "$TYPE" = 'remote' ]; then
            git pull
            git submodule update
        fi
    done
}

shed_clean () {
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
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "${REPODIR}/${REPO}" ]; then
            continue
        fi
        echo "Cleaning packages in '$REPO' repository..."
        for PACKAGE in "${REPODIR}/${REPO}"/*; do
            if [ ! -d "$PACKAGE" ]; then
                continue
            fi
            shed_read_package_meta "$PACKAGE" && \
            shed_clean || return 1
        done
    done
}

shed_package_status () {
    # NOTE: Reserve retval 1 for packages not found in managed repositories
    if [ -n "$SHED_INSTALLED_PKGVER" ]; then
        if [ "${VERSION}-${REVISION}" == "$SHED_INSTALLED_PKGVER" ]; then
            echo "Package '$NAME' is installed and up-to-date ($SHED_INSTALLED_PKGVER)"
            return 0
        else  
            echo "Package '$NAME' ($SHED_INSTALLED_PKGVER) is installed but ${VERSION}-${REVISION} is available"
            return 2
        fi
    else
        echo "Package '$NAME' (${VERSION}-${REVISION}) is present but not installed"
        return 3
    fi
}

shed_upgrade () {
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
            echo "Root privileges are required to upgrade this package."
            return 1
    fi
    shed_package_status
    if [ $? -eq 2 ]; then
        shed_resolve_dependencies INSTALLDEPS 'upgrade' 'install' && \
        shed_install
    fi
}

shed_upgrade_repos () {
    local -n REPOS=$1
    local REPO
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to upgrade packages in managed repositories."
        return 1
    fi
    for REPO in "${REPOS[@]}"; do
        if [ ! -d "${REPODIR}/${REPO}" ]; then
            echo "Could not find folder for managed repository '$REPO'."
            return 1
        fi
        local PACKAGE
        for PACKAGE in "${REPODIR}/${REPO}"/*; do
            if [ ! -d "$PACKAGE" ]; then
                continue
            fi
            shed_read_package_meta "$PACKAGE" && \
            shed_upgrade || return 1
        done
    done
}

shed_command () {
    local SHEDCMD
    local CMDREPOS
    if [ $# -gt 0 ]; then
        SHEDCMD=$1; shift
    else
        SHEDCMD=version
    fi

    case "$SHEDCMD" in
        add|add-list)
            local TRACK="$SHED_RELEASE"
            if [ $# -lt 1 ]; then
                echo "Too few arguments to 'add'. Usage: shedmake add <REPO_URL> <REPO_BRANCH>"
                exit 1
            elif [ $# -gt 1 ]; then
                TRACK="$2"
            fi
            shed_load_defaults && \
            shed_add "$1" "$TRACK"
            ;;
        build|build-list)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_resolve_dependencies BUILDDEPS 'status' 'build' && \
            shed_build
            ;;
        clean|clean-list)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shed_clean
            ;;
        clean-repo|clean-repo-list)
            CMDREPOS=( "$1" )
            shed_load_defaults && \
            shed_clean_repos CMDREPOS
            ;;
        clean-all)
            CMDREPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
            shed_load_defaults && \
            shed_clean_repos CMDREPOS
            ;;
        fetch-source|fetch-source-list)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shed_fetch_source
            ;;
        install|install-list)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_resolve_dependencies INSTALLDEPS 'install' 'install' && \
            shed_install
            ;;
        status)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shed_package_status
            ;;
        update-repo|update-repo-list)
            CMDREPOS=( "$1" )
            shed_load_defaults && \
            shed_update_repos CMDREPOS
            ;;
        update-all)
            CMDREPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
            shed_load_defaults && \
            shed_update_repos CMDREPOS
            ;;
        upgrade|upgrade-list)
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_upgrade
            ;;
        upgrade-repo|upgrade-repo-list)
            CMDREPOS=( "$1" )
            shed_load_defaults && \
            shift && \
            shed_parse_args "$@" && \
            shed_upgrade_repos CMDREPOS
            ;;
        upgrade-all)
            CMDREPOS=( "${REMOTEREPOS[@]}" "${LOCALREPOS[@]}" )
            shed_load_defaults && \
            shed_parse_args "$@" && \
            shed_upgrade_repos CMDREPOS
            ;;
        version)
            echo "Shedmake v${SHEDMAKEVER} - A trivial package management tool for Shedbuilt GNU/Linux"
            ;;
        *)
            echo "Unrecognized command: '$SHEDCMD'"
            ;;
    esac
}

# Check for -list action prefix
if [ $# -gt 0 ] && [ "${1: -5}" = '-list' ]; then
    if [ $# -lt 2 ]; then
        echo "Too few arguments to list-based action. Expected: shedmake <list action> <list file> <option 1> ..."
        exit 1
    elif [ ! -r "$2" ]; then
        echo "Unable to read from list file: '$2'"
        exit 1
    fi
    LISTWD="$(pwd)"
    LISTCMD="$1"; shift
    SMLFILE=$(readlink -f -n "$1"); shift
    while read -ra SMLARGS
    do
        if [[ "$SMLARGS" =~ ^#.* ]]; then
            continue
        fi
        PKGARGS=( "$LISTCMD" "${SMLARGS[@]}" "$@" )
        shed_command "${PKGARGS[@]}" || exit 1
        cd "$LISTWD"
    done < "$SMLFILE"
else
    shed_command "$@" || exit 1
fi
