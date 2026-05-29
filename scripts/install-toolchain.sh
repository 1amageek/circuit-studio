#!/usr/bin/env bash
# Install (or detect) the signoff toolchain — Magic, Netgen, ngspice, Sky130 PDK —
# and export MAGIC_BIN / NETGEN_BIN / PDK_ROOT so the gated real-tool tests run.
#
# Idempotent: existing installs under ~/.local/{magic,netgen} and ~/.volare are
# reused. OS-aware (macOS via Homebrew, Linux via apt). Used by both local devs
# and CI; in CI it appends the env vars to $GITHUB_ENV.
#
# Usage:  source scripts/install-toolchain.sh    (to get the env in your shell)
#    or:  ./scripts/install-toolchain.sh          (prints `export` lines)
set -euo pipefail

PREFIX="${TOOLCHAIN_PREFIX:-$HOME/.local}"
SRC="${TOOLCHAIN_SRC:-$HOME/src}"
SKY130_HASH="${SKY130_HASH:-c6d73a35f524070e85faff4a6a9eef49553ebc2b}"
OS="$(uname -s)"

log() { printf '[toolchain] %s\n' "$*" >&2; }

install_prereqs() {
    if [ "$OS" = "Darwin" ]; then
        brew install tcl-tk tcl-tk@8 gnu-sed libx11 ngspice >/dev/null 2>&1 || true
    else
        sudo apt-get update -y >/dev/null
        sudo apt-get install -y --no-install-recommends \
            build-essential m4 git \
            tcl-dev tk-dev tcl8.6-dev tk8.6-dev \
            libx11-dev libcairo2-dev libncurses-dev zlib1g-dev \
            ngspice python3-pip >/dev/null
    fi
}

build_magic() {
    if [ -x "$PREFIX/magic/bin/magic" ]; then log "magic present"; return; fi
    log "building magic"
    git clone --depth 1 https://github.com/RTimothyEdwards/magic "$SRC/magic" 2>/dev/null || true
    cd "$SRC/magic"
    if [ "$OS" = "Darwin" ]; then
        export SDKROOT="$(xcrun --show-sdk-path)"
        export CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)"
        ./configure --prefix="$PREFIX/magic" --without-x \
            --with-tcl=/opt/homebrew/opt/tcl-tk/lib --with-tk=/opt/homebrew/opt/tcl-tk/lib >/dev/null
        sed -i 's#^SED *= .*#SED = /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed#' defs.mak
    else
        ./configure --prefix="$PREFIX/magic" >/dev/null
    fi
    make >/dev/null 2>&1     # serial: Magic Makefiles race under -j
    make install >/dev/null
    cd - >/dev/null
}

build_netgen() {
    if [ -x "$PREFIX/netgen/bin/netgen" ]; then log "netgen present"; return; fi
    log "building netgen"
    git clone --depth 1 https://github.com/RTimothyEdwards/netgen "$SRC/netgen" 2>/dev/null || true
    cd "$SRC/netgen"
    export CFLAGS="-Wno-error=implicit-function-declaration"
    if [ "$OS" = "Darwin" ]; then
        export SDKROOT="$(xcrun --show-sdk-path)"
        export CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)"
        P8="$(brew --prefix tcl-tk@8)"; X="$(brew --prefix libx11)"
        ./configure --prefix="$PREFIX/netgen" \
            --x-includes="$X/include" --x-libraries="$X/lib" \
            --with-tcl="$P8/lib" --with-tk="$P8/lib" \
            --with-tclincls="$P8/include/tcl-tk" --with-tkincls="$P8/include/tcl-tk" \
            --with-tcllibs="$P8/lib" --with-tklibs="$P8/lib" >/dev/null
    else
        # Linux ships GNU sed and Tcl 8.6 dev headers; X11 via libx11-dev.
        ./configure --prefix="$PREFIX/netgen" \
            --with-tcl=/usr/lib --with-tk=/usr/lib >/dev/null
    fi
    make >/dev/null 2>&1
    make install >/dev/null
    cd - >/dev/null
}

install_pdk() {
    local versions="$HOME/.volare/volare/sky130/versions"
    if [ -d "$versions/$SKY130_HASH/sky130A" ]; then log "sky130 PDK present"; return; fi
    log "fetching sky130 PDK"
    pip3 install --quiet --user volare >/dev/null 2>&1 || pip3 install --quiet volare >/dev/null
    "$(python3 -m site --user-base)/bin/volare" enable --pdk sky130 "$SKY130_HASH" >/dev/null 2>&1 \
        || volare enable --pdk sky130 "$SKY130_HASH" >/dev/null
}

mkdir -p "$SRC"
install_prereqs
build_magic
build_netgen
install_pdk

MAGIC_BIN="$PREFIX/magic/bin/magic"
NETGEN_BIN="$PREFIX/netgen/bin/netgen"
PDK_ROOT="$HOME/.volare/volare/sky130/versions/$SKY130_HASH"

if [ -n "${GITHUB_ENV:-}" ]; then
    { echo "MAGIC_BIN=$MAGIC_BIN"; echo "NETGEN_BIN=$NETGEN_BIN"; echo "PDK_ROOT=$PDK_ROOT"; } >> "$GITHUB_ENV"
    log "exported MAGIC_BIN/NETGEN_BIN/PDK_ROOT to GITHUB_ENV"
fi
echo "export MAGIC_BIN=$MAGIC_BIN"
echo "export NETGEN_BIN=$NETGEN_BIN"
echo "export PDK_ROOT=$PDK_ROOT"
