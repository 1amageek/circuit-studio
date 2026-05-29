# Signoff Toolchain (Magic + Netgen + Sky130)

circuit-studio's real signoff path (`LiveSignoffService` → `MagicDRCSignoff`,
`NetgenLVSSignoff`, `MagicLayoutExtractor`) shells out to the open-source EDA
tools below. The integration tests that exercise it are **gated**: they call
`*.locate()` and skip when the toolchain is absent, so the suite stays green on
machines without it. Install the toolchain to run them for real.

```
LiveSignoffServiceTests, MagicDRCSignoffTests, NetgenLVSSignoffTests,
RealSignoffPEXEndToEndTests   ← skipped unless Magic + Netgen + Sky130 are present
```

## What you need

| Tool | Used for | Discovery (override) |
|---|---|---|
| Magic 8.3 | DRC, LVS-netlist extraction (`ext2spice`) | `~/.local/magic/bin/magic` (`MAGIC_BIN`) |
| Netgen 1.5 | LVS comparison | `~/.local/netgen/bin/netgen` (`NETGEN_BIN`) |
| Sky130 PDK (volare) | rules, setup, device matching | `~/.volare/volare/sky130/versions/<hash>` (`PDK_ROOT`) |

## macOS (Apple Silicon) build recipe

Headless tools — **no XQuartz required**. Common prerequisites:

```sh
brew install tcl-tk tcl-tk@8 gnu-sed libx11
export SDKROOT="$(xcrun --show-sdk-path)"     # else configure: "ld: library 'System' not found"
```

### Magic (Tcl 9)

```sh
git clone https://github.com/RTimothyEdwards/magic ~/src/magic && cd ~/src/magic
# defs.mak uses GNU `sed -i`; point SED at gsed:
CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)" \
  ./configure --prefix="$HOME/.local/magic" --without-x \
  --with-tcl=/opt/homebrew/opt/tcl-tk/lib --with-tk=/opt/homebrew/opt/tcl-tk/lib
sed -i 's#^SED *= .*#SED = /opt/homebrew/opt/gnu-sed/libexec/gnubin/sed#' defs.mak
make            # serial — the Makefiles race under -j on generated headers
make install
```

### Netgen (Tcl 8.6 — uses APIs removed in Tcl 9)

```sh
git clone https://github.com/RTimothyEdwards/netgen ~/src/netgen && cd ~/src/netgen
P8="$(brew --prefix tcl-tk@8)"; X="$(brew --prefix libx11)"
CC="$(xcrun -f clang)" CXX="$(xcrun -f clang++)" \
CFLAGS="-Wno-error=implicit-function-declaration" \
  ./configure --prefix="$HOME/.local/netgen" \
  --x-includes="$X/include" --x-libraries="$X/lib" \
  --with-tcl="$P8/lib" --with-tk="$P8/lib" \
  --with-tclincls="$P8/include/tcl-tk" --with-tkincls="$P8/include/tcl-tk" \
  --with-tcllibs="$P8/lib" --with-tklibs="$P8/lib"
make && make install
```

Gotchas: Netgen needs X11 headers to enable its Tcl build (`libx11` satisfies the
`AC_PATH_XTRA` check without XQuartz); it must build against **Tcl 8.6** because
`netgenexec.c` uses `Tcl_SetVar`/`Tcl_StaticPackage`, removed in Tcl 9 (Magic, by
contrast, builds fine against Tcl 9).

### Sky130 PDK

```sh
pip3 install volare
volare enable --pdk sky130 <build-hash>   # installs ~/.volare/volare/sky130/versions/<hash>
```

## Verify

```sh
echo 'quit -noprompt' | ~/.local/magic/bin/magic -dnull -noconsole   # prints "Magic 8.3 ..."
printf 'puts ok\nquit\n' | ~/.local/netgen/bin/netgen -batch          # prints "Netgen 1.5 ..."
swift test --filter LiveSignoffServiceTests                            # now runs for real
```
