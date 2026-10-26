# Official stable n8n, with only the separately vulnerable OS Brotli package
# replaced. Node, n8n, native modules, helpers and runtime configuration remain
# upstream's. This artifact is validated for linux/amd64.
FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a AS package-tools
RUN apk add --no-cache apk-tools-static brotli=1.2.1-r0
ADD --checksum=sha256:62a7e37e43bbfc1f8525a00ad2125fd5897135dc93b849733884cb78ffd8e26c https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/brotli-libs-1.2.1-r0.apk /packages/brotli-libs-1.2.1-r0.apk
RUN apk verify /packages/brotli-libs-1.2.1-r0.apk

FROM n8nio/n8n:2.45.3@sha256:bf88c3783fc4b2a90a007bb99b04ad2f6a9627f41499baf72ca67559c51c7f4c
USER root
# BuildKit mounts keep the package installer, archive and test CLI out of the
# final image. Signature verification uses the base's existing Alpine key.
# No signing key, repository upgrade or unsigned package is introduced.
# Updating through apk removes old library files and records the actual version.
RUN --network=none \
    --mount=from=package-tools,source=/sbin/apk.static,target=/tmp/apk.static \
    --mount=from=package-tools,source=/packages,target=/tmp/security-packages \
    --mount=from=package-tools,source=/usr/bin/brotli,target=/tmp/brotli \
    /tmp/apk.static verify /tmp/security-packages/brotli-libs-1.2.1-r0.apk \
    && /tmp/apk.static --no-network --no-cache --repositories-file /dev/null add --no-scripts /tmp/security-packages/brotli-libs-1.2.1-r0.apk \
    && /tmp/apk.static info --exists 'brotli-libs=1.2.1-r0' \
    && test "$(readlink /usr/lib/libbrotlidec.so.1)" = libbrotlidec.so.1.2.1 \
    && test ! -e /usr/lib/libbrotlidec.so.1.2.0 \
    && test "$(printf 'shared-library roundtrip' | /tmp/brotli -c | /tmp/brotli -d -c)" = 'shared-library roundtrip' \
    && mkdir -p /usr/local/share/runtime-security \
    && printf '%s\n' \
      'brotli-libs 1.2.1-r0; signed Alpine 3.24 x86_64 package' \
      'APK sha256 62a7e37e43bbfc1f8525a00ad2125fd5897135dc93b849733884cb78ffd8e26c' \
      'aports 8313352127992a9d82e2c2024494f6c38a4dffb4; upstream Brotli v1.2.1/db24a98aed38a16de78cc05ca15cdd8dc2a0d92d' \
      > /usr/local/share/runtime-security/brotli.txt
USER node
LABEL net.yuniruyuni.security.brotli-version="1.2.1-r0" \
      org.opencontainers.image.base.name="n8nio/n8n:2.45.3" \
      org.opencontainers.image.base.digest="sha256:bf88c3783fc4b2a90a007bb99b04ad2f6a9627f41499baf72ca67559c51c7f4c"
