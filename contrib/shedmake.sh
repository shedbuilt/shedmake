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
SHEDMAKEVER=0.9.9
CFGFILE=/etc/shedmake.conf

shed_parse_yes_no () {
    case "$1" in
        yes) echo 'true';;
        no) echo 'false';;
        *) return 1;;
    esac
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

shed_print_args_error () {
    echo "Invalid number of arguments to '$1'. Usage: shedmake $1 $2"
}


shed_print_repo_locate_error () {
    echo "Unable to locate managed package repository named '$1'"
}

shed_load_config () {
    if [ ! -r "$CFGFILE" ]; then
        echo "Unable to read from config file: '$CFGFILE'"
        return 1
    fi
    TMPDIR="$(sed -n 's/^TMP_DIR=//p' $CFGFILE)"
    LOCALREPODIR="$(sed -n 's/^LOCAL_REPO_DIR=//p' $CFGFILE)"
    REMOTEREPODIR="$(sed -n 's/^REMOTE_REPO_DIR=//p' $CFGFILE)"
    TEMPLATEDIR="$(sed -n 's/^TEMPLATE_DIR=//p' $CFGFILE)"
    DEFAULT_CACHESOURCE=$(shed_parse_yes_no "$(sed -n 's/^CACHE_SRC=//p' $CFGFILE)")
    DEFAULT_CACHEBINARY=$(shed_parse_yes_no "$(sed -n 's/^CACHE_BIN=//p' $CFGFILE)")
    DEFAULT_COMPRESSION="$(sed -n 's/^COMPRESSION=//p' $CFGFILE)"
    DEFAULT_NUMJOBS="$(sed -n 's/^NUM_JOBS=//p' $CFGFILE)"
    DEFAULT_DEVICE="$(sed -n 's/^DEVICE=//p' $CFGFILE)"
    export SHED_RELEASE="$(sed -n 's/^RELEASE=//p' $CFGFILE)"
    export SHED_CPU_CORE="$(sed -n 's/^CPU_CORE=//p' $CFGFILE)"
    export SHED_CPU_FEATURES="$(sed -n 's/^CPU_FEATURES=//p' $CFGFILE)"
    export SHED_NATIVE_TARGET="$(sed -n 's/^NATIVE_TARGET=//p' $CFGFILE)"
    export SHED_TOOLCHAIN_TARGET="$(sed -n 's/^TOOLCHAIN_TARGET=//p' $CFGFILE)"
}

shed_load_defaults () {
    VERBOSE=false
    FORCEACTION=false
    SHOULDCLEANTEMP=true
    SHOULDCACHESOURCE=false
    SHOULDCACHEBINARY=false
    SHOULDIGNOREDEPS=false
    SHOULDINSTALLDEPS=false
    SHOULDPREINSTALL=true
    SHOULDINSTALL=true
    SHOULDPOSTINSTALL=true
    SHOULDPURGE=false
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
            -c|--cache-source)
                SHOULDCACHESOURCE=true
                continue
                ;;
            -C|--cache-binary)
                SHOULDCACHEBINARY=true
                continue
                ;;
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
            -r|--retain-temp)
                SHOULDCLEANTEMP=false
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
            -B|--binary-dir)
                BINCACHEDIR="$OPTVAL"
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
            -p|--purge)
                SHOULDPURGE=$(shed_parse_yes_no "$OPTVAL")
                if [ $? -ne 0 ]; then
                    echo "Invalid argument for '$OPTION' Please specify 'yes' or 'no'"
                    return 1
                fi
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
            -S|--source-dir)
                SRCCACHEDIR="$OPTVAL"
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
    WORKDIR="${TMPDIR%/}/${NAME}_${SHED_VERSION_TUPLE}"
    export SHDPKG_FAKEROOT="${WORKDIR}/fakeroot"
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
    if [ "$(sed -n 's/^PURGE=//p' ${PKGMETAFILE})" = 'yes' ]; then
        SHOULDPURGE=true
    fi
    BIN=$(sed -n 's/^BIN=//p' ${PKGMETAFILE})
    BINFILE=$(sed -n 's/^BINFILE=//p' ${PKGMETAFILE})
    if [ -z "$BINFILE" ] && [ -n "$BIN" ]; then
        BINFILE=$(basename $BIN)
    fi
    read -ra LICENSE <<< $(sed -n 's/^LICENSE=//p' ${PKGMETAFILE})
    read -ra BUILDDEPS <<< $(sed -n 's/^BUILDDEPS=//p' ${PKGMETAFILE})
    read -ra INSTALLDEPS <<< $(sed -n 's/^INSTALLDEPS=//p' ${PKGMETAFILE})
    read -ra RUNDEPS <<< $(sed -n 's/^RUNDEPS=//p' ${PKGMETAFILE})
    DEFERREDDEPS=( )
    export SHED_INSTALL_HISTORY="${SHED_LOGDIR}/install.log"
    export SHED_INSTALLED_VERSION_TUPLE=''
    if [ -e "$SHED_INSTALL_HISTORY" ]; then
        SHED_INSTALLED_VERSION_TUPLE=$(tail -n 1 "$SHED_INSTALL_HISTORY")
    fi
    if [ -z "$NAME" ] || [ -z "$VERSION" ] || [ -z "$REVISION" ]; then
        echo 'Required fields missing from package metadata.'
        return 1
    fi
}

shed_package_info () {
    echo "Shedmake information for package located at $SHED_PKGDIR..."
    echo "Name:			$NAME"
    echo "Version:		$VERSION"
    echo "Package Revision:	$REVISION"
    echo "Source File URL:	$SRC"
    echo "Source File Name:	$SRCFILE"
    if [ -n "$SRCMD5" ]; then
        echo "Source File MD5SUM:	$SRCMD5"
    fi
    if [ -n "$REPOREF" ]; then
        echo "Source Git Refspec:	$REPOREF"
    fi
    if [ -n "$BIN" ]; then
        echo "Binary Archive URL (Raw):	$BIN"
        local BINURL=$(eval echo "$BIN")
        echo "Binary Archive URL:	$BINURL"
    fi
    echo "Binary Archive Name:	$(shed_binary_archive_name)"
    if [ -n "$LICENSE" ]; then
        echo "License(s):		${LICENSE[@]}"
    fi
    if [ -n "$BUILDDEPS" ]; then
        echo "Build Dependencies:	${BUILDDEPS[@]}"
    fi
    if [ -n "$INSTALLDEPS" ]; then
        echo "Install Dependencies:	${INSTALLDEPS[@]}"
    fi
    if [ -n "$RUNDEPS" ]; then
        echo "Runtime Dependencies:	${RUNDEPS[@]}"
    fi
    if [ -n "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        echo "Installed Version:	$SHED_INSTALLED_VERSION_TUPLE"
    else
        echo "Installed Version:	Not Installed"
    fi
    if $VERBOSE; then
        if [ -d "$SHED_PATCHDIR" ]; then
            echo -n "Patches: "
            ls "$SHED_PATCHDIR"
        fi
        if [ -d "$SHED_CONTRIBDIR" ]; then
            echo -n "Contrib Files: "
            ls "$SHED_CONTRIBDIR"
        fi
        if [ -d "$SHED_LOGDIR" ]; then
            echo -n "Install Logs: "
            ls "$SHED_LOGDIR"
        fi
    fi
}

# Returns:
#     0 - All hard dependencies successfully resolved
#   1-9 - File location or format error
# 10-19 - Package status error
# 20-29 - Package build error
# 30-39 - Package install error
#    40 - Unmet circular dependency error
shed_resolve_dependencies () {
    local -n DEPS=$1
    local DEPTYPE=$2
    local INSTALLACTION=$3
    local CANDEFER=$4
    local DEPACTION='status'
    local DEP
    local DEP_RESOLVE_RETVAL=0
    local DEP_RETVAL=0
    if ! $SHOULDIGNOREDEPS && [ ${#DEPS[@]} -gt 0 ]; then
        if $SHOULDINSTALLDEPS; then
            DEPACTION="$INSTALLACTION"
        fi
        echo "Resolving $DEPTYPE dependencies for '$NAME'..."
        for DEP in "${DEPS[@]}"; do
            local ISHARDDEP=true
            if [ ${#DEP} -gt 2 ] && [ "${DEP:0:1}" == '(' ] && [ "${DEP: -1}" == ')' ]; then
                ISHARDDEP=false
                DEP="${DEP:1:$(expr ${#DEP} - 2)}"
            fi
            if [ "$DEP" == "$DEPENDENCY_OF" ]; then
                # Do not attempt to install a circular dependency
                DEPACTION='status'
            fi
            case "$DEPACTION" in
                install|upgrade)
                    local IGNOREARG=false
                    local DEPARGS=( "$DEPACTION" "$DEP" "--dependency-of" "$NAME" )
                    for PARSEDARG in "${PARSEDARGS[@]}"; do
                        if $IGNOREARG; then
                            IGNOREARG=false
                            continue
                        fi
                        case "$PARSEDARG" in
                            -D|--dependency-of)
                                IGNOREARG=true
                                ;&
                            -f|--force)
                                continue
                                ;;
                            *)
                                DEPARGS+=( "$PARSEDARG" )
                                ;;
                        esac
                    done
                    shedmake "${DEPARGS[@]}"
                    DEP_RETVAL=$?
                    if [ $DEP_RETVAL -ne 0 ]; then
                        if $ISHARDDEP; then
                            DEP_RESOLVE_RETVAL=$DEP_RETVAL
                            break
                        elif [ $DEP_RETVAL -eq 40 ]; then
                            if $CANDEFER; then
                                echo "Deferring resolution of soft circular dependency '$DEP'"
                                DEFERREDDEPS+=( "$DEP" )
                            else
                                echo "Ignoring unresolved, soft circular dependency '$DEP'"
                            fi
                        else
                            echo "Ignoring unresolved soft dependency '$DEP'"
                        fi
                    fi
                ;;
                status)
                    # Ensure package is installed, if not up-to-date
                    shedmake status "$DEP"
                    DEP_RETVAL=$?
                    if $ISHARDDEP && [ $DEP_RETVAL -ne 0 ] && [ $DEP_RETVAL -ne 10 ]; then
                        if [ $DEP_RETVAL -eq 11 ] && [ "$DEP" == "$DEPENDENCY_OF" ]; then
                                DEP_RESOLVE_RETVAL=40
                        else
                                DEP_RESOLVE_RETVAL=$DEP_RETVAL
                        fi
                    fi
                ;;
            esac
        done
    fi
    if [ $DEP_RESOLVE_RETVAL -ne 0 ]; then
        echo "Action aborted due to unmet $DEPTYPE dependencies."
    fi
    return $DEP_RESOLVE_RETVAL
}

shed_strip_binaries () {
    local STRIPFOLDER
    # Strip all binaries and libraries, except explicitly created .dbg symbol files
    if [ -d "${SHED_FAKEROOT}/usr/lib" ]; then
        find "${SHED_FAKEROOT}/usr/lib" -type f -name \*.a -exec strip --strip-debug {} ';' 1>&3 2>&4
    fi
    for STRIPFOLDER in "${SHED_FAKEROOT}"/lib "${SHED_FAKEROOT}"/usr/{,local/}lib
    do
        if [ -d "$STRIPFOLDER" ]; then
            find "$STRIPFOLDER" -type f \( -name \*.so* -a ! -name \*dbg \) -exec strip --strip-unneeded {} ';' 1>&3 2>&4
        fi
    done
    for STRIPFOLDER in "${SHED_FAKEROOT}"/{bin,sbin} "${SHED_FAKEROOT}"/usr/{,local/}{bin,sbin,libexec}
    do
        if [ -d "$STRIPFOLDER" ]; then
            find "$STRIPFOLDER" -type f -exec strip --strip-all {} ';' 1>&3 2>&4
        fi
    done
}

shed_purge () {
    local NEWVERSION="$1"
    local OLDVERSION="$2"
    local PATHSTODELETE=''
    cd "$SHED_LOGDIR"
    if [ -z "$OLDVERSION" ] || [ "$NEWVERSION" == "$OLDVERSION" ]; then
        if $VERBOSE; then
            echo "Skipping purge of files orphaned by an upgrade."
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
        echo -n "Shedmake will uninstall '$NAME' ($OLDVERSION)..."
    elif [ ! -e ${NEWVERSION}.bom ]; then
        echo "Unable to retrieve install log for current version '$NEWVERSION'"
        return 1
    else
        PATHSTODELETE="$(comm -13 ${NEWVERSION}.bom ${OLDVERSION}.bom)"
        echo -n "Shedmake will purge files orphaned when '$NAME' was upgraded from $OLDVERSION to $NEWVERSION..."
    fi
    if $VERBOSE; then echo; fi
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
                            rm -v "$INSTALLEDPATH" 1>&3 2>&4
                        fi
                        ;;
                    directories)
                        if [ -d "$INSTALLEDPATH" ]; then
                            rmdir -v "$INSTALLEDPATH" 1>&3 2>&4
                        fi
                        ;;
                esac
            fi
        done <<< "$PATHSTODELETE"
    done
    if [ -z "$NEWVERSION" ]; then
        # Delete the install log dir if uninstalling
        cd ..
        rm -rvf "$SHED_LOGDIR" 1>&3 2>&4
    fi
    if ! $VERBOSE; then echo 'done'; fi
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
    echo -n "Shedmake will add the package at $REPOURL to the local repository at ${LOCALREPODIR}/${1}..."
    if $VERBOSE; then echo; fi
    git submodule add -b "$REPOBRANCH" "$REPOURL" 1>&3 2>&4 && \
    git submodule init 1>&3 2>&4 || return 1
    if ! $VERBOSE; then echo 'done'; fi
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
    cd "$REMOTEREPODIR" || return 1
    echo -n "Shedmake will add the repository at $REPOURL to the remote repositories in $REMOTEREPODIR as $REPONAME..."
    if $VERBOSE; then echo; fi
    git clone "$REPOURL" "$REPONAME" 1>&3 2>&4 && \
    cd "$REPONAME" && \
    git checkout "$REPOBRANCH" 1>&3 2>&4 && \
    git submodule init 1>&3 2>&4 && \
    git submodule update 1>&3 2>&4 || return 1
    if ! $VERBOSE; then echo 'done'; fi
}

# Function: shed_download_file
# Description: Downloads a file from a URL to a specified directory
# Arguments:
#     $1 - URL of file to download
#     $2 - Filename to use for download
#     $3 - Directory in which to place the download
shed_download_file () {
    if [ ! -d "$3" ]; then
        mkdir "$3"
    fi
    cd "$3"
    wget -O "$2" "$1" 1>&3 2>&4
}

# Function: shed_verify_file
# Description: Verifies a given file using an md5sum
# Arguments:
#     $1 - Path to file to verify
#     $2 - (Optional) md5sum against which the file will be tested
shed_verify_file () {
    if [ -n "$2" ]; then
        if [[ $(md5sum "$1" | awk '{print $1}') != $2 ]]; then
            return 1
        fi
    elif $VERBOSE; then
        echo 'WARNING: Skipping verification of file because no MD5 was provided.'
    fi
}

shed_fetch_source () {
    if [ -n "$SRC" ]; then
        # Create destination folder if absent
        if [ ! -d "$1" ]; then
            mkdir -p "$1" || return 1
        fi
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            if [ ! -d "${1}/${NAME}-git" ]; then
                if [ -d "${SRCCACHEDIR}/${NAME}-git" ]; then
                    echo -n "Updating source repository for '$NAME'..."
                    if $VERBOSE; then echo; fi
                    cp -R "${SRCCACHEDIR}/${NAME}-git" "$1"
                else
                    echo -n "Fetching source repository for '$NAME'..."
                    if $VERBOSE; then echo; fi
                    mkdir -p "${1}/${NAME}-git"
                    cd "${1}/${NAME}-git"
                    git init 1>&3 2>&4 && \
                    git remote add origin "$SRC" 1>&3 2>&4 || return 1
                fi
            fi
            cd "${1}/${NAME}-git"
            # Perform a shallow fetch of the desired refspec
            local LOCALREPOREF="$(sed -e "s/^refs\/heads\//refs\/remotes\/origin\//g" <<< $REPOREF)"
            git fetch --depth=1 origin +${REPOREF}:${LOCALREPOREF} 1>&3 2>&4 && \
            git checkout --quiet FETCH_HEAD 1>&3 2>&4 || return 1
            if ! $VERBOSE; then echo 'done'; fi
            # TODO: Use signature for verification
        else 
            # Source is an archive
            if [ ! -r "${1}/${SRCFILE}" ]; then
                if [ ! -r "${SRCCACHEDIR}/${SRCFILE}" ]; then
                    echo -n "Fetching source archive for '$NAME'..."
                    if $VERBOSE; then echo; fi
                    shed_download_file "$SRC" "$SRCFILE" "$1"
                    if [ $? -ne 0 ]; then
                        if ! $VERBOSE; then echo; fi
                        echo "Unable to download source archive $SRCFILE"
                        rm "${1}/${SRCFILE}"
                        return 1
                    fi
                    if ! $VERBOSE; then echo 'done'; fi
                else
                    cp "${SRCCACHEDIR}/${SRCFILE}" "$1"
                fi
            fi
            # Verify Source Archive MD5
            shed_verify_file "${1}/${SRCFILE}" "$SRCMD5"
            if [ $? -ne 0 ]; then
                echo "Source archive ${SRCFILE} does not match expected checksum"
                return 1
            fi
        fi
    fi
}

# Returns:
#    20 - Package build permission error
#    21 - Source acquisition error
#    22 - Build script missing error
#    23 - Build failed error
#    24 - Binary archive creation error
shed_build () {
    if $REQUIREROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to build this package."
        return 20
    fi

    # Work directory management
    rm -rf "$WORKDIR"
    mkdir "$WORKDIR"
    export SHED_FAKEROOT="$SHDPKG_FAKEROOT"

    # Source acquisition and unpacking
    shed_fetch_source "$WORKDIR" || return 21
    if $SHOULDCACHESOURCE && [ ! -d "$SRCCACHEDIR" ]; then
        mkdir "$SRCCACHEDIR"
    fi
    cd "$WORKDIR"
    if [ -n "$SRC" ]; then
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            if $SHOULDCACHESOURCE; then
                cp -R "${NAME}-git" "$SRCCACHEDIR"
            fi
        else 
            # Source is an archive or other file
            if $SHOULDCACHESOURCE; then
                cp "$SRCFILE" "$SRCCACHEDIR"
            fi
            # Unarchive Source
            tar xf "$SRCFILE"
        fi
    fi

    # Determine Source Root Dir    
    SRCDIR=$(ls -d */ 2>/dev/null)
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
    mkdir "$SHDPKG_FAKEROOT"
    if [ -a "${SHED_PKGDIR}/build.sh" ]; then
        shed_run_script "${SHED_PKGDIR}/build.sh"
    else
        echo "Missing build script for '$NAME' ($SHED_VERSION_TUPLE)"
        return 22
    fi

    if [ $? -ne 0 ]; then
        echo "Failed to build '$NAME' ($SHED_VERSION_TUPLE)"
        rm -rf "$WORKDIR"
        return 23
    fi
    if ! $VERBOSE; then
        echo 'done'
    else
        echo "Successfully built '$NAME' ($SHED_VERSION_TUPLE)"
    fi

    # Strip Binaries
    if $SHOULDSTRIP ; then
        if ! $VERBOSE; then
            echo -n 'Stripping binaries...'
        else
            echo 'Stripping binaries...'
        fi
        shed_strip_binaries
        if ! $VERBOSE; then
            echo 'done'
        fi
    fi

    # Archive Build Product
    if $SHOULDCACHEBINARY; then
        if [ ! -d "$BINCACHEDIR" ]; then
            mkdir "$BINCACHEDIR"
        fi
        echo -n "Creating binary archive $(shed_binary_archive_name)..."
        tar caf "${BINCACHEDIR}/$(shed_binary_archive_name)" -C "$SHED_FAKEROOT" . || return 24
        echo 'done'
    fi

    # Delete Temporary Files
    cd "$TMPDIR"
    if $SHOULDCLEANTEMP; then
        rm -rf "$WORKDIR"
    fi
}

# $1 - Binary archive directory
shed_fetch_binary () {
    if [ ! -r "${1}/$(shed_binary_archive_name)" ]; then
        if [ -n "$BIN" ]; then
            if [ ! -d "$1" ]; then
                mkdir -p "$1" || return 1
            fi
            # Download from the URL specified by BIN
            local BINURL=$(eval echo "$BIN")
            shed_download_file "$BINURL" "$(shed_binary_archive_name)" "$1"
            # TO-DO download accompanying MD5 file and verify
        else
            echo "No binary archive URL has been supplied for '$NAME'"
        fi
    fi
}

# Returns:
# 20-29 - Build failed error
#    30 - Package install permission error
#    31 - Pre-install script error
#    32 - Install script error
#    33 - Binary archive acquisition error
#    34 - Binary archive extraction error
#    35 - Post-install script error
shed_install () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to install a package."
        return 30
    fi

    # Prepare log directory
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKGDIR" | sed 's|'${SHED_INSTALLROOT%/}'/|/|')
    if [ ! -d "${SHED_LOGDIR}" ]; then
        mkdir "${SHED_LOGDIR}"
    fi

    # Pre-installation
    if [ -a "${SHED_PKGDIR}/preinstall.sh" ]; then
        if $SHOULDPREINSTALL; then
            echo -n "Running pre-install script for '$NAME' ($SHED_VERSION_TUPLE)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                shed_run_script "${SHED_PKGDIR}/preinstall.sh" || return 31
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" preinstall.sh || return 31
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            echo "Skipping the pre-install phase."
        fi
    fi

    # Installation
    if $SHOULDINSTALL; then
        if [ -a "${SHED_PKGDIR}/install.sh" ]; then
            echo -n "Running install script for '$NAME' ($SHED_VERSION_TUPLE)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                shed_run_script "${SHED_PKGDIR}/install.sh" || return 32
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" install.sh || return 32
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            local BINARCHIVE="${BINCACHEDIR}/$(shed_binary_archive_name)"
            if [ ! -d "$SHDPKG_FAKEROOT" ]; then
                # Attempt to download a binary archive
                shed_fetch_binary "$BINCACHEDIR" || return 33
                if [ ! -r "$BINARCHIVE" ]; then
                    # Or, failing that, build it from scratch
                    shedmake build "${SHED_PKGDIR}" "${PARSEDARGS[@]}" --retain-temp
                    local BUILDRETVAL=$?
                    if [ $BUILDRETVAL -ne 0 ]; then
                        echo "Unable to produce or obtain binary archive: $(shed_binary_archive_name)"
                        return $BUILDRETVAL
                    fi
                fi
            fi
            if [ -d "$SHDPKG_FAKEROOT" ]; then
                # Install directly from fakeroot
                echo -n "Installing files from ${SHDPKG_FAKEROOT}..."
                tar cf - -C "$SHDPKG_FAKEROOT" . | tar xvhf - -C "$SHED_INSTALLROOT" > "$SHED_INSTALL_BOM" || return 34
                echo 'done'
            elif [ -r "$BINARCHIVE" ]; then
                # Install from binary archive
                echo -n "Installing files from $(shed_binary_archive_name)..."
                tar xvhf "$BINARCHIVE" -C "$SHED_INSTALLROOT" > "$SHED_INSTALL_BOM" || return 34
                echo 'done'
            else 
                return 33
            fi
        fi
    else
        echo "Skipping the install phase."
    fi

    # Post-installation
    if [ -a "${SHED_PKGDIR}/postinstall.sh" ]; then
        if $SHOULDPOSTINSTALL; then
            echo -n "Running post-install script for '$NAME' ($SHED_VERSION_TUPLE)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALLROOT" == '/' ]; then
                shed_run_script "${SHED_PKGDIR}/postinstall.sh" || return 35
            else
                shed_run_chroot_script "$SHED_INSTALLROOT" "$SHED_CHROOT_PKGDIR" postinstall.sh || return 35
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            echo "Skipping the post-install phase."
        fi
    fi

    # Sort Install Log
    LC_ALL=C sort "$SHED_INSTALL_BOM" -o "$SHED_INSTALL_BOM"

    # Record Installation
    if [ "$SHED_VERSION_TUPLE" != "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        echo "$SHED_VERSION_TUPLE" >> "$SHED_INSTALL_HISTORY"
    fi

    # Purge Old Files
    if $SHOULDPURGE && [ -n "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        shed_purge "$SHED_VERSION_TUPLE" "$SHED_INSTALLED_VERSION_TUPLE"
    fi

    # Delete Temporary Files
    cd "$TMPDIR"
    if $SHOULDCLEANTEMP; then
        rm -rf "$WORKDIR"
    fi

    echo "Successfully installed '$NAME' ($SHED_VERSION_TUPLE)"
}

shed_update_repo_at_path () {
    cd "$1" || return 1
    if [[ $1 =~ ^$REMOTEREPODIR.* ]]; then
        if [[ $EUID -ne 0 ]]; then
            echo 'Root privileges are required to update managed remote package repositories.'
            return 1
        fi
        echo -n "Shedmake will update the remote repository at ${1}..."
        if $VERBOSE; then echo; fi
        git pull 1>&3 2>&4 && \
        git submodule init 1>&3 2>&4 && \
        git submodule update 1>&3 2>&4 || return 1
    else
        if [ -d "${1}/.git" ]; then
            echo -n "Shedmake will update the local repository at ${1}..."
            if $VERBOSE; then echo; fi
            git submodule update --remote 1>&3 2>&4 || return 1
        fi
    fi
    if ! $VERBOSE; then echo 'done'; fi
    shed_repo_status_at_path "$1"
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
    echo -n "Cleaning up cached archives for '$NAME'..."
    if $VERBOSE; then echo; fi
    rm -rfv "$SRCCACHEDIR" 1>&3 2>&4 && \
    rm -rfv "$BINCACHEDIR" 1>&3 2>&4 || return 1
    if ! $VERBOSE; then echo 'done'; fi
}

shed_clean_repo_at_path () {
    echo "Shedmake will clean up cached archives for packages in '$1'..."
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

# Returns:
#    0 - Package is installed and up-to-date
#   10 - Package is installed but update is available
#   11 - Package is available but not installed
shed_package_status () {
    # NOTE: Reserve retval 1 for packages not found in managed repositories
    if [ -n "$SHED_INSTALLED_VERSION_TUPLE" ]; then
        if [ "$SHED_VERSION_TUPLE" == "$SHED_INSTALLED_VERSION_TUPLE" ]; then
            echo "Package '$NAME' is installed and up-to-date ($SHED_INSTALLED_VERSION_TUPLE)"
            return 0
        else
            echo "Package '$NAME' ($SHED_INSTALLED_VERSION_TUPLE) is installed but $SHED_VERSION_TUPLE is available"
            return 10
        fi
    else
        echo "Package '$NAME' ($SHED_VERSION_TUPLE) is available but not installed"
        return 11
    fi
}

shed_repo_status_at_path () {
    local PACKAGE
    local PKGSTATUS
    local -i NUMPKGS=0
    local -i NUMINSTALLED=0
    local -i NUMUPDATES=0
    local PKGSWITHUPDATES=( )
    echo -n "Evaluating packages in the repository at $1..."
    if $VERBOSE; then echo; fi
    for PACKAGE in "${1}"/*; do
        if [ ! -d "$PACKAGE" ]; then
            continue
        fi
        shed_read_package_meta "$PACKAGE" || continue
        shed_package_status 1>&3 2>&4
        PKGSTATUS=$?
        if [ "$PKGSTATUS" -ne 11 ]; then
            ((++NUMINSTALLED))
        fi
        if [ "$PKGSTATUS" -eq 10 ]; then
            ((++NUMUPDATES))
            PKGSWITHUPDATES+=( "'$NAME' ($SHED_INSTALLED_VERSION_TUPLE) -> $SHED_VERSION_TUPLE" )
        fi
        ((++NUMPKGS))
    done
    if ! $VERBOSE; then echo 'done'; fi
    echo "$NUMINSTALLED of $NUMPKGS installed, with $NUMUPDATES update(s) available."
    if ! $VERBOSE && [ ${#PKGSWITHUPDATES[@]} -gt 0 ]; then
        echo 'Packages with available updates:'
        for PACKAGE in "${PKGSWITHUPDATES[@]}"; do
            echo "$PACKAGE"
        done
    fi
}

shed_repo_status () {
    local REPO=$(shed_locate_repo "$1")
    if [ -z "$REPO" ]; then
        shed_print_repo_locate_error "$REPO"
        return 1
    fi
    shed_repo_status_at_path "$REPO"
}

shed_upgrade_repo_at_path () {
    echo "Shedmake is preparing to upgrade packages in the repository at '$1'..."
    local PACKAGE
    local UPGRRETVAL
    for PACKAGE in "${1}"/*; do
        if [ ! -d "$PACKAGE" ]; then
            continue
        fi
        shedmake upgrade "$PACKAGE" "${PARSEDARGS[@]}"
        UPGRRETVAL=$?
        if [ $UPGRRETVAL -ne 0 ] && [ $UPGRRETVAL -ne 11 ]; then
            return $UPGRRETVAL
        fi
    done
    return 0
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
        shed_upgrade_repo "$REPO" || return $?
    done
}

shed_create () {
    local NEWPKGNAME=$(basename "$1")
    echo -n "Shedmake is creating a new package directory for '$NEWPKGNAME'..."
    if $VERBOSE; then echo; fi
    mkdir -v "$1" 1>&3 2>&4 && \
    cd "$1" || return 1
    if [ -n "$REPOURL" ]; then
        git init 1>&3 2>&4 && \
        git remote add origin "$REPOURL" 1>&3 2>&4 || return 1
    fi
    local TEMPLATEFILE
    local TEMPLATEFILENAME
    for TEMPLATEFILE in "${TEMPLATEDIR}"/{.[!.],}*
    do
        cp -v "$TEMPLATEFILE" . 1>&3 2>&4
        TEMPLATEFILENAME=$(basename "$TEMPLATEFILE")
        if [ "$TEMPLATEFILENAME" == 'package.txt' ]; then
            sed -i "s/NAME=.*/NAME=${NEWPKGNAME}/g" "$TEMPLATEFILENAME"
        fi
        if [ -n "$REPOURL" ]; then
            git add "$TEMPLATEFILENAME" 1>&3 2>&4 || return 1
        fi
    done
    if ! $VERBOSE; then echo 'done'; fi
}

shed_create_repo () {
    echo -n "Shedmake is creating a new local package repository '$1'..."
    if $VERBOSE; then echo; fi
    mkdir -v "${LOCALREPODIR}/$1" 1>&3 2>&4 || return 1
    if [ -n "$REPOURL" ]; then
        cd "${LOCALREPODIR}/$1" && \
        git init 1>&3 2>&4 && \
        git remote add origin "$REPOURL" 1>&3 2>&4
    fi
    if ! $VERBOSE; then echo 'done'; fi
}

shed_push () {
    echo -n "Shedmake will push '$1' ($2) to '$REPOBRANCH'..."
    if $VERBOSE; then echo; fi
    push -u origin master && \
    { git checkout "$REPOBRANCH" || git checkout -b "$REPOBRANCH"; } && \
    git merge master && \
    git push -u origin "$REPOBRANCH" && \
    git tag "$2" && \
    git push -u origin --tags
    if ! $VERBOSE; then echo 'done'; fi
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
        shed_load_defaults
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
            local ADDTOREPO="$1"; shift
            shed_parse_args "$@" && \
            shed_add "$ADDTOREPO"
            ;;
        add-repo|add-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_url> [--rename <local_name>] [--branch <repo_branch>]'
                return 1
            fi
            REPOURL="$1"; shift
            shed_parse_args "$@" && \
            shed_add_repo
            ;;
        build|build-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            echo "Shedmake is preparing to build '$NAME' ($SHED_VERSION_TUPLE)..." && \
            shed_resolve_dependencies BUILDDEPS 'build' 'install' 'false' && \
            shed_build
            ;;
        clean|clean-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_clean
            ;;
        clean-repo|clean-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local CLEANREPONAME="$1"; shift
            shed_parse_args "$@" && \
            shed_clean_repo "$CLEANREPONAME"
            ;;
        clean-all)
            shed_parse_args "$@" && \
            shed_clean_all
            ;;
        create|create-list|create-repo|create-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" "<new_package_name> [--origin <repo_url>]"
                return 1
            fi
            local CREATENAME="$1"; shift
            shed_parse_args "$@" || return $?
            case "$SHEDCMD" in
                create|create-list)
                    shed_create "$CREATENAME"
                    ;;
                create-repo|create-repo-list)
                    shed_can_add_repo "$CREATENAME" && \
                    shed_create_repo "$CREATENAME"
                    ;;
            esac
            ;;
        fetch-binary|fetch-binary-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_fetch_binary "$BINCACHEDIR"
            ;;
        fetch-source|fetch-source-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_fetch_source "$SRCCACHEDIR"
            ;;
        info|info-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" && \
            shed_package_info
            ;;
        install|install-list|upgrade|upgrade-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            local PKGSTATUS
            local DEP_CMD_ACTION
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" || return $?
            shed_package_status &>/dev/null
            PKGSTATUS=$?
            case "$SHEDCMD" in
                install|install-list)
                    DEP_CMD_ACTION='install'
                    if [ $PKGSTATUS -eq 0 ] || [ $PKGSTATUS -eq 10 ]; then
                        if ! $FORCEACTION; then
                            echo "Package '$NAME' (${SHED_INSTALLED_VERSION_TUPLE}) is already installed"
                            return 0
                        fi
                    elif [ $PKGSTATUS -ne 11 ]; then
                        return $PKGSTATUS
                    fi
                    ;;
                upgrade|upgrade-list)
                    DEP_CMD_ACTION='upgrade'
                    SHOULDINSTALLDEPS=true
                    if [ $PKGSTATUS -eq 0 ]; then
                        if ! $FORCEACTION; then
                            echo "Latest version of package '$NAME' is already installed (${SHED_INSTALLED_VERSION_TUPLE})"
                            return 0
                        fi
                    elif [ $PKGSTATUS -eq 11 ]; then
                        if [ -n "$DEPENDENCY_OF" ]; then
                            DEP_CMD_ACTION='install'
                        else
                            echo "Package '$NAME' has not been installed"
                            return $PKGSTATUS
                        fi
                    elif [ $PKGSTATUS -ne 10 ]; then
                        return $PKGSTATUS
                    fi
                    ;;
            esac
            case "$DEP_CMD_ACTION" in
                install)
                    echo "Shedmake is preparing to install '$NAME' ($SHED_VERSION_TUPLE) to ${SHED_INSTALLROOT}..."
                    ;;
                upgrade)
                    echo "Shedmake is preparing to upgrade '$NAME' ($SHED_VERSION_TUPLE) on ${SHED_INSTALLROOT}..."
                    ;;
            esac
            shed_resolve_dependencies INSTALLDEPS "$DEP_CMD_ACTION" "$DEP_CMD_ACTION" 'true' && \
            shed_install && \
            shed_resolve_dependencies DEFERREDDEPS 'deferred' "$DEP_CMD_ACTION" 'false' || return $?
            if [ ${#DEFERREDDEPS[@]} -gt 0 ]; then
                echo "Shedmake will re-install '$NAME' ($SHED_VERSION_TUPLE) for deferred dependencies..."
                shed_clean && \
                shed_install || return $?
            fi
            shed_resolve_dependencies RUNDEPS 'runtime' "$DEP_CMD_ACTION" 'false'
            ;;
        purge|purge-list|uninstall|uninstall-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shift && \
            shed_parse_args "$@" || return $?
            if [ -z "$SHED_INSTALLED_VERSION_TUPLE" ]; then
                echo "Package '$NAME' does not appear to be installed"
                return 11
            fi
            local OLDVERSIONTUPLE
            local NEWVERSIONTUPLE
            if [ "$SHEDCMD" == 'purge' ] || [ "$SHEDCMD" == 'purge-list' ]; then
                OLDVERSIONTUPLE="$(tail -n 2 $SHED_INSTALL_HISTORY | head -n 1)"
                NEWVERSIONTUPLE="$SHED_INSTALLED_VERSION_TUPLE"
            else
                OLDVERSIONTUPLE="$SHED_INSTALLED_VERSION_TUPLE"
                NEWVERSIONTUPLE=""
            fi
            shed_purge "$NEWVERSIONTUPLE" "$OLDVERSIONTUPLE"
            ;;
        push|push-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
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
            shed_parse_args "$@" && \
            cd "$REPOPATH" && \
            shed_push_repo "$PUSHREPO"
            ;;
        repo-status|repo-status-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local STATUSREPO="$1"; shift
            shed_parse_args "$@" && \
            shed_repo_status "$STATUSREPO"
            ;;
        status|status-list)
            if [ $# -ne 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name>'
                return 1
            fi
            shed_read_package_meta "$1" && \
            shed_package_status
            ;;
        update-repo|update-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local UPDATEREPO="$1"; shift
            shed_parse_args "$@" && \
            shed_update_repo "$UPDATEREPO"
            ;;
        update-all)
            shed_parse_args "$@" && \
            shed_update_all
            ;;
        upgrade-repo|upgrade-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local UPGRADEREPO="$1"; shift
            shed_parse_args "$@" && \
            shed_upgrade_repo "$UPGRADEREPO"
            ;;
        upgrade-all)
            shed_parse_args "$@" && \
            shed_upgrade_all
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
    shed_load_config || return $?
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
    shed_load_config &&
    shed_command "$@"
fi
