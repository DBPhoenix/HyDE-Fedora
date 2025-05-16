# =============================================================================
# Commands
# =============================================================================

install() {
    if [ ! -f "$PM_CACHE_DIR/last-fetch" ] || [ "$(cat "$PM_CACHE_DIR/last-fetch")" != "$(current_date)" ]; then
        pm_fetch
    fi
    if [ $# -eq 0 ]; then
        search all | PM=$PM PM_COLOR=$PM_COLOR xargs_self install
    else
        pm_install "$@"
    fi
}

remove() {
    if [ $# -eq 0 ]; then
        search installed | PM=$PM PM_COLOR=$PM_COLOR xargs_self remove
    else
        pm_remove "$@"
    fi
}

upgrade() {
    pm_fetch
    pm_upgrade
}

fetch() {
    pm_fetch
}

info() {
    pm_info "$1"
}

list() {
    check_source "$@"
    pm_list "$1" | pm_format "$1"
}

search() {
    check_source "$@"

    if [ -t 0 ]; then
        pm_list "$1" | pm_format "$1" | interactive_filter
    else
        FILTER_FILE=$(mktemp)
        trap "rm -f -- '$FILTER_FILE'" EXIT
        compile_stdin_filter >"$FILTER_FILE"
        pm_list "$1" | grep -Ef "$FILTER_FILE" | pm_format "$1" | interactive_filter
    fi
}

which() {
    echo "$PM"
}

is_installed() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <pkg> argument"
    fi
    if command -v "${PM}_is_installed" >/dev/null 2>&1; then
        "${PM}_is_installed" "$1"
    else
        die "is-installed command is not supported for package manager '$PM'"
    fi
}

file_query() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <file> argument"
    fi
    if command -v "${PM}_file_query" >/dev/null 2>&1; then
        "${PM}_file_query" "$1"
    else
        die "file-query command is not supported for package manager '$PM'"
    fi
}

# =============================================================================
# Utils
# =============================================================================

die() {
    echo >&2 "$0: $1"
    exit 1
}

die_wrong_usage() {
    die "$1, run '$0 help' for usage"
}

is_command() {
    [ -x "$(command -v "$1")" ]
}

current_date() {
    date -u +%Y-%m-%d
}

check_source() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <source> argument"
    elif [ "$1" != installed ] && [ "$1" != all ]; then
        die_wrong_usage "invalid <source> argument '$1'"
    fi
}

compile_stdin_filter() {
    # 1. Remove comments '#...'
    # 2. Trim lines
    # 3. Remove empty lines
    # 4. Insert matching context ("start of line" ... "end of line" or "whitespace")
    sed -E 's/#.*//;s/^\s+//;s/\s+$//' |
        { grep . || die "empty stdin filter"; } |
        awk '{ print "^" $1 "($|\\s)" }'
}

interactive_filter() {
    if is_command fzf; then
        fzf --exit-0 \
            --multi \
            --no-sort \
            --ansi \
            --layout=reverse \
            --exact \
            --cycle \
            --preview="PM=$PM PM_COLOR=$PM_COLOR $0 info {1}" |
            cut -d" " -f1
    else
        die "fzf is not available, run '$0 install fzf' first"
    fi
}

skip_table_header() {
    while read -r LINE; do
        case "$LINE" in
        --*) cat ;;
        esac
    done
}

xargs_self() {
    # Some older xargs implementations (busybox < 1.36) do not support `-o` option to reopen /dev/tty as stdin.
    # This is a workaround suggested by `man xargs`.
    # shellcheck disable=SC2016
    xargs -r sh -c '"$0" "$@" </dev/tty' "$0" "$@"
}

# =============================================================================
# PM wrapper
# =============================================================================

# Package managers are detected in this order
PMS="paru yay pacman apt dnf zypper apk brew scoop flatpak"

pm_detect() {
    if [ ! "${PM-}" ]; then
        for NAME in $PMS; do
            if is_command "$NAME"; then
                PM=$NAME
                break
            fi
        done
        if [ ! "${PM-}" ]; then
            die "no supported package manager found ($PMS)"
        fi
    fi
}

pm_install() {
    "${PM}_install" "$@"
}

pm_remove() {
    "${PM}_remove" "$@"
}

pm_upgrade() {
    "${PM}_upgrade"
}

pm_fetch() {
    "${PM}_fetch"
    current_date >"$PM_CACHE_DIR/last-fetch"
}

pm_info() {
    "${PM}_info" "$1"
}

pm_list() {
    "${PM}_list_$1"
}

pm_format() {
    "${PM}_format_$1"
}

# =============================================================================
# Pacman
# =============================================================================

pacman_install() {
    for PKG in "$@"; do
        if aur_helpers_contain "$PKG"; then
            # Custom install procedure for AUR helpers
            aur_helpers_install "$PKG"
            # Re-run the installation for the remaining packages (should use the installed helper as PM)
            printf "%s\n" "$@" | grep -Fv "$PKG" | xargs_self install
            return
        fi
    done
    sudo pacman -S --needed "$@"
}

pacman_remove() {
    sudo pacman -Rsc "$@"
}

pacman_upgrade() {
    sudo pacman -Su
}

pacman_fetch() {
    sudo pacman -Sy
}

pacman_info() {
    if aur_helpers_contain "$1"; then
        aur_helpers_info "$1"
    else
        pacman -Si --color="$PM_COLOR" "$1"
    fi
}

pacman_list_all() {
    pacman -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
    aur_helpers_list
}

pacman_list_installed() {
    pacman -Q --color=never
}

pacman_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

pacman_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

pacman_is_installed() {
    pacman -Q "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

pacman_file_query() {
    pacman -F "$1"
}

# =============================================================================
# AUR helpers
# =============================================================================

AUR_HELPERS="paru paru-bin yay yay-bin"

aur_helpers_contain() {
    for NAME in $AUR_HELPERS; do
        if [ "$1" = "$NAME" ]; then
            return 0
        fi
    done
    return 1
}

aur_helpers_install() {
    sudo pacman -S --needed git base-devel
    AUR_DIR=$(mktemp -d)
    trap "rm -rf -- '$AUR_DIR'" EXIT
    git clone "https://aur.archlinux.org/$1.git" "$AUR_DIR"
    cd "$AUR_DIR"
    makepkg -si
}

aur_helpers_info() {
    printf "\e[1mRepository  :\e[0m aur\n"
    printf "\e[1mName        :\e[0m %s\n" "$1"
    printf "\e[1mDescription :\e[0m AUR helper\n"
}

aur_helpers_list() {
    # shellcheck disable=SC2086
    printf "%s aur\n" $AUR_HELPERS
}

# =============================================================================
# Paru
# =============================================================================

paru_install() {
    paru -S --needed "$@"
}

paru_remove() {
    paru -Rsc "$@"
}

paru_upgrade() {
    paru -Su
}

paru_fetch() {
    paru -Sy
}

paru_info() {
    paru -Si --color="$PM_COLOR" "$1"
}

paru_list_all() {
    paru -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

paru_list_installed() {
    paru -Q --color=never
}

paru_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

paru_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

paru_is_installed() {
    paru -Q "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

paru_file_query() {
    paru -F -- "$1"
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    yay -S --needed "$@"
}

yay_remove() {
    yay -Rsc "$@"
}

yay_upgrade() {
    yay -Su
}

yay_fetch() {
    yay -Sy
}

yay_info() {
    yay -Si --color="$PM_COLOR" "$1"
}

yay_list_all() {
    # We want non-AUR results first and pacman is also much faster than yay here.
    {
        pacman -Sl --color=never
        yay -Sla --color=never
    } | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

yay_list_installed() {
    yay -Q --color=never
}

yay_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

yay_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

yay_is_installed() {
    yay -Q "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

yay_file_query() {
    yay -F -- "$1"
}

# =============================================================================
# Apt
# =============================================================================

apt_install() {
    sudo apt install "$@"
}

apt_remove() {
    sudo apt remove "$@"
}

apt_upgrade() {
    sudo apt upgrade
}

apt_fetch() {
    sudo apt update
}

apt_info() {
    # Using `apt show` is not recommended due to unstable CLI
    apt-cache show "$1"
}

apt_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dpkg-query --show -f '${package} [installed]\n' >"$INSTALLED_PKGS_FILE"
    apt-cache pkgnames | sort | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

apt_list_installed() {
    dpkg-query --show
}

apt_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_STATUS \$2 $FMT_RESET }"
}

apt_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

apt_is_installed() {
    dpkg -l "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

apt_file_query() {
    apt-file search "$1"
}

# =============================================================================
# Dnf
# =============================================================================

dnf_install() {
    sudo dnf install "$@"
}

dnf_remove() {
    sudo dnf remove "$@"
}

dnf_fetch() {
    # dnf exists with code 100 in distrobox https://github.com/fedora-cloud/docker-brew-fedora/issues/46
    sudo dnf check-update || true
}

dnf_upgrade() {
    sudo dnf upgrade
}

dnf_info() {
    # Skip the first header line
    dnf info -q --color="$PM_COLOR" "$1" | grep :
}

dnf_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dnf repoquery -q --installed --qf '%{name} [installed]' >"$INSTALLED_PKGS_FILE"
    dnf repoquery -q --qf='%{name} %{repoid} %{evr}' | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

dnf_list_installed() {
    dnf repoquery -q --installed --qf '%{name} %{evr}'
}

dnf_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

dnf_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

dnf_is_installed() {
    rpm -q "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

dnf_file_query() {
    dnf provides "$1"
}

# =============================================================================
# Zypper
# =============================================================================

zypper_install() {
    # Confirmation after interactive package selection does not work (user input from stdin is not read)
    sudo zypper install --no-confirm "$@"
}

zypper_remove() {
    # Confirmation after interactive package selection does not work (user input from stdin is not read)
    sudo zypper remove --no-confirm "$@"
}

zypper_fetch() {
    sudo zypper refresh
}

zypper_upgrade() {
    sudo zypper update
}

zypper_info() {
    zypper info "$1" | skip_table_header
}

zypper_list_all() {
    zypper packages --sort-by-name | skip_table_header | awk 'BEGIN { FS = "|" } ; { if (substr($1, 0, 1) == "i") print $3 $2 $4 "[installed]"; else print $3 $2 $4 }'
}

zypper_list_installed() {
    # Filter out duplicated entries with alternate version available (lines starting with 'v' status)
    zypper packages --sort-by-name --installed-only | skip_table_header | grep -v '^v' | awk 'BEGIN { FS = "|" } ; { print $3 $2 $4 }'
}

zypper_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

zypper_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

zypper_is_installed() {
    zypper se --installed-only "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

zypper_file_query() {
    zypper se --provides "$1"
}

# =============================================================================
# APK
# =============================================================================

apk_install() {
    sudo apk add "$@"
}

apk_remove() {
    sudo apk del "$@"
}

apk_fetch() {
    sudo apk update
}

apk_upgrade() {
    sudo apk upgrade
}

apk_info() {
    apk info "$1"
}

apk_list_all() {
    # First `sed` splits the version from package name `zlib-1.3.1-r0` -> `zlib 1.3.1-r0`
    # Seconds `sed` removes license `(...)` like `(BSD-3-Clause AND Apache-2.0 AND MIT)` to get rid of problematic whitespaces
    apk list --available | sed -E 's/-(\d)/ \1/;s/\([^)]+\)//' | awk '{ print $1 " " $4 " " $2 " " $5 }'
}

apk_list_installed() {
    # `sed` splits the version from package name `zlib-1.3.1-r0` -> `zlib 1.3.1-r0`
    apk list --installed | sed -E 's/-(\d)/ \1/' | awk '{ print $1 " " $4 " " $2 }'
}

apk_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

apk_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

apk_is_installed() {
    apk info "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

apk_file_query() {
    apk info --who-owns "$1"
}

# =============================================================================
# Brew
# =============================================================================

brew_install() {
    brew install "$@"
}

brew_remove() {
    brew uninstall "$@"
}

brew_fetch() {
    brew update
}

brew_upgrade() {
    brew upgrade
}

brew_info() {
    [ "$PM_COLOR" = always ] && export HOMEBREW_COLOR=1
    brew info "$1"
}

brew_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    brew list -1 | awk '{ print $1 " [installed]" }' >"$INSTALLED_PKGS_FILE"
    {
        brew formulae
        [ "$(uname -s)" = Darwin ] && brew casks
    } | grep . | sort -u | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

brew_list_installed() {
    brew list -1
}

brew_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_STATUS \$2 $FMT_RESET }"
}

brew_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_RESET }"
}

brew_is_installed() {
    brew list --formula "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

brew_file_query() {
    echo "file-query is not supported for Homebrew" >&2
    exit 1
}

# =============================================================================
# Scoop
# =============================================================================

scoop_install() {
    scoop install "$@"
}

scoop_remove() {
    scoop uninstall "$@"
}

scoop_fetch() {
    # Scoop search is very slow (especialy with multiple buckets) so we do create our own cache
    echo >&2 "Fetching packages..."
    scoop search | skip_table_header | grep . | awk '{ print $1 " " $3 " " $2 }' | sort >"$PM_CACHE_DIR/packages"
}

scoop_upgrade() {
    scoop update
}

scoop_info() {
    scoop info "$1" | grep .
}

scoop_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    scoop list | skip_table_header | grep . | awk '{ print $1 " [installed]" }' >"$INSTALLED_PKGS_FILE"
    [ -f "$PM_CACHE_DIR/packages" ] || scoop_fetch
    join -j1 -a1 "$PM_CACHE_DIR/packages" "$INSTALLED_PKGS_FILE"

}

scoop_list_installed() {
    scoop list | skip_table_header | grep . | awk '{ print $1 " " $3 " " $2 }'
}

scoop_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

scoop_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

scoop_is_installed() {
    scoop list "$1" >/dev/null 2>&1 && echo "Installed" || { echo "Not installed" && return 1; }
}

scoop_file_query() {
    echo "file-query is not supported for Scoop" >&2
    exit 1
}

# =============================================================================
# Flatpak
# =============================================================================

flatpak_install() {
    flatpak install -y "$@"
}

flatpak_remove() {
    flatpak uninstall -y "$@"
}

flatpak_fetch() {
    flatpak update --appstream
}

flatpak_upgrade() {
    flatpak update -y
}

flatpak_info() {
    flatpak info "$1"
}

flatpak_list_all() {
    flatpak remote-ls --columns=name,application,version
}

flatpak_list_installed() {
    flatpak list --columns=name,application,version
}

flatpak_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

flatpak_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

flatpak_is_installed() {
    flatpak list --columns=application | grep -q "^$1$" && echo "Installed" || { echo "Not installed" && return 1; }
}

flatpak_file_query() {
    echo "file-query is not supported for Flatpak" >&2
    exit 1
}

# =============================================================================
# Detect Package Manager
# =============================================================================

pm_detect
