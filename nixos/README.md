# NixOS VPS Configuration

Contabo VPS の NixOS 設定ファイル。GitHub Actions で自動デプロイされます。

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                   NixOS Host (Declarative)                  │
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │  Podman (n8n)   │  │  Incus (LXC)    │                  │
│  │  - rootless     │  │  - Arch Linux   │                  │
│  │  - docker互換   │  │  - 個人開発環境  │                  │
│  └─────────────────┘  └─────────────────┘                  │
│                                                             │
│  ┌─────────────────┐                                       │
│  │  cloudflared    │                                       │
│  │  - Tunnel       │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

## ファイル構成

```
nixos/
├── flake.nix                 # Nix Flakes エントリーポイント
├── flake.lock                # 依存関係のロックファイル
├── configuration.nix         # メイン設定
├── hardware-configuration.nix # ハードウェア設定（VPS固有）
├── secrets.nix               # agenix シークレット設定
├── services/
│   ├── cloudflared.nix       # Cloudflare Tunnel
│   ├── n8n.nix               # n8n (Podman)
│   └── incus.nix             # Incus (LXC)
└── secrets/
    ├── secrets.nix           # age 公開鍵定義
    ├── cloudflared-token.age # cloudflared トークン（暗号化済み）
    └── n8n-encryption-key.age # n8n 暗号化キー（暗号化済み）
```

## 自動デプロイ

`main` ブランチの `nixos/` ディレクトリに変更がプッシュされると、GitHub Actions が自動的に VPS にデプロイします。

### 認証

長期の SSH 秘密鍵は使いません。GitHub Actions は OIDC トークンから
[opkssh](https://github.com/openpubkey/opkssh) で短命の SSH 証明書を発行して接続します
（設定は `services/opkssh.nix`）。そのため deploy 用の GitHub Secret はありません。

ワークフロー側に `id-token: write` 権限が必要です。VPS 側で認可する identity は

```
repo:yuniruyuni@85034901/yuniruyuni.net@1181770564:environment:apply
```

です。後半が `:environment:` なのは deploy job が `environment: apply` を使うため
（`ref:` 形式にはなりません）。前半に数値 id が入るのは immutable subject claim へ
移行済みだからで、リポジトリ名を変えてもこの文字列は変わりません。実測は

```bash
gh api repos/yuniruyuni/yuniruyuni.net/actions/oidc/customization/sub
```

## 手動デプロイ

```bash
# ローカルから直接デプロイ（cloudflared 経由）
ssh -o ProxyCommand="cloudflared access ssh --hostname %h" yuniruyuni@ssh.yuniruyuni.net

# VPS 上でビルド＆適用
cd /etc/nixos
sudo nixos-rebuild switch --flake .#vps
```

## シークレット管理 (agenix)

シークレットは age で暗号化され、リポジトリに安全に保存されています。

### 新しいシークレットの追加

```bash
cd nixos/secrets

# シークレットファイルを編集（暗号化して保存される）
nix run github:ryantm/agenix -- -e new-secret.age

# secrets/secrets.nix に公開鍵定義を追加
# secrets.nix に使用方法を追加
```

### シークレットの更新

```bash
cd nixos/secrets
nix run github:ryantm/agenix -- -e cloudflared-token.age
```

## 初期セットアップ（新規インストール時）

### 1. NixOS インストール

```bash
# Contabo で Ubuntu をインストール後、kexec で NixOS インストーラーを起動
curl -L https://github.com/nix-community/nixos-images/releases/download/nixos-24.05/nixos-kexec-installer-x86_64-linux.tar.gz | tar xzf - -C /tmp
/tmp/kexec-installer.sh

# 再接続後、ディスク設定とインストール
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 1MiB 512MiB
parted /dev/sda -- set 1 bios_grub on
parted /dev/sda -- mkpart primary 512MiB -8GiB
parted /dev/sda -- mkpart primary linux-swap -8GiB 100%

mkfs.ext4 -L nixos /dev/sda2
mkswap -L swap /dev/sda3
mount /dev/disk/by-label/nixos /mnt
swapon /dev/sda3

nixos-generate-config --root /mnt
```

### 2. 設定ファイルを転送

```bash
scp -r infrastructure/nixos/* root@<VPS_IP>:/mnt/etc/nixos/
```

### 3. インストール

```bash
cd /mnt/etc/nixos
nixos-install --flake .#vps
reboot
```

### 4. デプロイ経路の確認

GitHub Actions 用の鍵を作る必要はありません。`services/opkssh.nix` の
`authorizations` に対象リポジトリの identity が入っていれば、Actions は
OIDC で発行した短命証明書で接続できます。

手元の端末から入るための公開鍵は `configuration.nix` の
`openssh.authorizedKeys.keys` に追加します。これは opkssh を壊したときの
復旧経路も兼ねるので、最低 1 本は必ず残してください。

## トラブルシューティング

### cloudflared が起動しない

```bash
sudo journalctl -u cloudflared -f
# シークレットが正しく復号されているか確認
sudo cat /run/agenix/cloudflared-token
```

### n8n が起動しない

```bash
sudo journalctl -u podman-n8n -f
# agenix サービスの状態確認
sudo systemctl status agenix
```

### Flake のビルドエラー

```bash
# Flake の構文チェック
nix flake check

# 詳細なビルドログ
nixos-rebuild build --flake .#vps --show-trace
```
