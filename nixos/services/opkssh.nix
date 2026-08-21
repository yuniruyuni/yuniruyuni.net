# opkssh (OpenPubkey SSH)
#
# GitHub Actions の OIDC トークンから短命の SSH 証明書を発行させ、長期の SSH
# 秘密鍵を GitHub secrets に置かずにデプロイできるようにする。
#
# 現状 apply-nixos.yml は secrets.SSH_PRIVATE_KEY という長期鍵を使っており、
# これは漏れても失効させるまで有効なままで、しかも wheel + passwordless sudo の
# yuniruyuni として着地する。アプリ側リポジトリにも同じ経路を増やすのは避けたい。
#
# opkssh は CA 秘密鍵を持たない点が自前実装 (oidc-ssh-ca) との違いで、
# 守るべき鍵が増えない。証明書に PK Token を載せ、検証側は OP の署名を辿る。
#
# 導入は段階的に行う。この時点では authorizedKeysCommand が増えるだけで、
# 既存の authorizedKeys による鍵認証はそのまま並存する (sshd は
# AuthorizedKeysFile と AuthorizedKeysCommand の両方を参照する)。
# そのため万一 opkssh が動かなくてもアクセスを失わない。

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
      # インフラ repo の deploy。着地先が yuniruyuni なのは nixos-rebuild switch に
      # sudo が要るためで、現行の apply-nixos.yml と同じ権限に揃えている。
      # アプリ側は権限を持たない専用ユーザへ着地させるので、この扱いはここだけ。
      {
        user = "yuniruyuni";
        principal = "repo:yuniruyuni/yuniruyuni.net:ref:refs/heads/main";
        issuer = "https://token.actions.githubusercontent.com";
      }
    ];
  };
}
