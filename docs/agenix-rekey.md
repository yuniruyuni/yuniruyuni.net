# Agenix Secrets Rekey 手順

VPS を再構築した場合や、secrets.nix のキー構成を変更した場合に secrets を rekey する手順。

## 前提条件

- 1Password に `infrastructure-admin` SSH キーが保存されていること
- `age` コマンドがインストールされていること
- `ssh-to-age` コマンドがインストールされていること

### ツールのインストール

```bash
# macOS
brew install age
go install github.com/Mic92/ssh-to-age/cmd/ssh-to-age@latest
```

## Rekey 手順

### 1. 1Password から秘密鍵を取得

1Password アプリで `infrastructure-admin` を開き、秘密鍵をファイルとしてエクスポート：

```bash
# 一時ファイルとして保存（作業後に必ず削除）
# 1Password GUI から秘密鍵をコピーして保存
cat > /tmp/infra-admin.key << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
（秘密鍵の内容）
-----END OPENSSH PRIVATE KEY-----
EOF
chmod 600 /tmp/infra-admin.key
```

### 2. SSH 秘密鍵を age 形式に変換

```bash
ssh-to-age -private-key -i /tmp/infra-admin.key > /tmp/infra-admin.age.key
```

### 3. secrets.nix を更新（必要な場合）

VPS を再構築した場合は、新しい VPS の SSH ホスト鍵を age 形式に変換して追加：

```bash
# VPS で実行
sudo cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
```

取得した age 公開鍵を `nixos/secrets/secrets.nix` の `vps` に設定。

### 4. Rekey を実行

```bash
cd nixos/secrets

# 各 .age ファイルを復号して再暗号化
for f in *.age; do
  echo "Rekeying $f..."
  CONTENT=$(age -d -i /tmp/infra-admin.age.key "$f")

  # secrets.nix の publicKeys に対応する全キーで再暗号化
  # vps と onepassword の例：
  echo "$CONTENT" | age \
    -r "age1xxxxxx..." \
    -r "age1t5u8r467lwp2t5d0qjr38va4nmly3wyg5k9fwttaakmu66q4zyvqq58qav" \
    -o "$f.new"

  mv "$f.new" "$f"
done
```

### 5. クリーンアップ

```bash
# 一時ファイルを確実に削除
rm -f /tmp/infra-admin.key /tmp/infra-admin.age.key
```

### 6. SSH ホスト公開鍵を更新

VPS を再構築した場合は、CI/CD の SSH ホスト鍵検証用に `ssh/known_hosts` を更新：

```bash
# VPS からホスト公開鍵を取得して known_hosts 形式で保存
ssh yuniruyuni.net "cat /etc/ssh/ssh_host_ed25519_key.pub; cat /etc/ssh/ssh_host_rsa_key.pub" 2>/dev/null | \
  awk '{print "ssh.yuniruyuni.net " $0}' > ssh/known_hosts
```

このファイルは CI/CD（nixos-deploy）から参照されます。

### 7. コミット & デプロイ

```bash
git add nixos/secrets/ ssh/known_hosts
git commit -m "chore(agenix): rekey secrets for new VPS"
git push
```

GitHub Actions が自動的に VPS にデプロイします。

## キー構成

| キー | 用途 | 場所 |
|------|------|------|
| `vps` | ランタイム復号 | VPS の `/etc/ssh/ssh_host_ed25519_key` |
| `onepassword` | Rekey 操作 | 1Password `infrastructure-admin` |

## トラブルシューティング

### "no identity matched any of the recipients"

- 使用している秘密鍵が .age ファイルの暗号化に使われた公開鍵と対応していない
- `ssh-to-age -private-key` で age 形式に変換したか確認
- secrets.nix の公開鍵と一致しているか確認

### age コマンドが SSH 鍵を直接読めない

age は SSH 秘密鍵を直接使用できますが、age 公開鍵（`age1...`）で暗号化されたファイルを復号するには、対応する age 秘密鍵（`AGE-SECRET-KEY-...`）が必要です。`ssh-to-age -private-key` で変換してください。
