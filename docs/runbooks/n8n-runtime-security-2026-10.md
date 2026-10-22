# n8n October 2026 runtime security rebuild

The deployed vendor n8n 2.44.4 runs Node 26.10.0. The vendor's stable 2.44.5 also
pins that runtime, and n8nio/base:26.12.1 was unavailable on 2026-10-22.
This temporary rebuild retains n8n 2.44.4 and uses the official Node
26.12.1-alpine3.24 image pinned by digest. It rebuilds isolated-vm, sqlite3 and
Kafka against the new Node headers and musl. It is not an upstream n8n image.

## Build and verification

```sh
docker build -t localhost/n8n-security:2.44.4-node26.12.1-security1 docker/n8n-security
docker run --rm --network none --entrypoint node \
  -v "$PWD/docker/n8n-security:/tests:ro" \
  localhost/n8n-security:2.44.4-node26.12.1-security1 /tests/native-smoke.cjs
docker run --rm --network none --entrypoint sh \
  -v "$PWD/docker/n8n-security:/tests:ro" \
  localhost/n8n-security:2.44.4-node26.12.1-security1 /tests/workflow-smoke.sh
```

Tests cover Node 26.12.1, SQLite queries, isolated-vm execution, Kafka/Sentry/
Snowflake musl binding loading, Brotli roundtrip, workflow import and execution,
HTTP Request, SQLite migrations, workflow publication and active webhook HTTP 200.
The application version remains 2.44.4 to avoid a database upgrade during the
runtime change. Real external workflows must not be executed just for testing.

## Staging and activation

Use the existing administrator SSH path. No new registry credentials or access
policies are needed. Save the running vendor image before its post-start prune:

```sh
sudo -u n8n podman save --format oci-archive \
  --output /var/lib/n8n/security-rollback-20261022/n8n-2.44.4.oci.tar \
  docker.io/n8nio/n8n:2.44.4
```

The parent directory must already exist with mode 0700 and owner n8n. Transfer
the built image with `docker save` over SSH into `sudo -u n8n podman load`.
Verify the loaded image ID against the preStart assertion in n8n.nix and verify
`node --version` in an isolated container before merging the configuration PR.
The service uses `pull = "never"`: a missing local image must fail closed.
There is deliberately no persistent registry login. A replacement host needs
the image staged before this NixOS configuration can start n8n.

Before activation, stop n8n briefly and make a consistent, encrypted data archive
under `/var/lib/backups/security-20261022-n8n` (mode 0700), addressed to the existing
host and infrastructure-admin recipients. Preserve the encrypted n8n key and
current NixOS configuration beside it. Verify the encrypted key decrypts with
the existing host identity to exactly the current runtime key without printing
either value. Verify the archive can be decrypted and read; restart n8n on every
failure path. Do not invoke the general backup helper here: it also permanently
deletes old remote backups, which is outside this remediation.

After the normal NixOS deployment, inspect the actual running image ID and
`process.versions`, check `/healthz/readiness` at the origin, compare workflow/
credential counts, and check all configured active workflows activated. Verify
the other application HAProxy backends remain up. Cached Cloudflare HTTP 200
alone is insufficient. Credential bodies, tokens, workflow content and key
values must not appear in logs or reports.

## Rollback and retirement

The saved vendor image can be loaded locally. Revert the n8n.nix image, pull
policy and preStart assertion, then use the normal NixOS deployment. Preserve
the encrypted data snapshot; restoring it overwrites subsequent application data
and needs a separate decision. A runtime-only rollback normally reuses current
data because n8n stayed at 2.44.4. The old image restores the known vulnerabilities.

The local image guard intentionally pins the exact tested image ID. Rebuilding
with different Alpine package revisions can change this ID: validate again and
update the assertion only with the new tested artifact. Prefer a vendor image
once its actual Node runtime is verified patched, then remove this temporary
Dockerfile and local-image guard in the same reviewed change.

Sources: https://nodejs.org/en/blog/vulnerability/october-2026-security-releases
and https://github.com/n8n-io/n8n/blob/n8n%402.44.4/docker/images/n8n/Dockerfile
