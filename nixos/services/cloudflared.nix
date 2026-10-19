# cloudflared service configuration
# Provides secure tunnel access to the VPS
# Secrets managed by agenix

{ config, pkgs, lib, ... }:

{
  # Install cloudflared
  environment.systemPackages = [ pkgs.cloudflared ];

  # cloudflared systemd service
  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # 名前解決の担い手より後に起動する。
    #
    # このホストの /etc/resolv.conf は 127.0.0.1 (incus 用の dnsmasq。
    # services.dnsmasq.resolveLocalQueries の既定) を向いている。26.05 への
    # switch では dnsmasq / nscd / resolvconf も更新対象で、cloudflared と
    # 一緒に止められ、「starting」の段で同時に起動された。その瞬間は DNS が
    # 引けず、cloudflared は edge の発見に失敗して READY を出す前に終了する。
    # これが `Failed to start cloudflared.service` (switch の exit 4) の正体で、
    # dhcpcd の restart そのものではない (dhcpcd はその前の段で済んでいる)。
    #
    # network-online.target は switch 中は active のままなので待ち合わせに
    # ならない。After= は同時に積まれた start job の間に順序を付けるので、
    # 起動する unit を直接並べる。存在しない unit を指しても害は無い。
    #
    # stopIfChanged は既定 (true: 先に止めて「starting」の段で起動) のままに
    # する。false にすると「restarting」の段で再起動されるが、その時点で
    # dnsmasq はまだ止まっているので、かえって確実に失敗する。
    after = [
      "network-online.target"
      "nss-lookup.target"
      "dhcpcd.service"
      "resolvconf.service"
      "dnsmasq.service"
      "nscd.service"
    ];

    # 一時的な失敗で起動制限 (start-limit-hit) に達して止まったままに
    # ならないようにする。トンネルは唯一の入口で、止まると ssh も含めて
    # 外から何もできなくなる。
    startLimitIntervalSec = 0;

    serviceConfig = {
      Type = "notify";
      TimeoutStartSec = 0;

      # 名前が引けるまで少し待ってから起動する (最大 60 秒、引けなくても
      # 起動は試みる)。順序付けで足りない場合 (boot 時の DHCP の遅れ等) に、
      # start job が即座に失敗して switch が赤くなるのを避ける保険。
      ExecStartPre = pkgs.writeShellScript "cloudflared-wait-dns" ''
        for _ in $(${pkgs.coreutils}/bin/seq 30); do
          ${pkgs.getent}/bin/getent ahosts region1.v2.argotunnel.com >/dev/null && exit 0
          ${pkgs.coreutils}/bin/sleep 2
        done
        echo "DNS not ready after 60s; starting cloudflared anyway" >&2
      '';

      ExecStart = "${pkgs.cloudflared}/bin/cloudflared --no-autoupdate tunnel run";

      # 正常終了 (exit 0) でも戻す。止まってよい場面は無い。
      Restart = "always";
      RestartSec = "5s";

      # Security hardening
      User = "cloudflared";
      Group = "cloudflared";
      # Use agenix-managed secret
      EnvironmentFile = config.age.secrets.cloudflared-token.path;
    };
  };

  # Create cloudflared user
  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
    home = "/var/lib/cloudflared";
    createHome = true;
  };

  users.groups.cloudflared = { };
}
