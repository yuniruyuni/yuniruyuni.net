# Grafana 13.2.4 の CA 検証修正候補

Grafana 本体のバージョンと依存モジュールを保ったまま、公式の同じソースを Go 1.26.10 で再構築する。対象は [GO-2026-6809](https://pkg.go.dev/vuln/GO-2026-6809) の CA 不信頼化。公式イメージの本体は Go 1.26.9 で構築されている。

`pins.json` に記録した7件の公式プラグインも、修正済み Go 1.27.3 で構築された公式配布物へ更新する。ZIP の SHA-256、版、Go 版を検証し、署名対象のファイルをそのまま保持する。署名検証や TLS 検証を無効にしない。

## 残る制約

- PostgreSQL、InfluxDB、Jaeger、Loki、MSSQL、MySQL の6プラグインは、確認時点で公式カタログに修正済み Go の版がない。独自に署名済みバイナリを書き換えず、従来版を保持する。該当プラグインが侵害された CA の証明書を使う HTTPS/TLS 接続を検証する場合のリスクは残る。
- 現構成の Loki はローカル HTTP 接続なので、その通信では CA 検証の問題に到達しない。接続方式やデータソースを変更する場合は再評価する。
- Tempo 13.3.0 はセキュリティ修正に加え、クエリエディターと trace ID クエリの修正を含む。主要3データソースと既存ダッシュボードの互換性を、使い捨ての試験データで確認する。
- これは構築・検証の候補であり、本番イメージ指定はまだ変更しない。新規の常設 CI ワークフローも追加していない。

## ローカル構築

```sh
docker build --target verify -t grafana-security-tests docker/grafana-security
docker build --target core -t grafana-security-core docker/grafana-security
docker build --target candidate -t grafana-security-candidate docker/grafana-security
python3 docker/grafana-security/verify-local.py grafana-security-core grafana-security-candidate
```

ローカル検証には Python 3.11 以降と Go が必要。試験用プログラムをホストの Go で構築するが、製品本体は固定した Go 1.26.10 コンテナで構築される。

ビルド時に Go 標準ライブラリの `crypto/x509` 試験を実行する。`verify` ターゲットの `/test-probe` は隔離した起動試験用であり、本番用 `candidate` には含めない。

本番反映前には、正確な候補イメージの Go 版・署名・起動・TLS・既存データ保持を確認し、新しい整合バックアップとロールバック用イメージを保持する。バックアップの復号・内容検証と、別環境での完全復元試験は区別して報告する。
