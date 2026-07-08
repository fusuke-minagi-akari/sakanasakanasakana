---
name: kalmia
description: kalmia-ロボットDBで自分が担当するタスク/サブタスクを抽出し、ステータス色分けの親子ツリー図(PNG)を生成する。デフォルトは完了/アーカイブを除いたアクティブのみ。--all で全件。
argument-hint: [--all | --active(default)]
---

# /kalmia — kalmia担当タスクをツリー図化

kalmia-ロボットDBから自分(担当者=実行ユーザー)のタスクを抽出し、ステータス色分けの親子ツリーをPNG化する。

## 引数

- `--active` (デフォルト): 完了(`完了`)・アーカイブ(`アーカイブ済み`)を除外。今やる作業だけ表示
- `--all`: 全ステータス表示。完了は横長回避のため4行グリッドに圧縮

## データソース定数

- kalmia-ロボット data source: `collection://<KALMIA_NOTION_COLLECTION_ID>`
- 親DB(スプリントビュー2)経由でなく直接このcollectionを叩く

## 手順

### 1. 自分のユーザーID取得
`mcp__claude_ai_Notion__notion-get-users` を `user_id: "self"` で呼び、`id` を取得。

### 2. 担当タスク抽出
`mcp__claude_ai_Notion__notion-query-data-sources` (SQLモード):

```sql
SELECT "タスクID","タスク名","ステータス","date:期限:start","親タスク","サブタスク","担当者",url
FROM "collection://<KALMIA_NOTION_COLLECTION_ID>"
WHERE "担当者" LIKE ?
```
params: `["%<self-id>%"]`

- `担当者` は user IDのJSON配列文字列。LIKEで部分一致
- `親タスク`/`サブタスク` はpage URLのJSON配列。これで親子関係を構築
- `ステータス` 値: `未着手 / 外パラ待ち / 進行中 / PR待ち / 完了 / アーカイブ済み`

### 3. 親子ツリー構築
- 自分のタスク同士で `親タスク`/`サブタスク` URLを突き合わせ、親→子をsubgraph化
- 親が自分のタスクでない(外部親)場合でも、同じ外部親を共有する自タスクは系統グループとしてまとめてよい(例: 水滴/障害物検出系、缶認識系)
- 親も子もない単独タスクは「単独タスク」subgraph内でステータス別に並べる
- `--active` 時: 完了・アーカイブのノードは除外。除外で親subgraphの中身が1個だけになる場合は単独ノード化

### 4. Mermaid生成
`/tmp/claude_diagram.mmd` に書く。**ラベルは必ず `"..."` で囲む**(`→ + ( ) /` がパーサを壊す。`→` は ` to ` 等に置換)。

ステータス色分け classDef:
```
classDef inprog fill:#93c5fd,stroke:#2563eb,color:#000
classDef pr     fill:#fdba74,stroke:#ea580c,color:#000
classDef extr   fill:#fde047,stroke:#ca8a04,color:#000
classDef todo   fill:#e5e7eb,stroke:#6b7280,color:#000
classDef done   fill:#86efac,stroke:#16a34a,color:#000
classDef arch   fill:#f3f4f6,stroke:#9ca3af,color:#9ca3af,stroke-dasharray:5 5
```
対応: 進行中→inprog / PR待ち→pr / 外パラ待ち→extr / 未着手→todo / 完了→done / アーカイブ済み→arch

ノード例: `n113["113 障害物検知 Moveit待ち"]:::inprog`
親子: `n99 --> n100 & n101 & n138`

**凡例(LEGEND)subgraphを必ず付ける**(表示するステータスのみ)。

`--all` で完了が多い時は横長防止: 完了subgraph内を `direction LR` + 不可視リンク `~~~` で5列×複数行グリッドに:
```
n80 ~~~ n126 ~~~ n69 ~~~ n78 ~~~ n11
n81 ~~~ n133 ~~~ n72 ~~~ n93 ~~~ n20
...
```

### 5. PNG描画
```bash
mkdir -p ~/Desktop/claude-outputs/diagrams
npx --yes @mermaid-js/mermaid-cli -i /tmp/claude_diagram.mmd \
  -o ~/Desktop/claude-outputs/diagrams/kalmia_tasks.png \
  -b white --scale 6 --width 1600 2>&1
sips -g pixelWidth -g pixelHeight ~/Desktop/claude-outputs/diagrams/kalmia_tasks.png
```
描画失敗時はMermaid構文(主にラベルの未引用特殊文字)を直して再試行。

### 6. 検証・報告
- 生成PNGをReadして描画確認
- 出力パス + 解像度を報告
- ステータス別サマリ(各件数)とボトルネック(例: 外パラ待ち件数)を一言添える
- Slack共有はPNGをドラッグ&ドロップ、と案内

## 出力先
`~/Desktop/claude-outputs/diagrams/kalmia_tasks.png` (グローバル規約: 非リポジトリ出力)
