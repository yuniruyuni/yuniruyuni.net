# Grafana Go CA distrust update

Grafana is pinned to the official 13.2.5 image, index digest
`sha256:9f7aa1e1e3246aade5792d35a738049f7f32f89cd51d1956cf426a4e86268a84`.
The linux/amd64 manifest is
`sha256:ffeeebf613b00fede764821c5e5b1545fb376aba561ae91c488e91f219adb25a`.
The actual server binary reports Go 1.26.10. This includes the
[GO-2026-6809](https://vuln.go.dev/ID/GO-2026-6809.json) /
CVE-2026-111943 CA distrust fix. The official release was
[published on 2026-10-27 at 11:34:35 UTC](https://github.com/grafana/grafana/releases/tag/v13.2.5).

Seven bundled plugin binaries already use Go 1.27.3, but the other six in this
image still use Go 1.26.7. `nixos/services/grafana-security.nix` pins complete
official signed archives for those six:

| Plugin | Version | Published UTC |
| --- | --- | --- |
| [PostgreSQL](https://github.com/grafana/grafana-postgresql-datasource/releases/tag/v13.0.6) | 13.0.6 | 2026-10-28 17:34:57 |
| [InfluxDB](https://github.com/grafana/grafana-influxdb-datasource/releases/tag/v13.1.9) | 13.1.9 | 2026-10-28 17:04:05 |
| [Jaeger](https://grafana.com/grafana/plugins/jaeger/) | 13.0.6 | 2026-10-21 13:04:43 |
| [Loki](https://grafana.com/grafana/plugins/loki/) | 13.2.3 | 2026-10-21 13:08:29 |
| [MSSQL](https://github.com/grafana/grafana-mssql-datasource/releases/tag/v13.0.9) | 13.0.9 | 2026-10-27 17:24:22 |
| [MySQL](https://github.com/grafana/grafana-mysql-datasource/releases/tag/v13.1.5) | 13.1.5 | 2026-10-27 15:39:05 |

All six actual linux/amd64 plugin binaries report Go 1.27.3. All archives were
more than 72 hours old when checked on 2026-10-31 at 19:44 UTC. MySQL 13.1.5 is
not yet in the Grafana catalog; its archive comes from the official GitHub
release and has the same valid Grafana signing key as the catalog plugins.
Each archive's SHA-256, complete MANIFEST file coverage and file hashes, and
PGP signature were independently verified. The official signing key fingerprint
is `F33B25B691074E84636570F37E4D0C6A708866E7`, obtained from
<https://grafana.com/api/plugins/ci/keys>.

## Configuration and existing deployment

Nix fetches each ZIP by its raw SHA-256 and preserves its entire signed contents
and executable modes. Group/other write bits are removed for valid Nix store
permissions, without changing file contents. A normal Podman Quadlet drop-in mounts the resulting Nix
store directories read-only under `/var/lib/grafana/plugins/<id>`. Grafana
[searches that directory before its bundled plugin directory](https://github.com/grafana/grafana/blob/v13.2.5/pkg/setting/setting.go#L1588).
The first occurrence of a plugin ID is used. TLS verification and Grafana's
plugin signature verification stay enabled. The plugin auto-updater is disabled
for the pinned read-only directories.

This uses the existing `observability.grafanaImage` option and the existing
public NixOS Validate / apply-nixos workflows. There is no custom Grafana image,
image publication job, new workflow, credential, or permission change. It is
independent of the previously rejected custom-image workflow proposed for #267;
that workflow remains unimplemented. The new candidate supersedes the old
13.2.4 custom build recipe.

A NixOS oneshot runs after converge when the pinned configuration changes. It
compares the actual six mount sources, destinations, read-only flags and update
setting; it restarts Grafana only if these differ. This applies plugin-only
updates without a second restart when converge already applied them, or a restart
on every unrelated converge. Generated Quadlet services themselves are outside
NixOS unit-change detection.

## Validation boundaries

The image's amd64 layers were verified against their registry SHA-256 digests;
the server and all 13 bundled backend binaries were inspected directly with
`go version -m`. The six replacement archives were separately checked as above.
The existing NixOS Validate workflow validates and builds the NixOS configuration.
It does not execute Grafana or test a database migration.

On 2026-10-31 the actual amd64 server and plugin binaries were executed under
QEMU in an offline local Linux VM, using synthetic data only. Official 13.2.5
and then the same server with the six read-only plugin mounts each passed 11
checks (22 total): database/version, a retained dashboard, the exact 13 plugin
versions and valid runtime signatures, Prometheus/Loki/Tempo health and proxy
requests, trusted TLS acceptance and untrusted TLS rejection with a matching
x509 runtime log. The six external plugins took precedence over the bundled
versions, including the uncatalogued MySQL 13.1.5 archive. The selected server
uses Go 1.26.10 and every selected backend plugin uses Go 1.27.3, so no older Go
backend remains for this CA issue.

This test executes extracted official binaries and reproduces the plugin mounts;
it does not execute NixOS switch or Podman's generated production unit. It also
does not test an upgrade from the existing production 13.2.4 database. Required
public NixOS CI runs separately on the review PR.

Production merge, deployment, and the final combined health check are coordinated
by the production task. Normal backups and NixOS rollback remain the existing
recovery path; this change does not add a separate backup or restore procedure.
