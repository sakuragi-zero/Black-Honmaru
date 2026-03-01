# Claude Code OTel 監視スタック

Claude Code のテレメトリデータを Grafana で可視化するための Self-hosted 監視スタックです。

## 構成

```
Claude Code
    │ OTLP/gRPC (port 4317)
    ▼
OTel Collector
    │ /metrics (port 8889)
    ▼
Prometheus (port 9090)
    │ datasource
    ▼
Grafana (port 3000)
```

| サービス | ポート | 役割 |
|---------|-------|------|
| OTel Collector | 4317 (gRPC), 4318 (HTTP) | Claude Code からテレメトリを受信 |
| Prometheus | 9090 | メトリクスを収集・保存 |
| Grafana | 3000 | メトリクスを可視化 |

## ファイル構成

```
monitoring/
├── docker-compose.yml        # サービス定義
├── otel-collector-config.yml # OTel Collector 設定（受信 → Prometheus 公開）
├── prometheus.yml            # Prometheus スクレイプ設定
└── README.md                 # このファイル
```

## セットアップ手順

### 1. Claude Code の settings.json を設定

`/workspace/.claude/settings.json` の `env` セクションに以下を追加：

```json
"env": {
  "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
  "OTEL_METRICS_EXPORTER": "otlp",
  "OTEL_LOGS_EXPORTER": "otlp",
  "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
  "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
}
```

### 2. 監視スタックを起動

```bash
cd /workspace/monitoring
docker compose up -d
```

起動確認：

```bash
docker compose ps
```

### 3. Grafana にデータソースを追加

1. `http://localhost:3000` を開く
2. ログイン: `admin` / `admin`（初回ログイン時にパスワード変更を求められます）
3. 左メニュー → **Connections → Data sources → Add data source**
4. **Prometheus** を選択
5. URL に `http://prometheus:9090` を入力
6. **Save & test** をクリック

### 4. ダッシュボードでメトリクスを確認

1. 左メニュー → **Dashboards → New → New dashboard**
2. **Add visualization** をクリック
3. Prometheus データソースを選択
4. クエリ例：

| クエリ | 内容 |
|-------|------|
| `claude_code_token_count_total` | 累計トークン使用量 |
| `claude_code_cost_usd_total` | 累計コスト（USD） |
| `claude_code_session_count_total` | セッション数 |
| `claude_code_lines_of_code_total` | 変更コード行数 |

> メトリクス名は `claude_code_` プレフィックスで統一されています。

## 停止・再起動

```bash
# 停止
docker compose down

# データを含めて完全削除
docker compose down -v

# 再起動
docker compose restart
```

## トラブルシューティング

### OTel Collector のログを確認

```bash
docker compose logs otel-collector
```

### Prometheus がメトリクスを取得できているか確認

ブラウザで `http://localhost:9090/targets` を開き、`claude-code` ジョブが `UP` になっているか確認。

### データが届いていない場合

- Docker が起動しているか確認
- `OTEL_EXPORTER_OTLP_ENDPOINT` が `http://localhost:4317` になっているか確認
- Claude Code を再起動して新しいセッションを開始する
