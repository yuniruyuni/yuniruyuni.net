# opkssh 0.16.0
#
# nixpkgs 25.11 が持っているのは v0.10.0 で、この VPS の OpenSSH 10.3 とは
# 組み合わせが成立しない。
#
# v0.10.0 の login は SSH 証明書の principals をわざと空にしており
# (commands/login.go: "If principals is empty the server does not enforce any
# principal. The OPK verifier should use policy to make this decision.")、
# 一方 OpenSSH 10 は principal を持たないユーザ証明書を cert-authority 経由で
# 受け取ると
#   Refusing certificate ID "" ...: Certificate lacks principal list
# として拒否する。実際に 2026-08-21 の疎通確認がこれで落ちた。
#
# 上流は同じ問題を後に修正しており、v0.16.0 では principals 未指定のとき
# プレースホルダ "opkssh-wildcard" を証明書に入れ (commands/login.go:487)、
# verify 側が cert-authority,principals="..." を返すようになっている
# (commands/verify.go:137)。この修正は client と server の両方に必要なため、
# クライアント (GitHub Actions) 側も同じ v0.16.0 に揃えている。
#
# 式は nixpkgs master の pkgs/by-name/op/opkssh/package.nix をそのまま取り込んだもの。
# nixpkgs 側が 0.16.0 以降を 25.11 に入れたらこのファイルごと削除してよい。
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "opkssh";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "openpubkey";
    repo = "opkssh";
    tag = "v${finalAttrs.version}";
    hash = "sha256-c+ZcC9m+PfwFyLSz+dwahYdQe+wKHQHECT+gNp1rdQU=";
  };

  ldflags = [ "-X main.Version=${finalAttrs.version}" ];

  vendorHash = "sha256-BmU/8Y6CweVnOeHftQhacKKLccQk1uNljzHe+/zkUn4=";

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  doInstallCheck = true;

  meta = {
    homepage = "https://github.com/openpubkey/opkssh";
    description = "Enables SSH to be used with OpenID Connect";
    license = lib.licenses.asl20;
    mainProgram = "opkssh";
  };
})
