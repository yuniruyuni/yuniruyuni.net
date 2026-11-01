# Official signed datasource archives for the Go CA distrust fix (GO-2026-6809).
# The official Grafana image fixes the server and seven bundled backends; these
# six independently released plugins replace the remaining older Go backends.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.yunirun;
  pins = [
    {
      id = "grafana-postgresql-datasource";
      version = "13.0.6";
      url = "https://github.com/grafana/grafana-postgresql-datasource/releases/download/v13.0.6/grafana-postgresql-datasource-13.0.6.linux_amd64.zip";
      sha256 = "a172cf8c517f45142b398a702763e205c0d2a727570a38c7d243640c3c8b6c9c";
    }
    {
      id = "influxdb";
      version = "13.1.9";
      url = "https://grafana.com/api/plugins/influxdb/versions/13.1.9/download?os=linux&arch=amd64";
      sha256 = "a1daa87aaaf923fcbccc2f3f055ddfe935014e1f4267a84638d492cf0c73c4ee";
    }
    {
      id = "jaeger";
      version = "13.0.6";
      url = "https://grafana.com/api/plugins/jaeger/versions/13.0.6/download?os=linux&arch=amd64";
      sha256 = "f15634bfcccc9f22e4c873efe3e9cc8126bd514b5358d0d3df1ba89380cc513f";
    }
    {
      id = "loki";
      version = "13.2.3";
      url = "https://grafana.com/api/plugins/loki/versions/13.2.3/download?os=linux&arch=amd64";
      sha256 = "570eaf86dd650663c594832eb675bb236d1231350016710d50ee583f479eb7c1";
    }
    {
      id = "mssql";
      version = "13.0.9";
      url = "https://grafana.com/api/plugins/mssql/versions/13.0.9/download?os=linux&arch=amd64";
      sha256 = "b1ca0199250137d1714582014935612d5f88244b613e02821f66dc387a3e0b91";
    }
    {
      id = "mysql";
      version = "13.1.5";
      url = "https://github.com/grafana/grafana-mysql-datasource/releases/download/v13.1.5/mysql-13.1.5.linux_amd64.zip";
      sha256 = "c5d3f6d729e0137c585177de05cb0f557e4d91d5dcf595c8a5a84b908b7bd3fc";
    }
  ];

  pluginPath = pin:
    let
      archive = pkgs.fetchurl {
        inherit (pin) url sha256;
        name = "${pin.id}-${pin.version}-linux-amd64.zip";
      };
    in pkgs.runCommand "${pin.id}-${pin.version}-signed" {
      nativeBuildInputs = [ pkgs.unzip pkgs.jq ];
    } ''
      unzip -q ${archive} -d unpack
      test "$(jq -r .id unpack/${pin.id}/plugin.json)" = ${lib.escapeShellArg pin.id}
      test "$(jq -r .info.version unpack/${pin.id}/plugin.json)" = ${lib.escapeShellArg pin.version}
      test -s unpack/${pin.id}/MANIFEST.txt
      # Keep every original file and executable bit covered by the signature.
      mv unpack/${pin.id} "$out"
      # Official ZIP directories can be group/world writable. Nix rejects such
      # outputs; remove write permissions without changing signed bytes or exec bits.
      chmod -R go-w "$out"
    '';

  quadletDropin = pkgs.writeText "yunirun-grafana-security.conf" ''
    [Container]
    # paths.plugins is searched before the image's plugins-bundled directory.
    ${lib.concatMapStringsSep "\n" (pin: "Volume=${pluginPath pin}:/var/lib/grafana/plugins/${pin.id}:ro") pins}
    # Keep the checked versions; the updater cannot replace read-only mounts.
    Environment=GF_PLUGINS_PREINSTALL_AUTO_UPDATE=false
  '';

  expectedMounts = map (pin: {
    source = toString (pluginPath pin);
    destination = "/var/lib/grafana/plugins/${pin.id}";
  }) pins;
in
{
  config = lib.mkIf (cfg.enable && cfg.observability.enable) {
    assertions = [ {
      assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
      message = "Grafana security plugins are pinned to official linux/amd64 archives.";
    } ];

    # Extend the existing yunirun-owned Quadlet without changing its generator.
    environment.etc."containers/systemd/yunirun-grafana.container.d/security.conf".source = quadletDropin;

    # Generated Quadlet services are outside NixOS's unit-change detection.
    # Apply plugin-only updates after converge, and avoid a second restart when
    # converge already recreated Grafana with these exact read-only mounts.
    systemd.services.grafana-security-apply = {
      description = "Apply pinned Grafana datasource plugins";
      wantedBy = [ "multi-user.target" ];
      after = [ "yunirun-converge.service" ];
      restartTriggers = [ quadletDropin ];
      path = [ pkgs.podman pkgs.jq pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if podman inspect yunirun-grafana | jq -e \
          --argjson expected ${lib.escapeShellArg (builtins.toJSON expectedMounts)} '
            .[0] as $actual
            | all($expected[]; . as $wanted
                | any($actual.Mounts[];
                    .Source == $wanted.source and
                    .Destination == $wanted.destination and .RW == false))
              and any($actual.Config.Env[];
                . == "GF_PLUGINS_PREINSTALL_AUTO_UPDATE=false")
          ' >/dev/null; then
          exit 0
        fi
        systemctl daemon-reload
        systemctl restart yunirun-grafana.service
      '';
    };
  };
}
