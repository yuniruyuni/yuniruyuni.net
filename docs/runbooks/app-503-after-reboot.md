# 再起動後にアプリが 503 を返す (rootless podman の名前空間が古い)

2026-10 に VPS が予定外に再起動し、fighter と lom が戻らなかった件の記録と復旧手順。
yunirun ≥ `2109871d` (yunirun PR #59) では converge / 起動時に自己修復するので、
通常はこの手順は不要。修復されなかったときのためのもの。

## 症状

- 公開ホスト名が Cloudflare 経由で **503 "No server is available to handle this request."** を返す。
  これは HAProxy の応答で、オリジン (yunirun-haproxy) までは届いている。
- `yunirun-haproxy` のログに `<NOSRV>` が並ぶ (該当アプリの backend に UP の server が 0 個)。

  ```bash
  journalctl -u yunirun-haproxy --since -30min | grep NOSRV
  ```

- アプリの user unit (`<app>-blue` / `<app>-green`) が起動に失敗している。
  podman のエラーは `insufficient UIDs or GIDs available in user namespace` や
  `potentially insufficient UIDs or GIDs available in user namespace`。
  非 root の image (distroless nonroot の uid 65532、nginx など) だけが落ち、
  root で動く image は動くので、一部のアプリだけが落ちる。
- 外形監視 (このリポジトリの外で管理) が通知する。
  起動 5 分後の `boot-selfcheck` (nixos/services/boot-selfcheck.nix) も n8n に通知する
  (n8n が戻っていれば)。

## 原因

NixOS の activation は `/etc/subuid` / `/etc/subgid` を `users.users` の宣言から作り直し、
yunirun が imperative に足したアプリユーザの行を消す。以前の yunirun は converge で
後から行を戻していたが、再起動時は converge より先に linger のユーザの unit
(`user@<uid>.service`) が起動し、podman が **行の無い状態で** ユーザ名前空間
(pause プロセス) を作った。rootless podman の名前空間は作った時点の写像のまま
変わらないので、行が戻った後も uid 1 個だけの写像を使い続ける。

`/etc/subuid` の行を見る検査はすべて通るので、実際の写像を見ないと分からない。

## 診断

```bash
# 前提の検査。root で走らせるとアプリごとの名前空間の写像まで見る
# (yunirun ≥ 2109871d の podman/user-namespace-is-fixed-when-created)。
sudo yunirun doctor

# 自己点検の結果
systemctl status boot-selfcheck.service
journalctl -u boot-selfcheck.service -b

# HAProxy から見た backend ごとの UP な server 数 (0 なら <NOSRV>)
curl -s http://127.0.0.1:8098/metrics | grep '^haproxy_backend_active_servers'
```

名前空間の写像を直接見る (`<app>` は fighter / lom など):

```bash
uid=$(id -u yunirun-<app>)
grep yunirun-<app> /etc/subuid /etc/subgid
sudo systemd-run --uid "$uid" --setenv XDG_RUNTIME_DIR=/run/user/$uid \
  --pipe --wait --quiet --collect podman unshare cat /proc/self/uid_map
```

健全なら 2 行目に subuid の範囲 (`1  <subuid開始>  65536` のような行) がある。
`0 <uid> 1` の 1 行しか無ければ古い名前空間を使っている。

## 復旧

### yunirun ≥ 2109871d の場合

converge が古い名前空間を検出して `podman system migrate` と `user@<uid>` の再起動を行う。

```bash
sudo systemctl restart yunirun-converge.service
journalctl -u yunirun-converge.service -b -n 100
```

### 手動 (上で直らない / 古い yunirun)

1. 名前空間を作り直させる (pause プロセスとコンテナが止まり、次の podman 呼び出しで
   今の `/etc/subuid` から作り直される)。

   ```bash
   sudo -u yunirun-<app> sh -c "cd / && XDG_RUNTIME_DIR=/run/user/$(id -u yunirun-<app>) podman system migrate"
   ```

2. アプリを入れ直す。アプリのリポジトリの `deploy-yunirun.yml` を
   `workflow_dispatch` で手動実行する (GitHub の Actions タブ → deploy-yunirun.yml →
   Run workflow、main)。

3. 確認する。

   ```bash
   curl -s http://127.0.0.1:8098/metrics | grep 'haproxy_backend_active_servers{proxy="<app>_out"}'
   sudo yunirun doctor
   sudo systemctl start boot-selfcheck.service
   ```

   外から `https://<host>/health` (lom はトップページ) が 200 を返すことも見る。
   Cloudflare の stale-while-revalidate で 200 に見えることがあるので、
   オリジンの確認は上の HAProxy の数字を正とする。

## 再発防止

- yunirun `2109871d` (PR #59): activation の `users` の直後に `yunirun subids` で行を戻す。
  起動時の activation は systemd より前に走るので、ユーザの unit から欠けた状態は見えない。
  converge は各アプリの uid_map / gid_map を確かめ、古ければ作り直す。
  doctor に `podman/user-namespace-is-fixed-when-created` が加わった。
- `nixos/services/boot-selfcheck.nix`: 起動 5 分後と以後 1 時間ごとに doctor と
  HAProxy の backend を確かめ、失敗したら n8n の alert webhook に通知する。
  n8n は同じホストにいるので、主たる通知経路はこのリポジトリの外で管理している外形監視。
