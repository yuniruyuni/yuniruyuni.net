# Temporary security rebuild of the deployed n8n application, without an n8n
# application/schema upgrade. Both inputs are immutable upstream images.
FROM n8nio/n8n:2.44.4@sha256:c72fa9f1bd9b59626deeb284824c0495625c3f6d894d395d27e241bf192d9900 AS application
FROM node:26.12.1-alpine3.24@sha256:ae8e1c19d56886270987e99b3cfcef13a919f0655b376ae322bc64ada76f88cd AS native-builder
RUN apk add --no-cache python3 make g++ librdkafka-dev
COPY --from=application /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n
ENV NODE_GYP=/usr/local/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js
# Follow upstream's native rebuilds against the patched Node headers and musl.
# Do not reuse the old V8-dependent isolated-vm binary.
RUN set -eu; \
    cd /usr/local/lib/node_modules/n8n/node_modules/isolated-vm; \
    rm -rf prebuilds; node "$NODE_GYP" rebuild --release -j 2; \
    cd /usr/local/lib/node_modules/n8n/node_modules/sqlite3; \
    node "$NODE_GYP" rebuild --release -j 2; \
    cd /usr/local/lib/node_modules/n8n/node_modules/.pnpm/@confluentinc+kafka-javascript@*/node_modules/@confluentinc/kafka-javascript; \
    BUILD_LIBRDKAFKA=0 node "$NODE_GYP" rebuild --release -j 2

FROM native-builder AS brotli-builder
RUN apk add --no-cache cmake
WORKDIR /tmp/brotli-build
# Stable v1.2.1 backports the same CVE fix as Node. Alpine 3.24's packaged
# brotli-libs 1.2.0-r1 still lacks it, independently of Node's embedded decoder.
ADD --checksum=sha256:113b9685dfc14dd2f3360d077283266eec2fbdfb0fe3e5600f11be151da0d68e https://github.com/google/brotli/archive/db24a98aed38a16de78cc05ca15cdd8dc2a0d92d.tar.gz /tmp/brotli.tar.gz
RUN --network=none tar -xzf /tmp/brotli.tar.gz --strip-components=1 \
    && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=ON \
      -DBROTLI_BUILD_TOOLS=ON -DBROTLI_DISABLE_TESTS=OFF \
    && cmake --build build -j 2 \
    && ctest --test-dir build --output-on-failure \
    && DESTDIR=/out cmake --install build

FROM node:26.12.1-alpine3.24@sha256:ae8e1c19d56886270987e99b3cfcef13a919f0655b376ae322bc64ada76f88cd
RUN apk add --no-cache openssh graphicsmagick tini tzdata ca-certificates libc6-compat librdkafka fontconfig git=2.54.0-r0
COPY --from=application /usr/share/fonts /usr/share/fonts
COPY --from=application /usr/share/node_modules/corepack /usr/share/node_modules/corepack
COPY --from=application /usr/share/node_modules/yarn /usr/share/node_modules/yarn
COPY --from=native-builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n
COPY --from=brotli-builder /out/usr/lib/ /usr/lib/
COPY --from=brotli-builder /out/usr/bin/brotli /usr/local/bin/brotli
COPY --from=application /docker-entrypoint.sh /docker-entrypoint.sh
RUN ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n \
    && ln -s /usr/share/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
    && ln -s /usr/share/node_modules/yarn/bin/yarn /usr/local/bin/yarn \
    && ln -s /usr/share/node_modules/yarn/bin/yarn /usr/local/bin/yarnpkg \
    && rm /usr/lib/libbrotlicommon.so.1.2.0 /usr/lib/libbrotlidec.so.1.2.0 /usr/lib/libbrotlienc.so.1.2.0 \
    && mkdir -p /usr/local/share/runtime-security \
    && printf '%s\n' 'Brotli 1.2.1; upstream db24a98aed38a16de78cc05ca15cdd8dc2a0d92d; source sha256 113b9685dfc14dd2f3360d077283266eec2fbdfb0fe3e5600f11be151da0d68e; replaces Alpine brotli-libs 1.2.0-r1 shared objects' > /usr/local/share/runtime-security/brotli.txt \
    && mkdir -p /home/node/.n8n && chown node:node /home/node/.n8n \
    && node -e 'if (process.version !== "v26.12.1") process.exit(1)' \
    && brotli --version && git --version && corepack --version && yarn --version \
    && fc-cache -f
ENV NODE_ENV=production N8N_RELEASE_TYPE=stable SHELL=/bin/sh NODE_PATH=/usr/local/lib/node_modules
WORKDIR /home/node
USER node
EXPOSE 5678
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
LABEL org.opencontainers.image.source="https://github.com/yuniruyuni/yuniruyuni.net" \
      org.opencontainers.image.version="2.44.4-node26.12.1-security2" \
      org.opencontainers.image.brotli-version="1.2.1" \
      org.opencontainers.image.description="Temporary n8n 2.44.4 rebuild for the October 2026 Node security release"
