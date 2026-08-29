---
name: amath
description: AMath GPUクラスターの「今」を1枚で: リアルタイム状況(GPU使用率/空き/Pending/Node異常)+ 運用・ビジネスコンテキスト(Notionのcluster-insights・改善リスト・GPU上限申請、Slack #1_team_cluster の最近の動き)。
---

# /amath — AMathクラスター状況レポート

AMath = AKARI Mathematicians。燈(AKARI)社内のGPU計算資源(Kubernetesクラスタ)。クライアント案件ではなく社内インフラなので機密フィルター上の「クライアント名」制限は対象外。

## 手順

### 1. リアルタイム状況取得

```bash
~/.claude/scripts/amath_status.sh
```

設定は `~/.claude/scripts/amath_config.json`(Grafana URL/認証, Prometheus datasource uid, Slackチャンネルid, 参照Notionページid)。ファイルが無ければユーザーに再作成を促す(Grafana admin認証が要る)。

出力から以下を拾う:
- `pending_pods` — 起動待ちPod数。0が正常
- `gpu_total` / `gpu_idle` / `gpu_in_use` — 総GPU数・未使用数・使用中数
- `nodes_not_ready` — 空配列なら全ノード正常。値があればノード名を報告
- `gpu_usage_by_user` — 各GPUの `label_username` / `modelName` / `namespace` / `pod` / 使用率(%)

### 2. 運用・ビジネスコンテキスト取得(並列実行)

**Notion** — `notion-fetch` で以下を取得し、直近更新分だけ拾う(全文は不要、更新日時と要点):
- cluster-insights: `~/.claude/scripts/amath_config.json` の `notion_context_pages.cluster_insights`
- amath改善したいことリスト: `improvement_backlog`
- nas周りに関する課題: `nas_issues`
- Amathのgpu上限変更申請: `gpu_quota_request`

id が古くて404の場合は `notion-search query:"amath"` で該当ページを探し直し、config の id を更新する。

**Slack** — `slack_search_public_and_private`:
- query: `in:<#$(slack_cluster_channel_id)>` sort: `timestamp`, `response_format: concise`, `limit: 15`, `include_context: false`
- 直近1〜2週間で障害・メンテ・GPU拡張・仕様変更に関わるメッセージのみ拾う(雑談は除外)

### 3. レポート組み立て

日本語で以下のセクション構成、簡潔に(見出し+箇条書き、長文説明は不要):

```
## AMath クラスター状況 (YYYY-MM-DD HH:MM)

### リアルタイム
- GPU: 使用中 X / 未使用 Y / 全 Z
- Pending Pods: N
- Node: 全て Ready / ⚠️ <node名> が Not Ready

### 使用中GPU
| ユーザー | GPUモデル | namespace | 使用率 |
|---|---|---|---|
...(gpu_usage_by_user から。使用率降順)

### 運用トピック(直近)
- [Notion] <ページ名>: <一言> (更新日)
- [Slack #1_team_cluster] <一言> (日付)
(該当なしなら「特になし」)

### 参照
- Grafana: config の `grafana_url` + `/d/<dashboard-uid>/amath-cluster`
- Notionクラスター管理: (For team matesセクションのリンク)
```

会話内に表示するのみでよい。ファイル保存は不要(ライブ状況表示のため)。
