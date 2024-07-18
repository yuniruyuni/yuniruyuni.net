FROM oven/bun:latest AS build

WORKDIR /work

ADD package.json /work
RUN bun install

ADD . /work
RUN bun run build

FROM joseluisq/static-web-server:latest
COPY --from=build /work/dist/* /public/
