# opkssh (OpenPubkey SSH)
#
# GitHub Actions の OIDC トークンから短命の SSH 証明書を発行させ、長期の SSH
# 秘密鍵を GitHub secrets に置かずにデプロイできるようにする。
#
# もともと apply-nixos.yml は secrets.SSH_PRIVATE_KEY という長期鍵を使っていた。
# 漏れても失効させるまで有効なままで、しかも wheel + passwordless sudo の
# yuniruyuni として着地する。アプリ側リポジトリにも同じ経路を増やしたくないため
# 置き換えた。長期鍵は 2026-08-21 に廃止済み。
#
# opkssh は CA 秘密鍵を持たない点が自前実装 (oidc-ssh-ca) との違いで、
# 守るべき鍵が増えない。証明書に PK Token を載せ、検証側は OP の署名を辿る。
#
# sshd は AuthorizedKeysFile と AuthorizedKeysCommand の両方を参照するため、
# configuration.nix に残した個人鍵での認証と並存する。opkssh や sshd を壊す変更を
# 入れてしまったときは個人鍵で入って復旧できる。

{ pkgs, ... }:

{
  services.opkssh = {
    enable = true;

    # nixpkgs 25.11 の v0.10.0 ではなく 0.16.0 を使う。
    #
    # v0.10.0 は SSH 証明書の principals を空にするが、この VPS の OpenSSH 10.3 は
    # principal を持たないユーザ証明書を「Certificate lacks principal list」として
    # 拒否する。2026-08-21 の疎通確認が実際にこれで落ちた。詳細は pkgs/opkssh.nix。
    package = pkgs.callPackage ../pkgs/opkssh.nix { };

    # 既定では google / microsoft / github の 3 つが登録されるが、ここで
    # 受け付ける必要があるのは GitHub Actions だけなので絞る。
    #
    # providers は「どの OP の署名を信頼するか」であって認可ではない
    # (認可は authorizations 側) が、不要な issuer を信頼リストに残す理由がない。
    #
    # lifetime = "oidc" は ID Token 自体の exp に証明書の寿命を合わせる指定。
    # GitHub Actions のトークンは短命なので、これが最も短い設定になる。
    providers = {
      github = {
        issuer = "https://token.actions.githubusercontent.com";
        clientId = "github";
        lifetime = "oidc";
      };
    };

    # 認可は /etc/opk/auth_id に
    #   <linux ユーザ> <OIDC identity> <issuer>
    # という 1 行として書き出される。
    #
    # identity は GitHub OIDC の sub クレームと突き合わせられるが、
    # nixpkgs 25.11 が入れている opkssh は v0.10.0 で、照合は
    #   string(claims.Sub) == user.IdentityAttribute
    # の完全一致のみ。refs/heads/* のような glob は効かない (upstream では
    # v0.16 で追加された)。デプロイは main への push 限定なので支障はないが、
    # tag デプロイや GitHub Environment を導入するとこの文字列が変わる
    # (environment を使うと sub は repo:OWNER/REPO:environment:NAME になる)。
    authorizations = [
      # インフラ repo の deploy (apply-nixos.yml)。着地先が yuniruyuni なのは
      # nixos-rebuild switch に sudo が要るためで、現行の長期鍵と同じ権限に揃えて
      # いる。アプリ側は権限を持たない専用ユーザへ着地させるので、この扱いはここだけ。
      #
      # environment:apply であって ref:refs/heads/main ではない点に注意。
      # apply-nixos.yml の deploy job は environment: apply を指定しており、
      # GitHub は environment を使う job の sub を
      #   repo:OWNER/REPO:environment:NAME
      # に変える (ref 形式にはならない)。
      {
        user = "yuniruyuni";
        principal = "repo:yuniruyuni/yuniruyuni.net:environment:apply";
        issuer = "https://token.actions.githubusercontent.com";
      }

      # --- ここから下は immutable subject claim への移行中だけ置くもの ---
      #
      # GitHub は 2026-07-15 以降に作られたリポジトリの sub を、名前ではなく
      # 数値 id を含む形にした。旧形式は名前空間の再利用に弱く、リポジトリを
      # 消して同じ名前で作り直せば同じ sub が再現してしまう。OIDC の仕様は
      # sub を二度と再割り当てされないものとしているので、旧形式はそもそも
      # それを満たしていない。既存のリポジトリも opt-in できるので揃える。
      #
      # リネームや移管でも新形式へ切り替わるため、放置すると名前を変えた
      # 瞬間に認可が外れる。原因の分かりにくい形で止まるので先に手を打つ。
      #
      # 認可は加算的な OR なので、新旧を両方置けば切り替えの前後どちらでも
      # 通る。全リポジトリの opt-in を確認したら、旧形式の側を消す。
      {
        user = "yuniruyuni";
        principal = "repo:yuniruyuni@85034901/yuniruyuni.net@1181770564:environment:apply";
        issuer = "https://token.actions.githubusercontent.com";
      }
    ]
    ++ map
      (p: {
        user = "yunirun-${p.app}";
        principal = "repo:yuniruyuni@85034901/${p.repo}@${p.id}:ref:refs/heads/main";
        issuer = "https://token.actions.githubusercontent.com";
      }) [
      { app = "template"; repo = "template"; id = "1203258260"; }
      { app = "costume"; repo = "costume"; id = "1181870108"; }
      { app = "lom"; repo = "LegendOfManaWeapon"; id = "1181342776"; }
      { app = "web"; repo = "web"; id = "830180787"; }
      { app = "tags"; repo = "StreamTagInventory"; id = "836372101"; }
      { app = "post"; repo = "StreamerPost"; id = "1020573506"; }
    ];
  };
}
