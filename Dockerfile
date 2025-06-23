FROM --platform=amd64 debian:12

ARG LLVM_MINGW_VERSION=20250613
ARG FEX_VERSION=2506

RUN dpkg --add-architecture arm64
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl libarchive-tools \
        python3 \
        make automake autoconf m4 flex bison pkg-config libtool gettext \
        binutils gcc \
        binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu \
        linux-libc-dev libc-devtools linux-headers-amd64 \
        linux-libc-dev-arm64-cross \
        libfreetype6-dev:amd64 libgnutls28-dev:amd64 libunwind-dev:amd64 libfontconfig1-dev:amd64 \
        libfreetype6-dev:arm64 libgnutls28-dev:arm64 libunwind-dev:arm64 libfontconfig1-dev:arm64

RUN mkdir /opt/llvm-mingw && curl -sL https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/llvm-mingw-$LLVM_MINGW_VERSION-ucrt-ubuntu-22.04-x86_64.tar.xz | bsdtar -C /opt/llvm-mingw --strip-components=1 -xf -
ENV PATH="/opt/llvm-mingw/bin:$PATH"

WORKDIR /opt/nswine/src
COPY --link ./ /opt/nswine/src/
RUN autoreconf -fi

WORKDIR /opt/nswine/src/amd64
RUN mkdir /opt/nswine/amd64 && ../configure --prefix /opt/nswine/amd64 --with-mingw=clang --disable-tests --host=x86_64-linux-gnu host_alias=x86_64-linux-gnu build_alias=x86_64-linux-gnu --enable-win64 CC='clang -target x86_64-linux-gnu' && make -j `nproc` && make install

WORKDIR /opt/nswine/src/arm64
RUN mkdir /opt/nswine/arm64 && ../configure --prefix /opt/nswine/arm64 --with-mingw=clang --disable-tests --host=aarch64-linux-gnu host_alias=aarch64-linux-gnu build_alias=x86_64-linux-gnu --enable-archs=arm64ec,aarch64 --with-wine-tools=../amd64 CC='clang -target aarch64-linux-gnu' && make -j `nproc` && make install

WORKDIR /opt/nswine/amd64
RUN WINEPREFIX=/opt/nswine/amd64/prefix ./bin/wine wineboot --init && WINEPREFIX=/opt/nswine/amd64/prefix ./bin/wineserver -w && rm -rf ./prefix/include ./share/man ./share/applications ./lib/wine/*/*.a

# note: this requires binfmt aarch64 support (docker run --privileged --rm tonistiigi/binfmt --install arm64)
WORKDIR /opt/nswine/arm64
RUN WINEPREFIX=/opt/nswine/arm64/prefix ./bin/wine64 wineboot --init && WINEPREFIX=/opt/nswine/arm64/prefix ./bin/wineserver -w && rm -rf ./prefix/include ./share/man ./share/applications ./lib/wine/*/*.a
RUN curl -sL https://launchpad.net/~fex-emu/+archive/ubuntu/fex/+files/fex-emu-wine_$FEX_VERSION~j_arm64.deb | bsdtar xOf - 'data.tar.*' | bsdtar -C ./prefix/drive_c/windows/system32 -s '#.*/##' -xvf - '**/libarm64ecfex.dll'

# TODO: nswrap, remove headers and static libs, lib rpath? (otherwise libunwind, libgnutls, and libfreetype will be required on the host), wineprefix cleanup (extra files, dedup, disable auto-update, etc)
# TODO: build fex?
