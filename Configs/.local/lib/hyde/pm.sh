#!/usr/bin/env sh

# This is a modified version of Copied from https://github.com/jpikl/pm?tab=MIT-1-ov-file
# This will become a core lib for HyDE to resolve package manager dependencies

# Contributor Notice:
# 1. Feel free to optimize this script
# 2. Feel free to rewrite this script into a compiled as long as we have a speed improvement
# 3. Feel free to add more package managers
# 4. Feel free to add more package manager commands

# HyDE Notice:
# We are using this script via ` hyde-shell pm <command> <package> `

# MIT License

# Copyright (c) 2023 Jan Pikl

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# shellcheck disable=SC2064

set -eu

export LC_ALL=C

usage() {
    echo "Package manager wrapper (supports: $PMS)"
    echo
    echo "Usage: $0 <command>"
    echo
    echo "Commands:"
    echo "  i,  install          Interactively select packages to install."
    echo "  i,  install <pkg>... Install one or more packages."
    echo "  r,  remove           Interactively select packages to remove."
    echo "  r,  remove <pkg>...  Remove one or more packages."
    echo "  u,  upgrade          Upgrade all installed packages."
    echo "  f,  fetch            Update local package database."
    echo "  n,  info <pkg>       Print package information."
    echo "  la, list all         List all packages."
    echo "  li, list installed   List installed packages."
    echo "  sa  search all       Interactively search between all packages."
    echo "  si  search installed Interactively search between installed packages."
    echo "  w,  which            Print which package manager is being used."
    echo "  h,  help             Print this help."
    echo "  pq,  query <pkg>     Check if a package is installed."
    echo "  fq, file-query <file> Query the package owning a specific file."
    echo "  cu, count-updates    Print the number of package needed to be updated."
    echo ""
    echo "Flags:"
    echo "  --pm <name>          Force package manager to use."
    echo
    echo "Interactive commands can read additional filters from standard input."
    echo "Each line is a regular expression (POSIX extended), matching whole package name."
}

main() {
    FORCE_PM=""
    if [ $# -gt 1 ] && [ "$1" = "--pm" ]; then
        FORCE_PM=$2
        shift 2
    fi

    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <command> argument"
    fi

    if [ "$1" = h ] || [ "$1" = -h ] || [ "$1" = help ] || [ "$1" = --help ]; then
        usage
        exit
    fi

    if [ ! "${PM_COLOR-}" ]; then
        if [ -t 1 ]; then
            PM_COLOR="always"
        else
            PM_COLOR="never"
        fi
    fi

    # Output formatting
    if [ "$PM_COLOR" = always ]; then
        FMT_NAME='"\033[1m"'
        FMT_GROUP='" \033[1;35m"'
        FMT_VERSION='" \033[1;36m"'
        FMT_STATUS='" \033[1;32m"'
        FMT_RESET='"\033[0m"'
    else
        FMT_NAME='""'
        FMT_GROUP='" "'
        FMT_VERSION='" "'
        FMT_STATUS='" "'
        FMT_RESET='""'
    fi

    if [ -n "$FORCE_PM" ]; then
        PM=$FORCE_PM
        if ! is_command "$PM"; then
            die "forced package manager '$PM' is not available"
        fi
    else
        pm_detect
    fi

    PM_CACHE_DIR=${XDG_CACHE_DIR:-$HOME/.cache}/pm/$PM
    mkdir -p "$PM_CACHE_DIR"

    COMMAND=$1
    shift

    case "$COMMAND" in
    i | install) install "$@" ;;
    u | upgrade) upgrade ;;
    r | remove) remove "$@" ;;
    n | info) info "$@" ;;
    l | list) list "$@" ;;
    li) list installed ;;
    la) list all ;;
    s | search) search "$@" ;;
    si) search installed ;;
    sa) search all ;;
    f | fetch) fetch ;;
    w | which) which ;;
    pq | query) is_installed "$@" ;;
    fq | file-query) file_query "$@" ;;
    *) die_wrong_usage "invalid <command> argument '$COMMAND'" ;;
    esac
}

# =============================================================================
# Source Lib
# =============================================================================

source "./pm-lib.sh"

# =============================================================================
# Run
# =============================================================================

main "$@"
