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

FROM node:26.12.1-alpine3.24@sha256:ae8e1c19d56886270987e99b3cfcef13a919f0655b376ae322bc64ada76f88cd
RUN apk add --no-cache openssh graphicsmagick tini tzdata ca-certificates libc6-compat librdkafka fontconfig
COPY --from=application /usr/share/fonts /usr/share/fonts
COPY --from=native-builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n
COPY --from=application /docker-entrypoint.sh /docker-entrypoint.sh
RUN ln -s /usr/local/lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n \
    && mkdir -p /home/node/.n8n && chown node:node /home/node/.n8n \
    && node -e 'if (process.version !== "v26.12.1") process.exit(1)' \
    && fc-cache -f
ENV NODE_ENV=production N8N_RELEASE_TYPE=stable SHELL=/bin/sh NODE_PATH=/usr/local/lib/node_modules
WORKDIR /home/node
USER node
EXPOSE 5678
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]
LABEL org.opencontainers.image.source="https://github.com/yuniruyuni/yuniruyuni.net" \
      org.opencontainers.image.version="2.44.4-node26.12.1-security1" \
      org.opencontainers.image.description="Temporary n8n 2.44.4 rebuild for the October 2026 Node security release"
