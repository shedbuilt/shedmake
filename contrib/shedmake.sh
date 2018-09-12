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
SHEDMAKEVER=1.0.0
CFGFILE=/etc/shedmake.conf

shed_cleanup () {
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        cd "$TMPDIR" || return 1
        rm -rf "$WORKDIR"
    fi
}

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
        SHED_BINARY_ARCHIVE_EXT="tar"
        ;;
    bz2|xz)
        SHED_BINARY_ARCHIVE_EXT="tar.${1}"
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
    LOCAL_REPO_DIR="$(sed -n 's/^LOCAL_REPO_DIR=//p' $CFGFILE)"
    REMOTE_REPO_DIR="$(sed -n 's/^REMOTE_REPO_DIR=//p' $CFGFILE)"
    TEMPLATE_DIR="$(sed -n 's/^TEMPLATE_DIR=//p' $CFGFILE)"
    DEFAULT_COMPRESSION="$(sed -n 's/^COMPRESSION=//p' $CFGFILE)"
    DEFAULT_NUMJOBS="$(sed -n 's/^NUM_JOBS=//p' $CFGFILE)"
    read -ra DEFAULT_OPTIONS <<< $(sed -n 's/^OPTIONS=//p' $CFGFILE)
    export SHED_RELEASE="$(sed -n 's/^RELEASE=//p' $CFGFILE)"
    export SHED_CPU_CORE="$(sed -n 's/^CPU_CORE=//p' $CFGFILE)"
    export SHED_CPU_FEATURES="$(sed -n 's/^CPU_FEATURES=//p' $CFGFILE)"
    export SHED_NATIVE_TARGET="$(sed -n 's/^NATIVE_TARGET=//p' $CFGFILE)"
}

shed_load_defaults () {
    VERBOSE=false
    FORCE_ACTION=false
    SHOULD_CLEAN_TEMP=true
    SHOULD_CACHE_SOURCE=false
    SHOULD_CACHE_BINARY=false
    SHOULD_IGNORE_DEPS=false
    SHOULD_INSTALL_DEPS=false
    SHOULD_PREINSTALL=true
    SHOULD_INSTALL=true
    SHOULD_POSTINSTALL=true
    SHOULD_INSTALL_DEFAULTS=true
    SHOULD_PURGE=false
    SHOULD_STRIP=true
    SHOULD_REQUIRE_ROOT=false
    DEFERRED_DEPS=( )
    REQUESTED_OPTIONS=( "${DEFAULT_OPTIONS[@]}" )
    unset PACKAGE_OPTIONS_MAP
    declare -gA PACKAGE_OPTIONS_MAP
    export SHED_BUILD_TARGET="$SHED_NATIVE_TARGET"
    export SHED_BUILD_HOST="$SHED_NATIVE_TARGET"
    export SHED_INSTALL_ROOT='/'
    export SHED_NUM_JOBS="$DEFAULT_NUMJOBS"
    REPO_BRANCH="$SHED_RELEASE"
    shed_set_binary_archive_compression "$DEFAULT_COMPRESSION"
    shed_set_output_verbosity $VERBOSE
}

shed_binary_archive_name () {
    if [ -n "$BINFILE" ]; then
        eval echo "$BINFILE"
    else
        echo "${SHED_PKG_NAME}_${SHED_PKG_VERSION_TRIPLET}_${SHED_RELEASE}_${SHED_CPU_CORE}_${SHED_CPU_FEATURES}.${SHED_BINARY_ARCHIVE_EXT}"
    fi
}

shed_locate_package () {
    local PKGDIR
    if [ -d "$1" ]; then
        PKGDIR=$(readlink -f -n "$1")
    else
        local REPO
        for REPO in "${REMOTE_REPO_DIR}"/* "${LOCAL_REPO_DIR}"/*; do
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
        echo "$PKGDIR"
    fi
}

shed_locate_repo () {
    local REPODIR
    if [ -d "$1" ]; then
        REPODIR=$(readlink -f -n "$1")
    elif [ -d "${REMOTE_REPO_DIR}/${1}" ]; then
        REPODIR="${REMOTE_REPO_DIR}/${1}"
    elif [ -d "${LOCAL_REPO_DIR}/${1}" ]; then
        REPODIR="${LOCAL_REPO_DIR}/${1}"
    fi
    if [ -z "$REPODIR" ]; then
        return 1
    else
        echo "$REPODIR"
    fi
}

shed_parse_args () {
    PARSEDARGS=( "$@" )
    local OPTION=''
    local OPTVAL=''
    local EXPECT_OPTVAL=false
    while (( $# )); do
        OPTVAL=''
        if [ "${1:0:1}" == '-' ]; then
            if $EXPECT_OPTVAL; then
                echo "Missing argument to option: '$OPTION'"
                return 1
            fi
            OPTION="$1"
        elif [ -n "$OPTION" ]; then
            if $EXPECT_OPTVAL; then
                OPTVAL="$1"
                EXPECT_OPTVAL=false
            else
                echo "Unexpected argument to option: '$OPTION'"
                return 1
            fi
        else
            echo "Invalid argument: '$1'"
            return 1
        fi
        shift

        # Check options with arguments
        if [ -n "$OPTVAL" ]; then
            case "$OPTION" in
                -a|--archive-compression)
                    shed_set_binary_archive_compression "$OPTVAL" || return 1
                    ;;
                -b|--branch)
                    REPO_BRANCH="$OPTVAL"
                    ;;
                -B|--binary-dir)
                    BINCACHEDIR="$OPTVAL"
                    ;;
                -d|--dependency-of)
                    DEPENDENCY_OF="$OPTVAL"
                    ;;
                -h|--host)
                    SHED_BUILD_HOST="$OPTVAL"
                    ;;
                -o|--options)
                    REQUESTED_OPTIONS=( $OPTVAL )
                    ;;
                -p|--purge)
                    if ! SHOULD_PURGE=$(shed_parse_yes_no "$OPTVAL"); then
                        echo "Invalid argument for '$OPTION' Please specify 'yes' or 'no'"
                        return 1
                    fi
                    ;;
                -r|--install-root)
                    SHED_INSTALL_ROOT="$OPTVAL"
                    ;;
                -j|--jobs)
                    SHED_NUM_JOBS="$OPTVAL"
                    ;;
                -n|--rename)
                    REPONAME="$OPTVAL"
                    ;;
                -s|--strip)
                    if ! SHOULD_STRIP=$(shed_parse_yes_no "$OPTVAL"); then
                        echo "Invalid argument for '$OPTION' Please specify 'yes' or 'no'"
                        return 1
                    fi
                    ;;
                -S|--source-dir)
                    SRCCACHEDIR="$OPTVAL"
                    ;;
                -t|--target)
                    SHED_BUILD_TARGET="$OPTVAL"
                    ;;
                -u|--url)
                    REPOURL="$OPTVAL"
                    ;;
                *)
                    echo "Invalid option: '$OPTION'"
                    return 1
                    ;;
            esac
            continue
        fi

        # Check unary options
        case "$OPTION" in
            -c|--cache-source)
                SHOULD_CACHE_SOURCE=true
                ;;
            -C|--cache-binary)
                SHOULD_CACHE_BINARY=true
                ;;
            -D|--skip-defaults-install)
                SHOULD_INSTALL_DEFAULTS=false
                ;;
            -f|--force)
                FORCE_ACTION=true
                ;;
            -I|--ignore-dependencies)
                SHOULD_IGNORE_DEPS=true
                ;;
            -i|--install-dependencies)
                SHOULD_INSTALL_DEPS=true
                ;;
            -k|--skip-preinstall)
                SHOULD_PREINSTALL=false
                ;;
            -K|--skip-postinstall)
                SHOULD_POSTINSTALL=false
                ;;
            -N|--skip-install)
                SHOULD_INSTALL=false
                ;;
            -R|--retain-temp)
                SHOULD_CLEAN_TEMP=false
                ;;
            -v|--verbose)
                VERBOSE=true
                shed_set_output_verbosity $VERBOSE
                ;;
            *)
                if [ $# -gt 0 ]; then
                    # Assume this is an option that takes arguments
                    EXPECT_OPTVAL=true
                else
                    echo "Invalid option: '$OPTION'"
                    return 1
                fi
                ;;
        esac
    done

    if $EXPECT_OPTVAL; then
        echo "Missing argument to option: '$OPTION'"
        return 1
    fi
}

shed_configure_options () {
    declare -A TEMP_PACKAGE_OPTIONS
    declare -A TEMP_SUPPORTED_OPTIONS
    declare -a TEMP_ALIASED_OPTIONS
    declare -a TEMP_SELECTED_OPTIONS
    local OPTION
    local SUBOPTION

    # Populate temporary package options map
    for OPTION in "${DEFAULT_PACKAGE_OPTIONS[@]}"; do
        TEMP_PACKAGE_OPTIONS["$OPTION"]="$OPTION"
    done

    # Process user-chosen options and exclusions
    for OPTION in "${REQUESTED_OPTIONS[@]}"; do
        if [ "${OPTION:0:1}" == '!' ]; then
            unset TEMP_PACKAGE_OPTIONS["${OPTION:1}"]
        else
            TEMP_SELECTED_OPTIONS+=( "$OPTION" )
        fi
    done

    # Append default package options
    for OPTION in "${!TEMP_PACKAGE_OPTIONS[@]}"; do
        TEMP_SELECTED_OPTIONS+=( "$OPTION" )
    done

    # Populate aliased options
    local ALIAS
    for ALIAS in "${ALIASED_PACKAGE_OPTIONS[@]}"; do
        unset ALIASED_OPTIONS_MAP
        declare -A ALIASED_OPTIONS_MAP
        local OPTION_ALIAS=''
        local OPTIONS_TO_ALIAS=''
        local ALIASED_OPTION
        local ALIAS_COMPONENT
        for ALIAS_COMPONENT in ${ALIAS//:/ }; do
            if [ -z "$OPTIONS_TO_ALIAS" ]; then
                OPTIONS_TO_ALIAS=$ALIAS_COMPONENT
            else
                OPTION_ALIAS=$ALIAS_COMPONENT
                for ALIASED_OPTION in ${OPTIONS_TO_ALIAS//|/ }; do
                    ALIASED_OPTIONS_MAP["$ALIASED_OPTION"]="$OPTION_ALIAS"
                done
            fi
        done
        if [ -z "$OPTION_ALIAS" ]; then
            echo "Invalid syntax in aliased package options: '$ALIAS'"
            return 1
        fi
        for OPTION in "${TEMP_SELECTED_OPTIONS[@]}"; do
            if [ -n "${ALIASED_OPTIONS_MAP[$OPTION]}" ]; then
                TEMP_ALIASED_OPTIONS+=( "${ALIASED_OPTIONS_MAP[$OPTION]}" )
            fi
        done
    done

    # Append aliased options
    TEMP_SELECTED_OPTIONS+=( "${TEMP_ALIASED_OPTIONS[@]}" )

    # Populate temporary supported package options map
    for OPTION in "${SUPPORTED_PACKAGE_OPTIONS[@]}"; do
        if [ ${#OPTION} -gt 2 ] && [ "${OPTION:0:1}" == '(' ] && [ "${OPTION: -1}" == ')' ]; then
            OPTION="${OPTION:1:$(expr ${#OPTION} - 2)}"
        fi
        for SUBOPTION in ${OPTION//|/ }; do
            TEMP_SUPPORTED_OPTIONS["$SUBOPTION"]="$OPTION"
        done
    done

    # Intersect desired and supported options
    for OPTION in "${TEMP_SELECTED_OPTIONS[@]}"; do
        local OPTION_VALUE="${TEMP_SUPPORTED_OPTIONS[$OPTION]}"
        local OPTION_TO_ADD="$OPTION"
        if [ -z "$OPTION_VALUE" ]; then
            continue
        fi
        for SUBOPTION in ${OPTION_VALUE//|/ }; do
            if [ -n "${PACKAGE_OPTIONS_MAP[$SUBOPTION]}" ]; then
                OPTION_TO_ADD=''
                break
            fi
        done
        if [ -n "$OPTION_TO_ADD" ]; then
            PACKAGE_OPTIONS_MAP[$OPTION_TO_ADD]=$OPTION_TO_ADD
        fi
    done

    # Validate options
    local OPTION_SATISFIED
    for OPTION in "${SUPPORTED_PACKAGE_OPTIONS[@]}"; do
        if [ ${#OPTION} -gt 2 ] && [ "${OPTION:0:1}" == '(' ] && [ "${OPTION: -1}" == ')' ]; then
            continue
        else
            OPTION_SATISFIED=false
            for SUBOPTION in ${OPTION//|/ }; do
                if [ -n "${PACKAGE_OPTIONS_MAP[$SUBOPTION]}" ]; then
                    OPTION_SATISFIED=true
                    break
                fi
            done
            if ! $OPTION_SATISFIED; then
                echo "Unable to configure build due to missing required option: $OPTION"
                return 1
            fi
        fi
    done

    export SHED_PKG_OPTIONS="${!PACKAGE_OPTIONS_MAP[*]}"
    export SHED_REQUESTED_OPTIONS="${REQUESTED_OPTIONS[*]}"
    export SHED_PKG_OPTIONS_ASSOC="$(declare -p PACKAGE_OPTIONS_MAP | sed -e 's/declare -A \w\+=//')"
    declare -a SORTED_OPTIONS=($(for OPTION in "${!PACKAGE_OPTIONS_MAP[@]}"; do echo $OPTION; done | LC_ALL=C sort))
    local DELIMITED_SORTED_OPTIONS="${SORTED_OPTIONS[*]}"
    if [ -n "$DELIMITED_SORTED_OPTIONS" ]; then
        DELIMITED_SORTED_OPTIONS="${DELIMITED_SORTED_OPTIONS// /-}"
    else
        DELIMITED_SORTED_OPTIONS='none'
    fi
    export SHED_PKG_VERSION_TRIPLET="${SHED_PKG_VERSION}-${SHED_PKG_REVISION}-${DELIMITED_SORTED_OPTIONS}"
}

shed_read_package_meta () {
    export SHED_PKG_DIR=$(shed_locate_package "$1")
    if [ -z "$SHED_PKG_DIR" ]; then
        echo "$1 is not a package directory"
        return 1
    fi

    if [[ $SHED_PKG_DIR =~ ^$REMOTE_REPO_DIR.* ]]; then
        # Actions on packages in managed remote repositories always require root privileges
        SHOULD_REQUIRE_ROOT=true
    fi

    SRCCACHEDIR="${SHED_PKG_DIR}/source"
    BINCACHEDIR="${SHED_PKG_DIR}/binary"
    PKGMETAFILE="${SHED_PKG_DIR}/package.txt"
    export SHED_PKG_PATCH_DIR="${SHED_PKG_DIR}/patch"
    export SHED_PKG_CONTRIB_DIR="${SHED_PKG_DIR}/contrib"
    export SHED_PKG_LOG_DIR="${SHED_PKG_DIR}/install"

    if [ ! -r "$PKGMETAFILE" ]; then
        echo "Cannot read from package.txt in package directory $SHED_PKG_DIR"
        return 1
    fi

    # Package Metadata
    export SHED_PKG_NAME=$(sed -n 's/^NAME=//p' "$PKGMETAFILE")
    export SHED_PKG_VERSION=$(sed -n 's/^VERSION=//p' "$PKGMETAFILE")
    export SHED_PKG_REVISION=$(sed -n 's/^REVISION=//p' "$PKGMETAFILE")
    export SHED_PKG_VERSION_TUPLE="${SHED_PKG_VERSION}-${SHED_PKG_REVISION}"
    WORKDIR="${TMPDIR%/}/${SHED_PKG_NAME}"
    export SHED_FAKE_ROOT="${WORKDIR}/fakeroot"
    SRC=$(sed -n 's/^SRC=//p' "$PKGMETAFILE")
    SRCFILE=$(sed -n 's/^SRCFILE=//p' "$PKGMETAFILE")
    if [ -z "$SRCFILE" ] && [ -n "$SRC" ]; then
        SRCFILE=$(basename $SRC)
    fi
    REPOREF=$(sed -n 's/^REF=//p' "$PKGMETAFILE")
    SRCMD5=$(sed -n 's/^SRCMD5=//p' "$PKGMETAFILE")
    if [ "$(sed -n 's/^STRIP=//p' $PKGMETAFILE)" = 'no' ]; then
        SHOULD_STRIP=false
    fi
    if [ "$(sed -n 's/^PURGE=//p' $PKGMETAFILE)" = 'yes' ]; then
        SHOULD_PURGE=true
    fi
    BIN=$(sed -n 's/^BIN=//p' "$PKGMETAFILE")
    BINFILE=$(sed -n 's/^BINFILE=//p' "$PKGMETAFILE")
    if [ -z "$BINFILE" ] && [ -n "$BIN" ]; then
        BINFILE=$(basename $BIN)
    fi
    read -ra LICENSE <<< $(sed -n 's/^LICENSE=//p' "$PKGMETAFILE")

    # Parse dependencies
    read -ra BUILD_DEPS <<< $(sed -n 's/^BUILDDEPS=//p' "$PKGMETAFILE")
    read -ra INSTALL_DEPS <<< $(sed -n 's/^INSTALLDEPS=//p' "$PKGMETAFILE")
    read -ra RUN_DEPS <<< $(sed -n 's/^RUNDEPS=//p' "$PKGMETAFILE")

    #Parse package options
    read -ra ALIASED_PACKAGE_OPTIONS <<< $(sed -n 's/^ALIASES=//p' "$PKGMETAFILE")
    read -ra SUPPORTED_PACKAGE_OPTIONS <<< $(sed -n 's/^OPTIONS=//p' "$PKGMETAFILE")
    read -ra DEFAULT_PACKAGE_OPTIONS <<< $(sed -n 's/^DEFAULTS=//p' "$PKGMETAFILE")

    export SHED_PKG_DOCS_INSTALL_DIR="/usr/share/doc/${SHED_PKG_NAME}-${SHED_PKG_VERSION}"
    export SHED_PKG_DEFAULTS_INSTALL_DIR="/usr/share/defaults/${SHED_PKG_NAME}"
    export SHED_INSTALL_HISTORY="${SHED_PKG_LOG_DIR}/install.log"
    export SHED_PKG_INSTALLED_VERSION_TRIPLET=''
    if [ -e "$SHED_INSTALL_HISTORY" ]; then
        SHED_PKG_INSTALLED_VERSION_TRIPLET=$(tail -n 1 "$SHED_INSTALL_HISTORY")
    fi
    if [ -z "$SHED_PKG_NAME" ] || [ -z "$SHED_PKG_VERSION" ] || [ -z "$SHED_PKG_REVISION" ]; then
        echo 'Required fields missing from package metadata.'
        return 1
    fi
}

shed_package_info () {
    echo "Shedmake information for package located at $SHED_PKG_DIR..."
    echo "Name:			$SHED_PKG_NAME"
    echo "Version:		$SHED_PKG_VERSION"
    echo "Package Revision:	$SHED_PKG_REVISION"
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
        echo "License(s):		${LICENSE[*]}"
    fi
    if [ -n "$BUILD_DEPS" ]; then
        echo "Build Dependencies:	${BUILD_DEPS[*]}"
    fi
    if [ -n "$INSTALL_DEPS" ]; then
        echo "Install Dependencies:	${INSTALL_DEPS[*]}"
    fi
    if [ -n "$RUN_DEPS" ]; then
        echo "Runtime Dependencies:	${RUN_DEPS[*]}"
    fi
    if [ -n "$SHED_PKG_INSTALLED_VERSION_TRIPLET" ]; then
        echo "Installed Version:	$SHED_PKG_INSTALLED_VERSION_TRIPLET"
    else
        echo "Installed Version:	Not Installed"
    fi
    if $VERBOSE; then
        if [ -d "$SHED_PKG_PATCH_DIR" ]; then
            echo -n "Patches: "
            ls "$SHED_PKG_PATCH_DIR"
        fi
        if [ -d "$SHED_PKG_CONTRIB_DIR" ]; then
            echo -n "Contrib Files: "
            ls "$SHED_PKG_CONTRIB_DIR"
        fi
        if [ -d "$SHED_PKG_LOG_DIR" ]; then
            echo -n "Install Logs: "
            ls "$SHED_PKG_LOG_DIR"
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
    local -n UNPROCESSED_DEPS=$1
    declare -a DEPS
    local DEPTYPE=$2
    local INSTALLACTION=$3
    local CANDEFER=$4
    local DEPACTION='status'
    local DEP
    local DEP_RESOLVE_RETVAL=0
    local DEP_RETVAL=0
    local DEP_TO_ADD
    local DEP_COMPONENT
    if ! $SHOULD_IGNORE_DEPS && [ ${#UNPROCESSED_DEPS[@]} -gt 0 ]; then
        for DEP in "${UNPROCESSED_DEPS[@]}"; do
            DEP_TO_ADD=''
            for DEP_COMPONENT in ${DEP//:/ }; do
                if [ -n "$DEP_TO_ADD" ] && [ -z "${PACKAGE_OPTIONS_MAP[$DEP_TO_ADD]}" ]; then
                    DEP_TO_ADD=''
                    break
                fi
                DEP_TO_ADD=$DEP_COMPONENT
            done
            if [ -n "$DEP_TO_ADD" ]; then
                DEPS+=( "$DEP_TO_ADD" )
            fi
        done
        if $SHOULD_INSTALL_DEPS; then
            DEPACTION="$INSTALLACTION"
        fi
        echo "Resolving $DEPTYPE dependencies for '$SHED_PKG_NAME'..."
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
                    local DEPARGS=( "$DEPACTION" "$DEP" "--dependency-of" "$SHED_PKG_NAME" )
                    for PARSEDARG in "${PARSEDARGS[@]}"; do
                        if $IGNOREARG; then
                            IGNOREARG=false
                            continue
                        fi
                        case "$PARSEDARG" in
                            -D|--dependency-of)
                                IGNOREARG=true
                                ;&
                            -f|--force|-R|--retain-temp)
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
                                DEFERRED_DEPS+=( "$DEP" )
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
    if [ -d "${SHED_FAKE_ROOT}/usr/lib" ]; then
        find "${SHED_FAKE_ROOT}/usr/lib" -type f -name \*.a -exec strip --strip-debug {} ';' 1>&3 2>&4
    fi
    for STRIPFOLDER in "${SHED_FAKE_ROOT}"/lib "${SHED_FAKE_ROOT}"/usr/{,local/}lib
    do
        if [ -d "$STRIPFOLDER" ]; then
            find "$STRIPFOLDER" -type f \( -name \*.so* -a ! -name \*dbg \) -exec strip --strip-unneeded {} ';' 1>&3 2>&4
        fi
    done
    for STRIPFOLDER in "${SHED_FAKE_ROOT}"/{bin,sbin} "${SHED_FAKE_ROOT}"/usr/{,local/}{bin,sbin,libexec}
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
    cd "$SHED_PKG_LOG_DIR"
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
        echo -n "Shedmake will uninstall '$SHED_PKG_NAME' ($OLDVERSION)..."
    elif [ ! -e ${NEWVERSION}.bom ]; then
        echo "Unable to retrieve install log for current version '$NEWVERSION'"
        return 1
    else
        PATHSTODELETE="$(comm -13 ${NEWVERSION}.bom ${OLDVERSION}.bom)"
        echo -n "Shedmake will purge files orphaned when '$SHED_PKG_NAME' was upgraded from $OLDVERSION to $NEWVERSION..."
    fi
    if $VERBOSE; then echo; fi
    local OLDPATH
    local PATHTYPE
    for PATHTYPE in files directories
    do
        while read -ra OLDPATH
        do
            if [ ${#OLDPATH} -gt 2 ] && [[ "${OLDPATH:0:2}" == './' ]]; then
                local INSTALLEDPATH="${SHED_INSTALL_ROOT%/}/${OLDPATH:2}"
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
        rm -rvf "$SHED_PKG_LOG_DIR" 1>&3 2>&4
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
    SHED_RELEASE="$SHED_RELEASE" \
    SHED_BUILD_HOST="$SHED_BUILD_HOST" \
    SHED_BUILD_TARGET="$SHED_BUILD_TARGET" \
    SHED_NATIVE_TARGET="$SHED_NATIVE_TARGET" \
    SHED_INSTALL_ROOT='/' \
    SHED_NUM_JOBS="$SHED_NUM_JOBS" \
    SHED_REQUESTED_OPTIONS="$SHED_REQUESTED_OPTIONS" \
    SHED_PKG_DIR="$2" \
    SHED_PKG_CONTRIB_DIR="${2}/contrib" \
    SHED_PKG_PATCH_DIR="${2}/patch" \
    SHED_PKG_LOG_DIR="${2}/install" \
    SHED_PKG_DOCS_INSTALL_DIR="$SHED_PKG_DOCS_INSTALL_DIR" \
    SHED_PKG_DEFAULTS_INSTALL_DIR="$SHED_PKG_DEFAULTS_INSTALL_DIR" \
    SHED_PKG_NAME="$SHED_PKG_NAME" \
    SHED_PKG_VERSION="$SHED_PKG_VERSION" \
    SHED_PKG_REVISION="$SHED_PKG_REVISION" \
    SHED_PKG_VERSION_TRIPLET="$SHED_PKG_VERSION_TRIPLET" \
    SHED_PKG_OPTIONS="$SHED_PKG_OPTIONS" \
    SHED_PKG_OPTIONS_ASSOC="$SHED_PKG_OPTIONS_ASSOC" \
    SHED_PKG_INSTALL_BOM="${2}/install/${SHED_PKG_VERSION_TRIPLET}.bom" \
    SHED_PKG_INSTALLED_VERSION_TRIPLET="$SHED_PKG_INSTALLED_VERSION_TRIPLET" \
    bash "${2}/${3}" 1>&3 2>&4
}

shed_can_add_repo () {
    if [ -d "${REMOTE_REPO_DIR}/${1}" ]; then
        echo 'A remote repository named '$1' already exists.'
        return 1
    elif [ -d "${LOCAL_REPO_DIR}/${1}" ]; then
        echo 'A local repository named '$1' already exists.'
        return 1
    fi
}

shed_add () {
    local REPOFILE="$(basename $REPOURL)"
    if [ -z "$REPONAME" ]; then
        REPONAME="$(basename $REPOFILE .git)"
    fi
    cd "${LOCAL_REPO_DIR}/${1}" || return 1
    if [ -d "$REPONAME" ]; then
        echo "A directory named '$REPONAME' is already present in local package repository '${1}'"
        return 1
    fi
    echo -n "Shedmake will add the package at $REPOURL to the local repository at ${LOCAL_REPO_DIR}/${1}..."
    if $VERBOSE; then echo; fi
    git submodule add -b "$REPO_BRANCH" "$REPOURL" 1>&3 2>&4 && \
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
    cd "$REMOTE_REPO_DIR" || return 1
    echo -n "Shedmake will add the repository at $REPOURL to the remote repositories in $REMOTE_REPO_DIR as $REPONAME..."
    if $VERBOSE; then echo; fi
    git clone "$REPOURL" "$REPONAME" 1>&3 2>&4 && \
    cd "$REPONAME" && \
    git checkout "$REPO_BRANCH" 1>&3 2>&4 && \
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

# Function: shed_md5sum_of_file
# Description: Prints the md5sum of the file at then given path
# Arguments:
#     $1 - Path to file to hash
# Returns:
#     0 - Successfully printed md5sum
#     1 - Error obtaining md5sum
#     2 - File not found or not readable
shed_md5sum_of_file () {
    if [ -r "$1" ]; then
        echo $(md5sum "$1" | awk '{print $1}')
        if [ $? -ne 0 ]; then
            # Error obtaining md5
            return 1
        fi
    else
        # File not present
        return 2
    fi
}

# Function: shed_verify_file
# Description: Verifies a given file using an md5sum
# Arguments:
#     $1 - Path to file to verify
#     $2 - (Optional) md5sum against which the file will be tested
shed_verify_file () {
    local FILE_MD5SUM
    if [ -n "$2" ]; then
        FILE_MD5SUM=$(shed_md5sum_of_file "$1")
        if [ $? -eq 0 ] && [ "$FILE_MD5SUM" == "$2" ]; then
            return 0
        else
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
            if [ ! -d "${1}/${SHED_PKG_NAME}-git" ]; then
                if [ -d "${SRCCACHEDIR}/${SHED_PKG_NAME}-git" ]; then
                    echo -n "Updating source repository for '$SHED_PKG_NAME'..."
                    if $VERBOSE; then echo; fi
                    cp -R "${SRCCACHEDIR}/${SHED_PKG_NAME}-git" "$1"
                else
                    echo -n "Fetching source repository for '$SHED_PKG_NAME'..."
                    if $VERBOSE; then echo; fi
                    mkdir -p "${1}/${SHED_PKG_NAME}-git"
                    cd "${1}/${SHED_PKG_NAME}-git"
                    git init 1>&3 2>&4 && \
                    git remote add origin "$SRC" 1>&3 2>&4 || return 1
                fi
            fi
            cd "${1}/${SHED_PKG_NAME}-git"
            # Perform a shallow fetch of the desired refspec
            local LOCALREPOREF="$(sed -e "s/^refs\/heads\//refs\/remotes\/origin\//g" <<< $REPOREF)"
            git fetch --depth=1 origin +${REPOREF}:${LOCALREPOREF} 1>&3 2>&4 &&
            git checkout --quiet FETCH_HEAD 1>&3 2>&4 || return 1
            if ! $VERBOSE; then echo 'done'; fi
            # TODO: Use signature for verification
        else
            # Source is an archive
            if [ ! -r "${1}/${SRCFILE}" ]; then
                if [ ! -r "${SRCCACHEDIR}/${SRCFILE}" ]; then
                    echo -n "Fetching source archive for '$SHED_PKG_NAME'..."
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
    if $SHOULD_REQUIRE_ROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to build this package."
        return 20
    fi

    # Work directory management
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"

    # Source acquisition and unpacking
    shed_fetch_source "$WORKDIR" || return 21
    if $SHOULD_CACHE_SOURCE && [ ! -d "$SRCCACHEDIR" ]; then
        mkdir "$SRCCACHEDIR"
    fi
    cd "$WORKDIR"
    if [ -n "$SRC" ]; then
        if [ "${SRC: -4}" = '.git' ]; then
            # Source is a git repository
            if $SHOULD_CACHE_SOURCE; then
                cp -R "${SHED_PKG_NAME}-git" "$SRCCACHEDIR"
            fi
        else
            # Source is an archive or other file
            if $SHOULD_CACHE_SOURCE; then
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
            export SHED_PKG_SOURCE_DIR="${WORKDIR}/${SRCDIR}"
            cd "$SRCDIR"
        else
            export SHED_PKG_SOURCE_DIR="$WORKDIR"
        fi
    else
        export SHED_PKG_SOURCE_DIR="$WORKDIR"
    fi

    # Build Source
    if ! $VERBOSE; then
        echo -n "Building '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)..."
    fi

    mkdir "$SHED_FAKE_ROOT"
    if [ -a "${SHED_PKG_DIR}/build.sh" ]; then
        shed_run_script "${SHED_PKG_DIR}/build.sh"
    else
        echo "Missing build script for '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)"
        return 22
    fi

    if [ $? -ne 0 ]; then
        echo "Failed to build '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)"
        rm -rf "$WORKDIR"
        return 23
    fi
    if ! $VERBOSE; then
        echo 'done'
    else
        echo "Successfully built '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)"
    fi

    # Strip Binaries
    if $SHOULD_STRIP ; then
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
    if $SHOULD_CACHE_BINARY; then
        if [ ! -d "$BINCACHEDIR" ]; then
            mkdir "$BINCACHEDIR"
        fi
        echo -n "Creating binary archive $(shed_binary_archive_name)..."
        tar caf "${BINCACHEDIR}/$(shed_binary_archive_name)" -C "$SHED_FAKE_ROOT" . || return 24
        echo 'done'
    fi

    # Delete Temporary Files
    if $SHOULD_CLEAN_TEMP; then
        shed_cleanup
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
            echo "No binary archive URL has been supplied for '$SHED_PKG_NAME'"
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
#    35 - Default configuration file installation error
#    36 - Post-install script error
shed_install () {
    if [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to install a package."
        return 30
    fi

    # Prepare log directory
    SHED_CHROOT_PKGDIR=$(echo "$SHED_PKG_DIR" | sed 's|'${SHED_INSTALL_ROOT%/}'/|/|')
    if [ ! -d "${SHED_PKG_LOG_DIR}" ]; then
        mkdir "${SHED_PKG_LOG_DIR}"
    fi
    export SHED_PKG_INSTALL_BOM="${SHED_PKG_LOG_DIR}/${SHED_PKG_VERSION_TRIPLET}.bom"

    # Pre-installation
    if [ -a "${SHED_PKG_DIR}/preinstall.sh" ]; then
        if $SHOULD_PREINSTALL; then
            echo -n "Running pre-install script for '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALL_ROOT" == '/' ]; then
                shed_run_script "${SHED_PKG_DIR}/preinstall.sh" || return 31
            else
                shed_run_chroot_script "$SHED_INSTALL_ROOT" "$SHED_CHROOT_PKGDIR" preinstall.sh || return 31
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            echo "Skipping the pre-install phase."
        fi
    fi

    # Installation
    if $SHOULD_INSTALL; then
        if [ -a "${SHED_PKG_DIR}/install.sh" ]; then
            echo -n "Running install script for '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALL_ROOT" == '/' ]; then
                shed_run_script "${SHED_PKG_DIR}/install.sh" || return 32
            else
                shed_run_chroot_script "$SHED_INSTALL_ROOT" "$SHED_CHROOT_PKGDIR" install.sh || return 32
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            local BINARCHIVE="${BINCACHEDIR}/$(shed_binary_archive_name)"
            if [ ! -d "$SHED_FAKE_ROOT" ]; then
                # Attempt to download a binary archive
                shed_fetch_binary "$BINCACHEDIR" || return 33
                if [ ! -r "$BINARCHIVE" ]; then
                    # Or, failing that, build it from scratch
                    shedmake build "${SHED_PKG_DIR}" "${PARSEDARGS[@]}" --retain-temp
                    local BUILDRETVAL=$?
                    if [ $BUILDRETVAL -ne 0 ]; then
                        echo "Unable to produce or obtain binary archive: $(shed_binary_archive_name)"
                        return $BUILDRETVAL
                    fi
                fi
            fi
            if [ -d "$SHED_FAKE_ROOT" ]; then
                # Install directly from fakeroot
                echo -n "Installing files from ${SHED_FAKE_ROOT}..."
                tar cf - -C "$SHED_FAKE_ROOT" . | tar xvhf - -C "$SHED_INSTALL_ROOT" > "$SHED_PKG_INSTALL_BOM" || return 34
                echo 'done'
            elif [ -r "$BINARCHIVE" ]; then
                # Install from binary archive
                echo -n "Installing files from $(shed_binary_archive_name)..."
                tar xvhf "$BINARCHIVE" -C "$SHED_INSTALL_ROOT" > "$SHED_PKG_INSTALL_BOM" || return 34
                echo 'done'
            else
                return 33
            fi
        fi
        # Install default configuration files
        if $SHOULD_INSTALL_DEFAULTS; then
            shed_install_defaults || return 35
        fi
    else
        echo "Skipping the install phase."
    fi

    # Post-installation
    if [ -a "${SHED_PKG_DIR}/postinstall.sh" ]; then
        if $SHOULD_POSTINSTALL; then
            echo -n "Running post-install script for '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)..."
            if $VERBOSE; then echo; fi
            if [ "$SHED_INSTALL_ROOT" == '/' ]; then
                shed_run_script "${SHED_PKG_DIR}/postinstall.sh" || return 36
            else
                shed_run_chroot_script "$SHED_INSTALL_ROOT" "$SHED_CHROOT_PKGDIR" postinstall.sh || return 36
            fi
            if ! $VERBOSE; then echo 'done'; fi
        else
            echo "Skipping the post-install phase."
        fi
    fi

    # Sort Install Log
    LC_ALL=C sort "$SHED_PKG_INSTALL_BOM" -o "$SHED_PKG_INSTALL_BOM"

    # Record Installation
    if [ "$SHED_PKG_VERSION_TRIPLET" != "$SHED_PKG_INSTALLED_VERSION_TRIPLET" ]; then
        echo "$SHED_PKG_VERSION_TRIPLET" >> "$SHED_INSTALL_HISTORY"
    fi

    # Purge Old Files
    if $SHOULD_PURGE && [ -n "$SHED_PKG_INSTALLED_VERSION_TRIPLET" ]; then
        shed_purge "$SHED_PKG_VERSION_TRIPLET" "$SHED_PKG_INSTALLED_VERSION_TRIPLET"
    fi

    # Delete Temporary Files
    if $SHOULD_CLEAN_TEMP; then
        shed_cleanup
    fi

    echo "Successfully installed '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)"
}

shed_install_defaults () {
    # Catalogue available default files
    local DEFAULT_FILE
    local FILE_MD5SUM
    local DEFAULTS_LOG_FILE="${SHED_PKG_LOG_DIR}/defaults.log"
    declare -A DEFAULT_FILES_MAP
    if [ -d "${SHED_INSTALL_ROOT%/}${SHED_PKG_DEFAULTS_INSTALL_DIR}" ]; then
        cd "${SHED_INSTALL_ROOT%/}${SHED_PKG_DEFAULTS_INSTALL_DIR}"
        shopt -s globstar nullglob dotglob
        for DEFAULT_FILE in **; do
            if [ -d "$DEFAULT_FILE" ]; then
                continue
            fi
            FILE_MD5SUM=$(shed_md5sum_of_file "$DEFAULT_FILE")
            if [ $? -eq 0 ]; then
                DEFAULT_FILES_MAP["$DEFAULT_FILE"]="$FILE_MD5SUM"
            else
                echo "Unable to produce md5sum for '$DEFAULT_FILE'"
            fi
        done
        shopt -u globstar nullglob dotglob
    fi
    # echo "Available Defaults: $(declare -p DEFAULT_FILES_MAP | sed -e 's/declare -A \w\+=//')"

    if [ ${#DEFAULT_FILES_MAP[@]} -gt 0 ]; then
        echo -n "Installing default configuration files..."
        if $VERBOSE; then echo; fi
    else
        return 0
    fi

    # Load recorded defaults
    declare -A RECORDED_DEFAULTS_MAP
    if [ -r "$DEFAULTS_LOG_FILE" ]; then
        while read -ra INSTALLED_DEFAULT
        do
            if [ ${#INSTALLED_DEFAULT[@]} -ne 2 ]; then
                echo "Unable to parse installed default: $INSTALLED_DEFAULT"
                continue
            fi
            RECORDED_DEFAULTS_MAP["${INSTALLED_DEFAULT[0]}"]="${INSTALLED_DEFAULT[1]}"
        done < "$DEFAULTS_LOG_FILE"
    fi
    # echo "Recorded Defaults: $(declare -p RECORDED_DEFAULTS_MAP | sed -e 's/declare -A \w\+=//')"

    # Iterate through available default files
    for DEFAULT_FILE in "${!DEFAULT_FILES_MAP[@]}"; do
        # For each, see if there's a corresponding file on disk
        FILE_MD5SUM="$(shed_md5sum_of_file ${SHED_INSTALL_ROOT%/}/${DEFAULT_FILE})"
        if [ $? -eq 1 ]; then
            # Exit on errors other than missing file
            echo "Error checking md5sum of potentially installed default file at: '${SHED_INSTALL_ROOT%/}/${DEFAULT_FILE}'"
            return 1
        fi
        if [ "${RECORDED_DEFAULTS_MAP[$DEFAULT_FILE]}" != "$FILE_MD5SUM" ]; then
            # If the hashes don't match, don't install the file
            if $VERBOSE; then
                echo "Avoiding overwriting configuration file '$DEFAULT_FILE' with md5sum '${FILE_MD5SUM}' with default version with md5sum '${DEFAULT_FILES_MAP["$DEFAULT_FILE"]}' due to mismatch with recorded md5sum '${RECORDED_DEFAULTS_MAP[$DEFAULT_FILE]}'"
            fi
            continue
        fi
        # Install the file if necessary (or forced) and update our installed defaults map with its md5sum
        local DEFAULT_TO_INSTALL="${SHED_INSTALL_ROOT%/}${SHED_PKG_DEFAULTS_INSTALL_DIR}/${DEFAULT_FILE}"
        local FILE_PERMISSIONS
        FILE_PERMISSIONS=$(stat -c "%a" "$DEFAULT_TO_INSTALL") &&
        install -vDm${FILE_PERMISSIONS} "$DEFAULT_TO_INSTALL" "${SHED_INSTALL_ROOT%/}/${DEFAULT_FILE}" 1>&3 2>&4 &&
        RECORDED_DEFAULTS_MAP["$DEFAULT_FILE"]="${DEFAULT_FILES_MAP["$DEFAULT_FILE"]}" || return 1
    done
    # Write out the updated defaults.bom
    if [ -e "$DEFAULTS_LOG_FILE" ]; then
        rm "$DEFAULTS_LOG_FILE"
    fi
    for DEFAULT_FILE in "${!RECORDED_DEFAULTS_MAP[@]}"; do
        echo "$DEFAULT_FILE ${RECORDED_DEFAULTS_MAP["$DEFAULT_FILE"]}" >> "$DEFAULTS_LOG_FILE"
    done
    if ! $VERBOSE; then echo 'done'; fi
}

shed_update_repo_at_path () {
    cd "$1" || return 1
    if [[ $1 =~ ^$REMOTE_REPO_DIR.* ]]; then
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
    for REPO in "${REMOTE_REPO_DIR}"/* "${LOCAL_REPO_DIR}"/*; do
        shed_update_repo_at_path "$REPO" || return 1
    done
}

shed_clean () {
    if $SHOULD_REQUIRE_ROOT && [[ $EUID -ne 0 ]]; then
        echo "Root privileges are required to clean this package."
        return 1
    fi
    echo -n "Cleaning up cached archives for '$SHED_PKG_NAME'..."
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
    for REPO in "${REMOTE_REPO_DIR}"/* "${LOCAL_REPO_DIR}"/*; do
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
    if [ -n "$SHED_PKG_INSTALLED_VERSION_TRIPLET" ]; then
        local VERSION_TRIPLET_PREFIX="${SHED_PKG_VERSION_TUPLE}-"
        if [ "${SHED_PKG_INSTALLED_VERSION_TRIPLET:0:${#VERSION_TRIPLET_PREFIX}}" == "$VERSION_TRIPLET_PREFIX" ]; then
            echo "Package '$SHED_PKG_NAME' is installed and up-to-date ($SHED_PKG_INSTALLED_VERSION_TRIPLET)"
            return 0
        else
            echo "Package '$SHED_PKG_NAME' $SHED_PKG_INSTALLED_VERSION_TRIPLET is installed but $SHED_PKG_VERSION_TUPLE is available"
            return 10
        fi
    else
        echo "Package '$SHED_PKG_NAME' $SHED_PKG_VERSION_TUPLE is available but not installed"
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
        shed_read_package_meta "$PACKAGE" || return 1
        shed_package_status 1>&3 2>&4
        PKGSTATUS=$?
        if [ "$PKGSTATUS" -ne 11 ]; then
            ((++NUMINSTALLED))
        fi
        if [ "$PKGSTATUS" -eq 10 ]; then
            ((++NUMUPDATES))
            PKGSWITHUPDATES+=( "'$SHED_PKG_NAME' ($SHED_PKG_INSTALLED_VERSION_TRIPLET) -> $SHED_PKG_VERSION_TUPLE" )
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
    for REPO in "${REMOTE_REPO_DIR}"/* "${LOCAL_REPO_DIR}"/*; do
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
    for TEMPLATEFILE in "${TEMPLATE_DIR}"/{.[!.],}*
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
    mkdir -v "${LOCAL_REPO_DIR}/$1" 1>&3 2>&4 || return 1
    if [ -n "$REPOURL" ]; then
        cd "${LOCAL_REPO_DIR}/$1" && \
        git init 1>&3 2>&4 && \
        git remote add origin "$REPOURL" 1>&3 2>&4
    fi
    if ! $VERBOSE; then echo 'done'; fi
}

shed_push () {
    echo -n "Shedmake will push '$1' ($2) to '$REPO_BRANCH'..."
    if $VERBOSE; then echo; fi
    push -u origin master && \
    { git checkout "$REPO_BRANCH" || git checkout -b "$REPO_BRANCH"; } && \
    git merge master && \
    git push -u origin "$REPO_BRANCH" && \
    git tag "$2" && \
    git push -u origin --tags
    if ! $VERBOSE; then echo 'done'; fi
}

shed_push_package () {
    shed_push "$1" "${SHED_PKG_VERSION}-${SHED_RELEASE}-${SHED_PKG_REVISION}"
}

shed_push_repo () {
    local NEWTAG
    local LASTTAG="$(git describe --tags)"
    if [ -n "$LASTTAG" ]; then
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
            shed_parse_args "$@" &&
            shed_add "$ADDTOREPO"
            ;;
        add-repo|add-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_url> [--rename <local_name>] [--branch <repo_branch>]'
                return 1
            fi
            REPOURL="$1"; shift
            shed_parse_args "$@" &&
            shed_add_repo
            ;;
        build|build-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_configure_options &&
            echo "Shedmake is preparing to build '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET)..." &&
            shed_resolve_dependencies BUILD_DEPS 'build' 'install' 'false' &&
            shed_build
            ;;
        clean|clean-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_clean
            ;;
        clean-repo|clean-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local CLEANREPONAME="$1"; shift
            shed_parse_args "$@" &&
            shed_clean_repo "$CLEANREPONAME"
            ;;
        clean-all)
            shed_parse_args "$@" &&
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
                    shed_can_add_repo "$CREATENAME" &&
                    shed_create_repo "$CREATENAME"
                    ;;
            esac
            ;;
        fetch-binary|fetch-binary-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_fetch_binary "$BINCACHEDIR"
            ;;
        fetch-source|fetch-source-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_fetch_source "$SRCCACHEDIR"
            ;;
        info|info-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_package_info
            ;;
        install|install-list|upgrade|upgrade-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            local PKGSTATUS
            local DEP_CMD_ACTION
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            shed_configure_options || return $?
            shed_package_status &>/dev/null
            PKGSTATUS=$?
            case "$SHEDCMD" in
                install|install-list)
                    DEP_CMD_ACTION='install'
                    if [ $PKGSTATUS -eq 0 ] || [ $PKGSTATUS -eq 10 ]; then
                        if ! $FORCE_ACTION; then
                            echo "Package '$SHED_PKG_NAME' is already installed (${SHED_PKG_INSTALLED_VERSION_TRIPLET})"
                            return 0
                        fi
                    elif [ $PKGSTATUS -ne 11 ]; then
                        return $PKGSTATUS
                    fi
                    ;;
                upgrade|upgrade-list)
                    DEP_CMD_ACTION='upgrade'
                    SHOULD_INSTALL_DEPS=true
                    if [ $PKGSTATUS -eq 0 ]; then
                        if ! $FORCE_ACTION; then
                            echo "Latest version of package '$SHED_PKG_NAME' is already installed (${SHED_PKG_INSTALLED_VERSION_TRIPLET})"
                            return 0
                        fi
                    elif [ $PKGSTATUS -eq 11 ]; then
                        if [ -n "$DEPENDENCY_OF" ]; then
                            DEP_CMD_ACTION='install'
                        else
                            echo "Package '$SHED_PKG_NAME' has not been installed"
                            return $PKGSTATUS
                        fi
                    elif [ $PKGSTATUS -ne 10 ]; then
                        return $PKGSTATUS
                    fi
                    ;;
            esac
            echo "Shedmake is preparing to $DEP_CMD_ACTION '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET) on ${SHED_INSTALL_ROOT}..."
            shed_resolve_dependencies INSTALL_DEPS "$DEP_CMD_ACTION" "$DEP_CMD_ACTION" 'true' &&
            shed_install &&
            shed_resolve_dependencies DEFERRED_DEPS 'deferred' "$DEP_CMD_ACTION" 'false' || return $?
            if [ ${#DEFERRED_DEPS[@]} -gt 0 ]; then
                echo "Shedmake will re-install '$SHED_PKG_NAME' ($SHED_PKG_VERSION_TRIPLET) for deferred dependencies..."
                shed_clean &&
                shed_install || return $?
            fi
            shed_resolve_dependencies RUN_DEPS 'runtime' "$DEP_CMD_ACTION" 'false'
            ;;
        purge|purge-list|uninstall|uninstall-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" || return $?
            if [ -z "$SHED_PKG_INSTALLED_VERSION_TRIPLET" ]; then
                echo "Package '$SHED_PKG_NAME' does not appear to be installed"
                return 11
            fi
            local OLDVERSIONTUPLE
            local NEWVERSIONTUPLE
            if [ "$SHEDCMD" == 'purge' ] || [ "$SHEDCMD" == 'purge-list' ]; then
                OLDVERSIONTUPLE="$(tail -n 2 $SHED_INSTALL_HISTORY | head -n 1)"
                NEWVERSIONTUPLE="$SHED_PKG_INSTALLED_VERSION_TRIPLET"
            else
                OLDVERSIONTUPLE="$SHED_PKG_INSTALLED_VERSION_TRIPLET"
                NEWVERSIONTUPLE=""
            fi
            shed_purge "$NEWVERSIONTUPLE" "$OLDVERSIONTUPLE"
            ;;
        push|push-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name> [<options>]'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shift &&
            shed_parse_args "$@" &&
            cd "$SHED_PKG_DIR" &&
            shed_push_package "$SHED_PKG_NAME"
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
            shed_parse_args "$@" &&
            cd "$REPOPATH" &&
            shed_push_repo "$PUSHREPO"
            ;;
        repo-status|repo-status-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local STATUSREPO="$1"; shift
            shed_parse_args "$@" &&
            shed_repo_status "$STATUSREPO"
            ;;
        status|status-list)
            if [ $# -ne 1 ]; then
                shed_print_args_error "$SHEDCMD" '<package_name>'
                return 1
            fi
            shed_read_package_meta "$1" &&
            shed_package_status
            ;;
        update-repo|update-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local UPDATEREPO="$1"; shift
            shed_parse_args "$@" &&
            shed_update_repo "$UPDATEREPO"
            ;;
        update-all)
            shed_parse_args "$@" &&
            shed_update_all
            ;;
        upgrade-repo|upgrade-repo-list)
            if [ $# -lt 1 ]; then
                shed_print_args_error "$SHEDCMD" '<repo_name> [<options>]'
                return 1
            fi
            local UPGRADEREPO="$1"; shift
            shed_parse_args "$@" &&
            shed_upgrade_repo "$UPGRADEREPO"
            ;;
        upgrade-all)
            shed_parse_args "$@" &&
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

# Trap signals
trap shed_cleanup SIGINT SIGTERM

# Check for -list action prefix
if [ $# -gt 0 ] && [ "${1: -5}" = '-list' ]; then
    if [ $# -lt 2 ]; then
        echo "Too few arguments to list-based action. Expected: shedmake <list-action> <list-file> [<options>] ..."
        exit 1
    elif [ ! -r "$2" ]; then
        echo "Unable to read from list file: '$2'"
        exit 1
    fi
    shed_load_config || return $?
    SHED_LIST_CMD_RETVAL=0
    SHED_LIST_WD="$(pwd)"
    SHED_LIST_CMD="$1"; shift
    SHED_LIST_FILE=$(readlink -f -n "$1"); shift
    while read -ra SHED_LIST_ARGS
    do
        if [[ "$SHED_LIST_ARGS" =~ ^#.* ]]; then
            continue
        fi
        SHED_LIST_CMD_ARGS=( "$SHED_LIST_CMD" ${SHED_LIST_ARGS[@]} "$@" )
        shed_command "${SHED_LIST_CMD_ARGS[@]}"
        SHED_LIST_CMD_RETVAL=$?
        if [ $SHED_LIST_CMD_RETVAL -ne 0 ]; then
            echo "Aborting remaining list commands due to error: $SHED_LIST_CMD_RETVAL"
            exit 1
        fi
        cd "$SHED_LIST_WD" || exit 1
    done < "$SHED_LIST_FILE"
else
    shed_load_config &&
    shed_command "$@"
fi
