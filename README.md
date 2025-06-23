# nswine

WIP

Testing changes quickly:

```bash
# prep
printf '%s\n' '*~' '/autom4te.cache' '/config.log' '/prefix' '/tmp*' '/.cache' > .git/info/exclude

# rebuilding
make clean
autoreconf -f
./configure --enable-win64 CC="ccache gcc -m64" CXX="ccache g++ -m64" x86_64_CC="ccache x86_64-w64-mingw32-gcc"
make -j$(nproc)

# running wine
export WINEPREFIX=$(git rev-parse --show-toplevel)/prefix WINEARCH=win64
./server/wineserver -k
rm -rf $WINEPREFIX
./wine cmd

# resetting ccache
ccache -C
```
