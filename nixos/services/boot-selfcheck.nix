# 起動後の自己点検。
#
# 2026-10 に予定外の再起動が起き、fighter と lom が落ちたまま戻らなかった。
# yunirun が /etc/subuid の行を戻すより先に linger のユーザの unit が起動し、
# podman が subuid の無いユーザ名前空間を作ってしまったため。HAProxy から
# 見ると両系とも health check に落ち、Cloudflare には 503
# "No server is available" が返っていた (docs/runbooks/app-503-after-reboot.md)。
#
# yunirun 本体は 2109871d で直った (activation の中で subuid を戻し、
# converge が古い名前空間を作り直す)。ここに置くのは「再起動の後に本当に
# 戻ったか」を人が見に行かなくても分かるようにする仕組み。
#
# 起動 5 分後と、以後 1 時間ごとに次を確かめる:
#   1. yunirun doctor — 名前空間の写像を含む前提がすべて成り立っているか
#   2. HAProxy の計測口 — 各アプリの backend に UP の server が 1 つ以上あるか
#      (0 のときに HAProxy は <NOSRV> として 503 を返す。今回の症状そのもの)
#
# 外から公開ホスト名を叩くのでは足りない。Cloudflare の
# stale-while-revalidate により、オリジンが止まっていても 200 が返ることがある
# (services/yunirun.nix の observability の注記)。
#
# 失敗したら n8n の alert webhook に送り、journal にも残して非 0 で終わる。
# ただし n8n はこのホストの上で動いているので、ホストごと落ちた場合や n8n
# 自身が戻っていない場合には届かない。n8n がホストを共有しているので、
# 主たる通知経路はこのリポジトリの外で管理している外形監視で、こちらは補助である。
#
# 失敗が続く間は 1 時間ごとに通知が繰り返される。直すまで鳴り続けるのを
# 意図している。

{ config, lib, pkgs, ... }:

let
  cfg = config.services.yunirun;

  # yunirun の HAProxy が常に開いている計測用の listener
  # (yunirun internal/render/render.go の MetricsPort)。
  haproxyMetrics = "http://127.0.0.1:8098/metrics";

  # backend の名前は "<アプリ名>_out" (同 render.go)。
  apps = lib.attrNames cfg.apps;

  selfcheck = pkgs.writeShellApplication {
    name = "boot-selfcheck";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      gnugrep
      gawk
      jq
      hostname
      # yunirun doctor が呼ぶもの。services.yunirun の runtimePath に合わせる。
      podman
      systemd
      shadow
      util-linux
      iproute2
    ];
    text = ''
      failures=()

      log() { printf '%s\n' "$*"; }

      # 1. yunirun doctor
      log "==> yunirun doctor"
      if doctor_out="$(${cfg.package}/bin/yunirun doctor 2>&1)"; then
        log "$doctor_out"
      else
        log "$doctor_out"
        failures+=("yunirun doctor failed: $(printf '%s' "$doctor_out" | tail -n 20)")
      fi

      # 2. HAProxy の backend ごとの UP な server 数
      log "==> haproxy backends"
      if metrics="$(curl -fsS --max-time 10 ${lib.escapeShellArg haproxyMetrics})"; then
        for app in ${lib.escapeShellArgs apps}; do
          active="$(printf '%s\n' "$metrics" \
            | awk -v p="haproxy_backend_active_servers{proxy=\"''${app}_out\"}" \
                '$1 == p { print $2; found = 1 } END { if (!found) print "missing" }')"
          if [[ "$active" == "missing" ]]; then
            failures+=("$app: backend ''${app}_out not found in haproxy metrics")
            log "  $app: MISSING"
          elif awk -v n="$active" 'BEGIN { exit !(n + 0 >= 1) }'; then
            log "  $app: ok ($active active)"
          else
            failures+=("$app: no server UP in haproxy backend (503 <NOSRV>)")
            log "  $app: DOWN (0 active)"
          fi
        done
      else
        failures+=("haproxy metrics endpoint ${haproxyMetrics} unreachable (yunirun-haproxy down?)")
      fi

      if ((''${#failures[@]} == 0)); then
        log "boot-selfcheck: all checks passed"
        exit 0
      fi

      summary="$(printf '%s\n' "''${failures[@]}")"
      log "boot-selfcheck: FAILED"
      log "$summary"

      ${lib.optionalString (cfg.observability.alertWebhook != "") ''
        # Grafana の webhook 通知に近い形で送る。n8n 側の既存のフローが
        # title / message を拾えるようにするため。
        payload="$(jq -n \
          --arg host "$(hostname)" \
          --arg summary "$summary" \
          '{
            receiver: "boot-selfcheck",
            status: "firing",
            title: "[FIRING] boot-selfcheck on \($host)",
            message: $summary,
            alerts: [{
              status: "firing",
              labels: { alertname: "BootSelfcheckFailed", host: $host, source: "boot-selfcheck" },
              annotations: { summary: "boot-selfcheck failed on \($host)", description: $summary }
            }]
          }')"
        if curl -fsS --max-time 10 -H 'Content-Type: application/json' \
            -d "$payload" ${lib.escapeShellArg cfg.observability.alertWebhook} >/dev/null; then
          log "boot-selfcheck: alert sent"
        else
          log "boot-selfcheck: WARNING could not deliver alert to webhook (n8n down?)"
        fi
      ''}
      exit 1
    '';
  };
in
lib.mkIf cfg.enable {
  systemd.services.boot-selfcheck = {
    description = "Self-check that yunirun apps came back after boot";
    after = [ "yunirun-converge.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    # newuidmap / newgidmap (setuid wrapper) の存在を doctor が確かめる。
    path = [ "/run/wrappers" ];
    serviceConfig = {
      Type = "oneshot";
      # doctor は台帳 (root のみ読める) とユーザの名前空間を見るので root で動かす。
      ExecStart = "${selfcheck}/bin/boot-selfcheck";
      TimeoutStartSec = "5min";

      # 読むだけで何も書かない。podman は systemd-run 越しに別 unit で動くので
      # ここの制限は及ばない。
      PrivateTmp = true;
      ProtectSystem = "full";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictRealtime = true;
      LockPersonality = true;
      NoNewPrivileges = true;
      # 叩くのは HAProxy の計測口と n8n の webhook だけで、どちらも loopback。
      IPAddressAllow = [ "localhost" ];
      IPAddressDeny = [ "any" ];
    };
  };

  systemd.timers.boot-selfcheck = {
    description = "Run boot-selfcheck 5 minutes after boot, then hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
  };
}
