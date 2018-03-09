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
SHEDMAKEVER=0.9.1
CFGFILE=/etc/shedmake.conf
LOCALREPODIR=/var/shedmake/repos/local
REMOTEREPODIR=/var/shedmake/repos/remote
TEMPLATEDIR=/var/shedmake/template

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

shed_set_output_verbosity () {
    if $1; then
        exec 3>&1 4>&2
    else 
        exec 3>/dev/null 4>/dev/null
    fi
}

shed_wget_verbosity () {
    if $VERBOSE; then
        echo '--verbose'
    else
        echo '--no-verbose'
    fi
}

shed_print_args_error () {
    echo "Invalid number of arguments to '$1'. Usage: shedmake $1 $2"
}


shed_print_repo_locate_error () {
    echo "Unable to locate managed package repository named '$1'"
}

# Shedmake Config File Defaults
if [ ! -r "$CFGFILE" ]; then
    echo "Unable to read from config file: '$CFGFILE'"
    exit 1
fi
DEFAULT_NUMJOBS="$(sed -n 's/^NUMJOBS=//p' $CFGFILE)"
DEFAULT_DEVICE="$(sed -n 's/^DEVICE=//p' $CFGFILE)"
TMPDIR="$(sed -n 's/^TMPDIR=//p' $CFGFILE)"
DEFAULT_COMPRESSION="$(sed -n 's/^COMPRESSION=//p' $CFGFILE)"
export SHED_RELEASE="$(sed -n 's/^RELEASE=//p' $CFGFILE)"
export SHED_CPU_CORE="$(sed -n 's/^CPU_CORE=//p' $CFGFILE)"
export SHED_CPU_FEATURES="$(sed -n 's/^CPU_FEATURES=//p' $CFGFILE)"
export SHED_NATIVE_TARGET="$(sed -n 's/^NATIVE_TARGET=//p' $CFGFILE)"
export SHED_TOOLCHAIN_TARGET="$(sed -n 's/^TOOLCHAIN_TARGET=//p' $CFGFILE)"
DEFAULT_KEEPSOURCE=$(shed_parse_yes_no "$(sed -n 's/^KEEPSRC=//p' $CFGFILE)")
DEFAULT_KEEPBINARY=$(shed_parse_yes_no "$(sed -n 's/^KEEPBIN=//p' $CFGFILE)")

shed_load_defaults () {
    VERBOSE=false
    FORCEACTION=false
    KEEPSOURCE="$DEFAULT_KEEPSOURCE"
    KEEPBINARY="$DEFAULT_KEEPBINARY"
    SHOULDIGNOREDEPS=false
    SHOULDINSTALLDEPS=false
    SHOULDPREINSTALL=true
    SHOULDINSTALL=true
    SHOULDPOSTINSTALL=true
    SHOULDCLEANUP=false
    SHOULDSTRIP=true
    REQUIREROOT=false
    export SHED_BUILDMODE=release
    export SHED_TARGET=native
    export SHED_HOST=native
    export SHED_INSTALLROOT='/'
    export SHED_NUMJOBS="$DEFAULT_NUMJOBS"
    export SHED_DEVICE="$DEFAULT_DEVICE"
    REPOBRANCH="$SHED_RELEASE"
    shed_set_binary_archive_compression "$DEFAULT_COMPRESSION"
    shed_set_output_verbosity $VERBOSE
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
            -f|--force)
                FORCEACTION=true
                continue
                ;;
            -I|--ignore-dependencies)
                SHOULDIGNOREDEPS=true
                continue
                ;;
            -i|--install-dependencies)
                SHOULDINSTALLDEPS=true
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
            -N|--skip-install)
                SHOULDINSTALL=false
                continue
                ;;
            -v|--verbose)
                VERBOSE=true
                shed_set_output_verbosity $VERBOSE
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
            -a|--archive-compression)
                shed_set_binary_archive_compression "$OPTVAL" || return 1
                ;;
            -b|--branch)
                REPOBRANCH="$OPTVAL"
                ;;
            -c|--cleanup)
                SHOULDCLEANUP=$(shed_parse_yes_no "$OPTVAL")
                if [ $? -ne 0 ]; then
                    echo "Invalid argument for '$OPTION' Please specify 'yes' or 'no'"
                    return 1
                fi
                ;;
            -d|--device)
                SHED_DEVICE="$OPTVAL"
                ;;
            -D|--dependency-of)
                DEPENDENCY_OF="$OPTVAL"
                ;;
            -h|--host)
                SHED_HOST="$OPTVAL"
                ;;
            -o|--origin)
                REPOURL="$OPTVAL"
                ;;
            -r|--install-root)
                SHED_INSTALLROOT="$OPTVAL"
                ;;
            -j|--jobs)
                SHED_NUMJOBS="$OPTVAL"
                ;;
            -m|--mode)
                SHED_BUILDMODE="$OPTVAL"
                ;;
            -n|--rename)
                REPONAME="$OPTVAL"
                ;;
            -s|--strip)
                SHOULDSTRIP=$(shed_parse_yes_no "$OPTVAL")
                if [ $? -ne 0 ]; then
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
        echo "${NAME}_${VERSION}-${REVISION}_${SHED_RELEASE}_${SHED_BUILDMODE}_${SHED_CPU_CORE}_${SHED_CPU_FEATURES}.${BINARCHEXT}"
    fi
}

shed_locate_package () {
    local PKGDIR
    if [ -d "$1" ]; then
        PKGDIR=$(readlink -f -n "$1")
    else
        local REPO
        for REPO in "${REMOTEREPODIR}"/* "${LOCALREPODIR}"/*; do
            if [ ! -d "$REPO" ]; then
                continue
            elif [ -d "${REPO}/${1}" ]; then
                PKGDIR="${REPO}/${1}"
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

shed_locate_repo () {
    local REPODIR
    if [ -d "$1" ]; then
        REPODIR=$(readlink -f -n "$1")
    elif [ -d "${REMOTEREPODIR}/${1}" ]; then
        REPODIR="${REMOTEREPODIR}/${1}"
    elif [ -d "${LOCALREPODIR}/${1}" ]; then
        REPODIR="${LOCALREPODIR}/${1}"
    fi
    if [ -z "$REPODIR" ]; then
        return 1
    else
        echo $REPODIR
    fi
}

shed_read_package_meta () {
    export SHED_PKGDIR=$(shed_locate_package "$1")
    if [ -z "$SHED_PKGDIR" ]; then
        echo "$1 is not a package directory"
        return 1
    fi

    if [[ $SHED_PKGDIR =~ ^$REMOTEREPODIR.* ]]; then
        # Actions on packages in managed remote repositories always require root privileges
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
    export SHED_VERSION_TUPLE="${VERSION}-${REVISION}"
    export SHED_INSTALL_BOM="${SHED_LOGDIR}/${SHED_VERSION_TUPLE}.bom"
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
    if [ "$(sed -n 's/^CLEANUP=//p' ${PKGMETAFILE})" = 'yes' ]; then
        SHOULDCLEANUP=true
    fi
    BIN=$(sed -n 's/^BIN=//p' ${PKGMETAFILE})
    BINFILE=$(sed -n 's/^BINFILE=//p' ${PKGMETAFILE})
    if [ -z "$BINFILE" ] && [ -n "$BIN" ]; then
        BINFILE=$(basename $BIN)
    fi
    read -ra BUILDDEPS <<< $(sed -n 's/^BUILDDEPS=//p' ${PKGMETAFILE})
    read -ra INSTALLDEPS <<< $(sed -n 's/^INSTALLDEPS=//p' ${PKGMETAFILE})
    read -ra RUNDEPS <<< $(sed -n 's/^RUNDEPS=//p' ${PKGMETAFILE})
    export SHED_INSTALL_HISTORY="${SHED_LOGDIR}/install.log"
    export SHED_INSTALLED_VERSION_TUPLE=''
    if [ -e "$SHED_INSTALL_HISTORY" ]; then
        SHED_INSTALLED_VERSION_TUPLE=$(tail -n 1 "$SHED_INSTALL_HISTORY")
    fi
    if [ -z "$NAME" ] || [ -z "$VERSION" ] || [ -z "$REVISION" ]; then
        echo "Required fields missing from package metadata."
        return 1
    fi
}

shed_resolve_dependencies () {
    local -n DEPS=$1
    local DEPTYPE=$2
    local DEPACTION
    local DEP
    local STATUSRETVAL
    if $SHOULDINSTALLDEPS; then
        case "$DEPTYPE" in
            install|build)
                DEPACTION='install'
            ;;
            upgrade)
                DEPACTION='upgrade'
            ;;
        esac
    else
        DEPACTION='status'
    fi
    if ! $SHOULDIGNOREDEPS && [ ${#DEPS[@]} -gt 0 ]; then
        echo "Resolving $DEPTYPE dependencies for '$NAME'..."
        for DEP in "${DEPS[@]}"; do
            if [ "$DEP" == "$DEPENDENCY_OF" ]; then
                if $VERBOSE; then
                    echo "Ignoring circular dependency '$DEP'."
                fi
                continue
            fi
            case "$DEPACTION" in
                install|upgrade)
                    local DEPARGS=( "$DEPACTION" "$DEP" "${PARSEDARGS[@]}" "--dependency-of" "$NAME" )
                    shedmake "${DEPARGS[@]}" || return 1
                ;;
                status)
                    # Ensure package is installed, if not up-to-date
                    shedmake status "$DEP"
                    STATUSRETVAL=$?
                    if [ $STATUSRETVAL -ne 0 ] && [ $STATUSRETVAL -ne 2 ]; then
                        return 1
                    fi
                ;;
            esac
        done
    fi
    # Ensure retval is 0, as shedmake status may have returned a non-zero value
    return 0
}

shed_download_source () {
    if [ ! -d "$SRCCACHEDIR" ]; then
        mkdir "$SRCCACHEDIR"
    fi
    cd "$SRCCACHEDIR"
    wget -O "$SRCFILE" "$SRC" $(shed_wget_verbosity)
}

shed_download_binary () {
    if [ ! -d "$BINCACHEDIR" ]; then
        mkdir "$BINCACHEDIR"
    fi
    cd "$BINCACHEDIR"
    local BINURL=$(eval echo "$BIN")
    wget -O "$(shed_binary_archive_name)" "$BINURL" $(shed_wget_verbosity)
}

shed_verify_source () {
    if [ -n "$SRCMD5" ]; then
        if [ "$(md5sum ${SRCCACHEDIR}/${SRCFILE} | awk '{print $1}')" != "$SRCMD5" ]; then
            return 1
        fi
    elif $VERBOSE; then
        echo 'WARNING: Skipping verification of source archive because SRCMD5 is absent from package metadata'
    fi
}

shed_strip_binaries () {
    local STRIPFOLDER
    # Strip all binaries and libraries, except explicitly created .dbg symbol files
    if [ -d "${SHED_FAKEROOT}/usr/lib" ]; then
        find "${SHED_FAKEROOT}/usr/lib" -type f -name \*.a \
            -exec strip --strip-debug {} ';'
    fi
    for STRIPFOLDER in "${SHED_FAKEROOT}"/lib "${SHED_FAKEROOT}"/usr/{,local/}lib
    do
        if [ -d "$STRIPFOLDER" ]; then
            find "$STRIPFOLDER" -type f \( -name \*.so* -a ! -name \*dbg \) \
                -exec strip --strip-unneeded {} ';'
        fi
    done
    for STRIPFOLDER in "${SHED_FAKEROOT}"/{bin,sbin} "${SHED_FAKEROOT}"/usr/{,local/}{bin,sbin,libexec}
    do
        if [ -d "$STRIPFOLDER" ]; then
            find "$STRIPFOLDER" -type f \
                -exec strip --strip-all {} ';'
        fi
    done
}

shed_cleanup () {
    local NEWVERSION="$1"
    local OLDVERSION="$2"
    local PATHSTODELETE=''
    cd "$SHED_LOGDIR"
    if [ -z "$OLDVERSION" ] || [ "$NEWVERSION" == "$OLDVERSION" ]; then
        if $VERBOSE; then
            echo "No need to clean up orphaned files between specified versions."
        fi
        return 0
    fi
    if [ ! -e ${OLDVERSION}.bom ]; then
        echo "Unable to retrieve install log for previous version '$OLDVERSION'"
        return 1
    fi
    if [ -z "$NEWVERSION" ]; then
        # Delete all files from old version if no new version replaces it
        PATHSTODELETE="$(<${OLDVERSION}.bom)"
        echo "Shedmake will uninstall '$NAME'..."
    elif [ ! -e ${NEWVERSION}.bom ]; then
        echo "Unable to retrieve install log for current version '$NEWVERSION'"
        return 1
    else
        PATHSTODELETE="$(comm -13 ${NEWVERSION}.bom ${OLDVERSION}.bom)"
        echo "Shedmake will delete files orphaned when '$NAME' was upgraded from $OLDVERSION to $NEWVERSION..."
    fi
    local OLDPATH
    local PATHTYPE
    for PATHTYPE in files directories
    do
        while read -ra OLDPATH
        do
            if [ ${#OLDPATH} -gt 2 ] && [[ "${OLDPATH:0:2}" == './' ]]; then
                local INSTALLEDPATH="${SHED_INSTALLROOT%/}/${OLDPATH:2}"
                case $PATHTYPE in
                    files)
                        if [ ! -d "$INSTALLEDPATH" ]; then
                            rm -v "$INSTALLEDPATH"
                        fi
                        ;;
                    directories)
                        if [ -d "$INSTALLEDPATH" ]; then
                            rmdir -v "$INSTALLEDPATH"
                        fi
                        ;;
                esac
            fi
        done <<< "$PATHSTODELETE"
    done
    if [ -z "$NEWVERSION" ]; then
        # Delete the install log dir if uninstalling
        cd ..
        rm -rf "$SHED_LOGDIR"
    fi
}

shed_run_script () {
    bash "$1" 1>&3 2>&4
}

# Function: shed_run_chroot_script
# Description: Runs a package script in a chroot environment
# Arguments:
#     $1 - Absolute path to changed root
#     $2 - Path to package relative to changed root
#     $3 - Name of package script to run
shed_run_chroot_script () {
    chroot "$1" /usr/bin/env -i \
    HOME=/root                  \
    TERM="$TERM"                \
    PS1='\u:\w\$ '              \
    PATH=/bin:/usr/bin:/sbin:/usr/sbin \
    SHED_DEVICE="$SHED_DEVICE" \
    SHED_NUMJOBS="$SHED_NUMJOBS" \
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
    SHED_VERSION_TUPLE="$SHED_VERSION_TUPLE" \
    SHED_INSTALL_BOM="${2}/install/${SHED_VERSION_TUPLE}.bom" \
    bash "${2}/${3}" 1>&3 2>&4
}

shed_can_add_repo () {
    if [ -d "${REMOTEREPODIR}/${1}" ]; then
        echo 'A remote repository named '$1' already exists.'
        return 1
    elif [ -d "${LOCALREPODIR}/${1}" ]; then
        echo 'A local repository named '$1' already exists.'
        return 1
    fi
}

shed_add () {
    local REPOFILE="$(basename $REPOURL)"
    if [ -z "$REPONAME" ]; then
        REPONAME="$(basename $REPOFILE .git)"
    fi
    cd "${LOCALREPODIR}/${1}" || return 1
    if [ -d "$REPONAME" ]; then
        echo "A directory named '$REPONAME' is already present in local package repository '${1}'"
        return 1
    fi
    git submodule add -b "$REPOBRANCH" "$REPOURL" && \
    git submodule init || return 1
}

shed_add_repo () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to add a remote repository."
        return 1
    fi
    local REPOFILE="$(basename $REPOURL)"
    if [ -z "$REPONAME" ]; then
        REPONAME="$(basename $REPOFILE .git)"
    fi
    shed_can_add_repo "$REPONAME" && \
    cd "$REMOTEREPODIR" && \
    git clone "$REPOURL" "$REPONAME" && \
    cd "$REPONAME" && \
    git checkout "$REPOBRANCH" && \
    git submodule init && \
    git submodule update && \
    echo "Successfully added remote repository '$REPONAME'"
}

shed_fetch_source () {
   if [ -n "$SRC" ]; then
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            if [ ! -d "${SRCCACHEDIR}/${NAME}-git" ]; then
                mkdir -p "${SRCCACHEDIR}/${NAME}-git"
                cd "${SRCCACHEDIR}/${NAME}-git"
                git init 1>&3 2>&4 && \
                git remote add origin "$SRC" 1>&3 2>&4 || return 1
            else
                cd "${SRCCACHEDIR}/${NAME}-git"
            fi
            # Perform a shallow fetch of the desired refspec
            local LOCALREPOREF="$(sed -e "s/^refs\/heads\//refs\/remotes\/origin\//g" <<< $REPOREF)"
            git fetch --depth=1 origin +${REPOREF}:${LOCALREPOREF} 1>&3 2>&4 && \
            git checkout --quiet FETCH_HEAD 1>&3 2>&4 || return 1
            # TODO: Use signature for verification
        else 
            # Source is an archive
            if [ ! -r ${SRCCACHEDIR}/${SRCFILE} ]; then
                shed_download_source
                if [ $? -ne 0 ]; then
                    echo "Unable to download source archive ${SRCFILE}"
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
    if ! $VERBOSE; then
        echo -n "Building '$NAME' ($SHED_VERSION_TUPLE)..."
    fi
    mkdir "${SHED_FAKEROOT}"
    if [ -a "${SHED_PKGDIR}/build.sh" ]; then
        shed_run_script "${SHED_PKGDIR}/build.sh"
    else
        echo "Missing build script for '$NAME' ($SHED_VERSION_TUPLE)"
        return 1
    fi

    if [ $? -ne 0 ]; then
        echo "Failed to build '$NAME' ($SHED_VERSION_TUPLE)"
        rm -rf "$WORKDIR"
        return 1
    fi
    if ! $VERBOSE; then
        echo 'done'
    else
        echo "Successfully built '$NAME' ($SHED_VERSION_TUPLE)"
    fi

    # Strip Binaries
    if $SHOULDSTRIP ; then
        echo -n 'Stripping binaries...'
        shed_strip_binaries
        echo 'done'
    fi

    # Archive Build Product
    if [ ! -d "$BINCACHEDIR" ]; then
        mkdir "$BINCACHEDIR"
    fi
    echo -n "Creating binary archive $(shed_binary_archive_name)..."
    tar -caf "${BINCACHEDIR}/$(shed_binary_archive_name)" -C "$SHED_FAKEROOT" . || return 1
    echo 'done'

    # Delete Source
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
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to install a package."
        return 1
    fi

    # Prepare log directory
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')
    if [ ! -d "${SHED_LOGDIR}" ]; then
        mkdir "${SHED_LOGDIR}"
    fi

    # Pre-installation
    if [ -a "${SHED_PKGDIR}/preinstall.sh" ]; then
        if $SHOULDPREINSTALL; then
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                shed_run_script "${SHED_PKGDIR}/preinstall.sh" || return 1
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
                shed_run_script "${SHED_PKGDIR}/install.sh" || return 1
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
                echo -n "Installing files from binary archive $(shed_binary_archive_name)..."
                tar xvhf "$BINARCHIVE" -C "$SHED_INSTALLROOT" > "$SHED_INSTALL_BOM" || return 1
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

    # Post-installation
    if [ -a "${SHED_PKGDIR}/postinstall.sh" ]; then
        if $SHOULDPOSTINSTALL; then
            echo "Running post-install script for '$NAME' ($SHED_VERSION_TUPLE)..."
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                shed_run_script "${SHED_PKGDIR}/postinstall.sh" || return 1
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" postinstall.sh || return 1
            fi
        else
            echo "Skipping the post-install phase."
        fi
    fi

    # Sort Install Log
    sort "$SHED_INSTALL_BOM" -o "$SHED_INSTALL_BOM"

    # Record Installation
    if [ "$SHED_VERSION_TUPLE" != "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        echo "$SHED_VERSION_TUPLE" >> "$SHED_INSTALL_HISTORY"
    fi

    # Clean Up Old Files
    if $SHOULDCLEANUP && [ -n "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        shed_cleanup "$SHED_VERSION_TUPLE" "$SHED_INSTALLED_VERSION_TUPLE"
    fi

    echo "Successfully installed '$NAME' ($SHED_VERSION_TUPLE)"
}

shed_update_repo_at_path () {
    cd "${1}" || return 1
    if [[ ${1} =~ ^$REMOTEREPODIR.* ]]; then
        if [[ $EUID -ne 0 ]]; then
            echo 'Root privileges are required to update managed remote package repositories.'
            return 1
        fi
        echo "Shedmake is updating the remote repository at ${1}..."   
        git pull && \
        git submodule init && \
        git submodule update
    else
        echo "Shedmake is updating the local repository at ${1}..."   
        git submodule update --remote
    fi
}

shed_update_repo () {
    local REPO=$(shed_locate_repo "$1")
    if [ -z "$REPO" ]; then
        shed_print_repo_locate_error "$REPO"
        return 1
    fi
    shed_update_repo_at_path "$REPO"
}

shed_update_all () {
    local REPO
    for REPO in "${REMOTEREPODIR}"/* "${LOCALREPODIR}"/*; do
        shed_update_repo_at_path "$REPO" || return 1
    done
}

shed_clean () {
   if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
       echo "Root privileges are required to clean this package."
       return 1
   fi
   echo "Cleaning cached archives for '$NAME'..."
   rm -rf "$SRCCACHEDIR" && \
   rm -rf "$BINCACHEDIR"
}

shed_clean_repo_at_path () {
    echo "Shedmake will clean packages in the repository at '$1'..."
    local PACKAGE
    for PACKAGE in "${1}"/*; do
        if [ ! -d "$PACKAGE" ]; then
            continue
        fi
        shed_read_package_meta "$PACKAGE" && \
        shed_clean || return 1
    done
}

shed_clean_repo () {
    local REPO=$(shed_locate_repo "$1")
    if [ -z "$REPO" ]; then
        shed_print_repo_locate_error "$REPO"
        return 1
    fi
    shed_clean_repo_at_path "$REPO"
}

shed_clean_all () {
    local REPO
    for REPO in "${REMOTEREPODIR}"/* "${LOCALREPODIR}"/*; do
        if [ ! -d "${REPO}" ]; then
            continue
        fi
        shed_clean_repo_at_path "$REPO" || return 1
    done
}

shed_package_status () {
    # NOTE: Reserve retval 1 for packages not found in managed repositories
    if [ -n "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        if [ "$SHED_VERSION_TUPLE" == "$SHED_INSTALLED_VERSION_TUPLE" ]; then
            echo "Package '$NAME' is installed and up-to-date ($SHED_INSTALLED_VERSION_TUPLE)"
            return 0
        else
            echo "Package '$NAME' ($SHED_INSTALLED_VERSION_TUPLE) is installed but $SHED_VERSION_TUPLE is available"
            return 2
        fi
    else
        echo "Package '$NAME' ($SHED_VERSION_TUPLE) is available but not installed"
        return 3
    fi
}

shed_upgrade () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to upgrade packages."
        return 1
    fi
    shed_package_status
    if [ $? -eq 2 ]; then
        FORCEACTION=true
        SHOULDINSTALLDEPS=true
        shed_resolve_dependencies INSTALLDEPS 'upgrade' && \
        shed_install || return $?
    fi
    # Ensure retval of 0, as shed_package_status may have returned an acceptable non-zero value
    return 0
}

shed_upgrade_repo_at_path () {
    echo "Shedmake is preparing upgrade packages in the repository at '$1'..."
    local PACKAGE
    for PACKAGE in "${1}"/*; do
        if [ ! -d "$PACKAGE" ]; then
            continue
        fi
        shed_read_package_meta "$PACKAGE" && \
        shed_upgrade || return 1
    done
}

shed_upgrade_repo () {
    local REPO=$(shed_locate_repo "$1")
    if [ -z "$REPO" ]; then
        shed_print_repo_locate_error "$REPO"
        return 1
    fi
    shed_upgrade_repo_at_path "$REPO"
}

shed_upgrade_all () {
    local REPO
    for REPO in "${REMOTEREPODIR}"/* "${LOCALREPODIR}"/*; do
        if [ ! -d "${REPO}" ]; then
            continue
        fi
        shed_upgrade_repo "$REPO" || return 1
    done
}

shed_create () {
    local NEWPKGNAME=$(basename "$1")
    echo "Shedmake is creating a new package directory for '$NEWPKGNAME'..."
    mkdir "$1" && \
    cd "$1" || return 1
    if [ -n "$REPOURL" ]; then
        git init && \
        git remote add origin "$REPOURL" || return 1
    fi
    local TEMPLATEFILE
    local TEMPLATEFILENAME
    for TEMPLATEFILE in "${TEMPLATEDIR}"/{.[!.],}*
    do
        cp "$TEMPLATEFILE" .
        TEMPLATEFILENAME=$(basename "$TEMPLATEFILE")
        if [ "$TEMPLATEFILENAME" == 'package.txt' ]; then
            sed -i "s/NAME=.*/NAME=${NEWPKGNAME}/g" "$TEMPLATEFILENAME"
        fi
        if [ -n "$REPOURL" ]; then
            git add "$TEMPLATEFILENAME" || return 1
        fi
    done
}

shed_create_repo () {
    shed_can_add_repo "$1" && \
    mkdir -v "${LOCALREPODIR}/$1" || return 1
    if [ -n "$REPOURL" ]; then
        cd "${LOCALREPODIR}/$1" && \
        git init && \
        git remote add origin "$REPOURL"
    fi
}

shed_push () {
    echo "Shedmake is preparing to push the master revision of '$1' to '$REPOBRANCH'..."
    local TAG="$2"
    push -u origin master && \
    { git checkout "$REPOBRANCH" || git checkout -b "$REPOBRANCH"; } && \
    git merge master && \
    git push -u origin "$REPOBRANCH" && \
    git tag "$TAG" && \
    git push -u origin --tags
}

shed_push_package () {
    shed_push "$1" "${VERSION}-${SHED_RELEASE}-${REVISION}"
}

shed_push_repo () {
    local NEWTAG
    local LASTTAG="$(git describe --tags)"
    if [ -n "LASTTAG" ]; then
        NEWTAG="${SHED_RELEASE}-$(($(echo $LASTTAG | sed 's/.*-\([0-9]*\)$/\1/') + 1))"
    else
        NEWTAG="${SHED_RELEASE}-1"
    fi
    shed_push "$1" "$NEWTAG"
}

shed_command () {
    local SHEDCMD
    if [ $# -gt 0 ]; then
        SHEDCMD=$1; shift
    else
        SHEDCMD=version
    fi

    case "$SHEDCMD" in
        add|add-list)
            if [ $# -lt 2 ]; then
                shed_print_args_error "$SHEDCMD" '<package_url> <local_repo> [--rename <local_name>] [--branch <repo_branch>]'
                return 1
            fi
            REPOURL="$1"; shift
            local ADDTOREPO="$2"; shift
            shed_load_defaults && \
            shed_parse_args "$@" && \
            shed_add "$ADDTOREPO"
            ;;
        add-repo|add-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_url> [--rename <local_name>] [--branch <repo_branch>]'
                return 1
            fi
            REPOURL="$1"; shift
            shed_load_defaults && \
            shed_parse_args "$@" && \
            shed_add_repo
            ;;
        build|build-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            echo "Shedmake is preparing to build '$NAME' ($SHED_VERSION_TUPLE)..." && \
            shed_resolve_dependencies BUILDDEPS 'build' && \
            shed_build
            ;;
        clean|clean-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shed_clean
            ;;
        clean-repo|clean-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_clean_repos "$1"
            ;;
        clean-all)
            if [ $# -ne 0 ]; then
                shed_print_args_error "$SHEDCMD" ''
                return 1
            fi
            shed_load_defaults && \
            shed_clean_all
            ;;
        cleanup|cleanup-list|uninstall|uninstall-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" || return 1
            if [ ! -e "$SHED_INSTALL_HISTORY" ]; then
                echo "Unable to locate installed version history for '$NAME'"
                return 1
            fi
            local OLDVERSIONTUPLE
            local NEWVERSIONTUPLE
            if [ "$SHEDCMD" == 'cleanup' ]; then
                OLDVERSIONTUPLE="$(tail -n 2 $SHED_INSTALL_HISTORY | head -n 1)"
                NEWVERSIONTUPLE="$SHED_INSTALLED_VERSION_TUPLE"
            else
                OLDVERSIONTUPLE="$SHED_INSTALLED_VERSION_TUPLE"
                NEWVERSIONTUPLE=""
            fi
            shed_cleanup "$NEWVERSIONTUPLE" "$OLDVERSIONTUPLE"
            ;;
        create|create-list|create-repo|create-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" "<new_package_name> [--origin <repo_url>]"
                return 1
            fi
            local CREATENAME="$1"; shift
            shed_load_defaults && \
            shed_parse_args "$@" || return 1
            case "$SHEDCMD" in
                create|create-list)
                    shed_create "$CREATENAME"
                    ;;
                create-repo|create-repo-list)
                    shed_create_repo "$CREATENAME"
                    ;;
            esac
            ;;
        fetch-source|fetch-source-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_fetch_source
            ;;
        install|install-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" || return 1
            if [ -n "$SHED_INSTALLED_VERSION_TUPLE" ] && ! $FORCEACTION; then
                echo "Package '$NAME' is already installed (${SHED_INSTALLED_VERSION_TUPLE})"
                return 0
            fi
            echo "Shedmake is preparing to install '$NAME' ($SHED_VERSION_TUPLE) to ${SHED_INSTALLROOT}..." && \
            shed_resolve_dependencies INSTALLDEPS 'install' && \
            shed_install
            ;;
        push|push-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            cd "$SHED_PKGDIR" && \
            shed_push_package "$NAME"
            ;;
        push-repo|push-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local PUSHREPO="$1"; shift
            local REPOPATH=$(shed_locate_repo "$PUSHREPO")
            if [ -z "$REPOPATH" ]; then
                shed_print_repo_locate_error "$PUSHREPO"
                return 1
            fi
            shed_load_defaults && \
            shed_parse_args "$@" && \
            cd "$REPOPATH" && \
            shed_push_repo "$PUSHREPO"
            ;;
        status|status-list)
            if [ $# -ne 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name>'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shed_package_status
            ;;
        update-repo|update-repo-list)
            if [ $# -ne 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name>'
                return 1
            fi
            shed_load_defaults && \
            shed_update_repo "$1"
            ;;
        update-all)
            if [ $# -ne 0 ]; then
                shed_print_args_error "$SHEDCMD" ''
                return 1
            fi
            shed_load_defaults && \
            shed_update_all
            ;;
        upgrade|upgrade-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_upgrade
            ;;
        upgrade-repo|upgrade-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            shed_load_defaults && \
            shift && \
            shed_parse_args "$@" && \
            shed_upgrade_repo "$1"
            ;;
        upgrade-all)
            if [ $# -ne 0 ]; then
                shed_print_args_error "$SHEDCMD" ''
                return 1
            fi
            shed_load_defaults && \
            shed_parse_args "$@" && \
            shed_upgrade_all
            ;;
        version)
            if [ $# -ne 0 ]; then
                shed_print_args_error "$SHEDCMD" ''
                return 1
            fi
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
        shed_command "${PKGARGS[@]}" || exit $?
        cd "$LISTWD"
    done < "$SMLFILE"
else
    shed_command "$@"
fi
