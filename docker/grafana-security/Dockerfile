FROM docker.io/library/golang:1.26.10-alpine3.24@sha256:d1f3216ef30257c850cc136ba42a359ccd9d3e75f19b2c276e520c0b4ef327ce AS builder
RUN apk add --no-cache git make python3
ENV CGO_ENABLED=0 GOTOOLCHAIN=local GOMAXPROCS=2 GOFLAGS=-p=2 GOMEMLIMIT=3GiB
WORKDIR /src
RUN git init . && git remote add origin https://github.com/grafana/grafana.git && \
    git fetch --depth 1 origin af4a33e3786594ad72f72d97e6744010330c2977 && \
    git checkout --detach FETCH_HEAD && \
    test "$(git rev-parse HEAD)" = af4a33e3786594ad72f72d97e6744010330c2977
RUN go test crypto/x509
RUN make build-go OS=linux ARCH=amd64 GO_BUILD_TAGS=oss WIRE_TAGS=oss \
    COMMIT_SHA=af4a33e3786594ad72f72d97e6744010330c2977 BUILD_BRANCH=HEAD \
    SOURCE_DATE_EPOCH="$(git show -s --format=%ct HEAD)"
COPY pins.json stage-plugins.py probe.go /tests/
RUN python3 /tests/stage-plugins.py /plugins && \
    go build -o /probe /tests/probe.go && \
    go version -m /src/bin/linux/amd64/grafana > /core-buildinfo.txt

FROM docker.io/grafana/grafana@sha256:dbbc38ea21103cefb50396340cd88afec779c7e070b0a7bf5a75b4ce46651d3f AS core
COPY --from=builder --chown=0:0 --chmod=755 /src/bin/linux/amd64/grafana /usr/share/grafana/bin/grafana

FROM core AS candidate
USER 0
# Replace complete official signed archives; retaining old files would invalidate signatures.
RUN rm -rf /usr/share/grafana/data/plugins-bundled/elasticsearch /usr/share/grafana/data/plugins-bundled/grafana-pyroscope-datasource /usr/share/grafana/data/plugins-bundled/opentsdb /usr/share/grafana/data/plugins-bundled/prometheus /usr/share/grafana/data/plugins-bundled/stackdriver /usr/share/grafana/data/plugins-bundled/tempo /usr/share/grafana/data/plugins-bundled/zipkin
COPY --from=builder --chown=472:0 /plugins/ /usr/share/grafana/data/plugins-bundled/
USER 472

FROM candidate AS verify
COPY --from=builder --chmod=755 /probe /test-probe
COPY --from=builder /core-buildinfo.txt /test-core-buildinfo.txt

# Default builds also produce the production candidate, without test utilities.
FROM candidate AS release
