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
    # identity は GitHub OIDC の sub クレームと完全一致で突き合わせられる。
    # ここで使っている v0.16.0 は glob も扱えるが、認可を広げる理由が無いので
    # 使っていない。
    #
    # sub の形は 2 つの要素で決まる。前半はリポジトリの識別で、immutable
    # subject claim へ移行済みなので数値 id が入る (名前を変えても不変)。
    # 後半は job の性質で、environment: を使うと :environment:<name>、
    # 使わなければ :ref:refs/heads/main になる。どちらか一方でも変えると
    # ここの文字列を直す必要がある。実測は
    #   gh api repos/<owner>/<repo>/actions/oidc/customization/sub
    authorizations = [
      # インフラ repo の deploy (apply-nixos.yml)。着地先が yuniruyuni なのは
      # nixos-rebuild switch に sudo が要るためで、現行の長期鍵と同じ権限に揃えて
      # いる。アプリ側は権限を持たない専用ユーザへ着地させるので、この扱いはここだけ。
      #
      # 末尾が :environment:apply であって :ref:refs/heads/main ではない点に
      # 注意。apply-nixos.yml の deploy job が environment: apply を指定して
      # いるため。アプリ側は environment を使わないので :ref: になる。
      #
      # インフラ repo の sub も immutable subject claim へ移行済み。
      #
      # 旧形式 (repo:yuniruyuni/yuniruyuni.net:...) は名前空間の再利用に
      # 弱く、リポジトリを消して同じ名前で作り直せば同じ sub が再現する。
      # OIDC の仕様は sub を二度と再割り当てされないものとしているので、
      # 旧形式はそれを満たしていない。8 リポジトリすべてを opt-in させた。
      #
      # 数値 id は不変なので、リポジトリ名を変えてもここは直さなくてよい。
      {
        user = "yuniruyuni";
        principal = "repo:yuniruyuni@85034901/yuniruyuni.net@1181770564:environment:apply";
        issuer = "https://token.actions.githubusercontent.com";
      }
    ];
  };
}
