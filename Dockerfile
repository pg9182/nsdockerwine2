# syntax=docker/dockerfile:1

# go version
ARG GO="1.24.2"

# wine version
ARG WINE="10.6"

# hangover version
ARG HANGOVER="1"

# debian version
ARG DEBIAN="12"
ARG DEBIAN_CODENAME="bookworm"

# nswine options
ARG NSWINEOPT="-optimize -vendor"

# note: the dependency list will need to be updated manually if wine changes
# TODO: finish this
# TODO: automate this somehow or maybe just install the entire package
ARG NSWINESYSDEP="libunwind8 libgnutls30"

# note: you'll need qemu-binfmt-static (and if you get "no such file or directory", your qemu is dynamically linked)

# the go image contains go, ca-certificates, git, gcc, etc, and is based on
# debian, so it's a good base image... we can always swap it out later
FROM golang:${GO}-${DEBIAN_CODENAME} AS toolchain-host
FROM --platform=amd64 golang:${GO}-${DEBIAN_CODENAME} AS toolchain-amd64
FROM --platform=arm64 golang:${GO}-${DEBIAN_CODENAME} AS toolchain-arm64

# build nswine for amd64
FROM toolchain-host AS nswinebuild-amd64
COPY --link ./nswine /src
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -C /src -o /nswine .

# build nswine for arm64
FROM toolchain-host AS nswinebuild-arm64
COPY --link ./nswine /src
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -C /src -o /nswine .

# collect nswine artifacts
FROM scratch AS nswinebuild
COPY --link --from=nswinebuild-amd64 /nswine /amd64/nswine
COPY --link --from=nswinebuild-arm64 /nswine /arm64/nswine

# download wine for amd64
FROM toolchain-host AS wine-amd64
ARG WINE
ARG DEBIAN_CODENAME
ARG MIRROR
RUN wget --quiet --show-progress --progress=bar:force:noscroll \
    https://dl.winehq.org/wine-builds/debian/dists/${DEBIAN_CODENAME}/main/binary-amd64/winehq-devel_${WINE}~${DEBIAN_CODENAME}-1_amd64.deb \
    https://dl.winehq.org/wine-builds/debian/dists/${DEBIAN_CODENAME}/main/binary-amd64/wine-devel_${WINE}~${DEBIAN_CODENAME}-1_amd64.deb \
    https://dl.winehq.org/wine-builds/debian/dists/${DEBIAN_CODENAME}/main/binary-amd64/wine-devel-amd64_${WINE}~${DEBIAN_CODENAME}-1_amd64.deb
RUN for x in *.deb; do dpkg-deb -x "$x" /wine; done

# download wine for arm64
FROM toolchain-host AS wine-arm64
ARG WINE
ARG HANGOVER
ARG DEBIAN
ARG DEBIAN_CODENAME
ARG MIRROR
RUN wget --quiet --show-progress --progress=bar:force:noscroll \
    https://github.com/AndreRH/hangover/releases/download/hangover-${WINE}${HANGOVER:+.}${HANGOVER}/hangover_${WINE}${HANGOVER:+.}${HANGOVER}_debian${DEBIAN}_${DEBIAN_CODENAME}_arm64.tar
RUN tar xvf hangover_${WINE}${HANGOVER:+.}${HANGOVER}_debian${DEBIAN}_${DEBIAN_CODENAME}_arm64.tar
RUN for x in *.deb; do dpkg-deb -x "$x" /wine; done

# collect wine artifacts (useful for development)
# docker buildx build --progress plain --target wine --output build/wine .
FROM scratch AS wine
COPY --link --from=wine-amd64 /wine /amd64
COPY --link --from=wine-arm64 /wine /arm64

# build wine runtime on amd64 (binfmt)
FROM toolchain-amd64 AS nswine-amd64
COPY --link --from=nswinebuild-amd64 /nswine /usr/local/bin/nswine
COPY --link --from=wine-amd64 /wine /wine
ARG NSWINESYSDEP
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${NSWINESYSDEP}
ARG NSWINEOPT
RUN nswine -prefix=/wine/opt/wine-devel -output=/opt/northstar-runtime ${NSWINEOPT}

# build wine runtime on arm64 (binfmt)
FROM toolchain-arm64 AS nswine-arm64
COPY --link --from=nswinebuild-arm64 /nswine /usr/local/bin/nswine
COPY --link --from=wine-arm64 /wine /wine
ARG NSWINESYSDEP
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ${NSWINESYSDEP}
ARG NSWINEOPT
RUN nswine -prefix=/wine/usr -output=/opt/northstar-runtime ${NSWINEOPT}

# collect wine runtime artifacts (useful for development)
# docker buildx build --progress plain --target nswine --output build/nswine .
FROM scratch AS nswine
COPY --link --from=nswine-amd64 /opt/northstar-runtime /amd64
COPY --link --from=nswine-arm64 /opt/northstar-runtime /arm64

# build nswrap on amd64 (binfmt)
FROM toolchain-amd64 AS nswrap-amd64
COPY --link ./nswrap /src
RUN mkdir /opt/northstar-runtime && gcc-12 -Wall -Wextra /src/nswrap.c -o /opt/northstar-runtime/nswrap

# build nswrap on arm64 (binfmt)
FROM toolchain-arm64 AS nswrap-arm64
COPY --link ./nswrap /src
RUN mkdir /opt/northstar-runtime && gcc-12 -Wall -Wextra /src/nswrap.c -o /opt/northstar-runtime/nswrap

# collect nswrap artifacts (useful for development)
# docker buildx build --progress plain --target nswine --output build/nswrap .
FROM scratch AS nswrap
COPY --link --from=nswrap-amd64 /opt/northstar-runtime/nswrap /amd64/nswrap
COPY --link --from=nswrap-arm64 /opt/northstar-runtime/nswrap /arm64/nswrap

# assemble runtime for amd64
FROM scratch AS runtime-amd64
COPY --link --from=nswine-amd64 /opt/northstar-runtime /opt/northstar-runtime
COPY --link --from=nswrap-amd64 /opt/northstar-runtime/nswrap /opt/northstar-runtime/nswrap

# assemble runtime for arm64
FROM scratch AS runtime-arm64
COPY --link --from=nswine-arm64 /opt/northstar-runtime /opt/northstar-runtime
COPY --link --from=nswrap-arm64 /opt/northstar-runtime/nswrap /opt/northstar-runtime/nswrap

# collect runtime artifacts
# docker buildx build --progress plain --target runtime --output build/runtime .
FROM scratch AS runtime
COPY --link --from=runtime-amd64 /opt/northstar-runtime /amd64
COPY --link --from=runtime-arm64 /opt/northstar-runtime /arm64
