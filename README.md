# nswine

WIP

```
printf '%s\n' '*~' '/autom4te.cache' '/config.log' '/prefix' '/tmp*' '/.cache' > .git/info/exclude
```

```
make clean; autoreconf -f && ./configure --enable-win64 CC="ccache gcc -m64" CXX="ccache g++ -m64" x86_64_CC="ccache x86_64-w64-mingw32-gcc"
make -j$(nproc)
```

```
export WINEPREFIX=$(git rev-parse --show-toplevel)/prefix WINEARCH=win64
./server/wineserver -k; rm -rf $WINEPREFIX; ./wine cmd
```

<!-- TODO: build arm64ec wine, see https://github.com/AndreRH/hangover/blob/master/.packaging/ubuntu2204/wine/debian/rules -->

```
curl -sL https://launchpad.net/~fex-emu/+archive/ubuntu/fex/+files/fex-emu-wine_2506~j_arm64.deb | bsdtar xOf - 'data.tar.*' | bsdtar -C "$WINEPREFIX/drive_c/windows/system32" -s '#.*/##' -xvf - .'**/libarm64ecfex.dll'
```
