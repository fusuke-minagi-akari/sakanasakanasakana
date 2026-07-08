---
name: report
description: GitHubリンクと説明から日本語マークダウンレポートを生成し、~/Desktop に保存する。ブランチURL、ディレクトリURL、PR URLに対応。
argument-hint: <github-url> "<what to report on>"
---

# /report — GitHub から日本語レポートを生成

## 引数の解析

`$ARGUMENTS` を2つに分割:
- **URL**: 最初のトークン（`http` または `github.com` で始まる）
- **説明**: URL以降の全テキスト（レポートの焦点）

URLがなければユーザーに確認。説明がなければ「技術的な取り組みの概要レポート」をデフォルトとする。

## URL種別の判定とコンテンツ取得

### PR URL（`/pull/` を含む）
```bash
gh pr view <number> --repo <owner/repo> --json title,body,state,files,additions,deletions,commits,labels,createdAt,mergedAt
gh pr diff <number> --repo <owner/repo>
```
PR diffで参照されるキーファイル（README、docs、configs）も読む。

### ブランチ/ディレクトリURL（`/tree/` を含む）
URLから `owner/repo`、`branch`、`path` を解析。
```bash
gh api "repos/{owner}/{repo}/git/trees/{branch}?recursive=1" --jq '.tree[].path'
gh api "repos/{owner}/{repo}/contents/{path}?ref={branch}" --jq '.content' | base64 -d
```

### リポジトリルートURL
```bash
gh repo view <owner/repo> --json defaultBranchRef --jq '.defaultBranchRef.name'
```
デフォルトブランチでブランチ/ディレクトリURLと同様に処理。

### ローカルパス
URL がローカルパス（`/`、`~`、`.` で始まる）の場合、ファイルシステムから直接読む。

## コンテンツ探索

スコープが大きい場合は Agent (Explore type) を使用。

**優先順位:**
1. README.md, REPORT.md, PLAN.md
2. PROGRESS.md, CHANGELOG
3. 実験ログ、推論ログ
4. ソースコード（説明に関連する部分のみ）
5. 設定ファイル

**読まない:** バイナリ、画像、モデル重み、node_modules、.venv、__pycache__

## レポート生成

以下の構成で日本語マークダウンレポートを書く。内容に応じてセクションを取捨選択する。

```markdown
# [レポートタイトル（日本語）]

**日付:** YYYY-MM-DD

---

## 🎯 背景
なぜこの取り組みが必要だったか。課題。コンテキスト。

## 🔧 手法
何をしたか。技術的アプローチ。設計判断。

## 📊 結果
定量的な結果。メトリクス。before/after比較。

## 💡 考察
何が効いて何が効かなかったか。主要な学び。

## ➡️ 次のステップ
残タスク。未解決の問題。今後の方向性。
```

### 文体ルール

**言語: 全て日本語（必須）。**
- 本文、見出し、箇条書き、テーブルのセル — 全て日本語で書く。
- 英語で残して良いもの: モデル名 (Claude, Opus)、メトリクス名 (F1, IoU)、コード識別子 (`variable_name`)、CLIコマンド (`gh pr view`)、ツール名 (PyTorch, Docker)
- 迷ったら日本語。英語の方が自然でも、日本語訳があるなら日本語を使う。
- テンプレートの説明文は構造の参考用。実際のレポートに英語の説明文を残さない。

**簡潔さが最優先。**
- フィラー禁止（"〜について述べる", "以下に示す", "本節では〜を説明する"）
- テーブルが示す内容を文章で繰り返さない
- 3項目以上は箇条書き。1段落1アイデア。
- 目標: **最大2000語**。短いほど良い。

**視覚的フォーマット:**
- 構造化比較には全てテーブル
- 絵文字は見出しとステータスのみ:
  - 見出し: `## 🎯`, `## 🔧`, `## 📊`, `## 💡`, `## ➡️`
  - ステータス: ✅ 達成, ❌ 未達, ⚠️ 注意, 📈 改善, 📉 悪化, 🔄 変化なし
  - 本文中に絵文字を散りばめない
- 重要な数値は **太字**
- 各セクション最重要の知見は `>` ブロック引用
- 主要セクション間は `---` で区切り

**トーン:** 事実ベース、直接的。読者はプロジェクト外のエンジニアと想定。
**自己完結:** ローカルパス、内部URL、読者の環境への参照を含めない。

## 保存

ファイル名: `~/Desktop/claude-outputs/reports/report_YYYYMMDD_<slug>.md`
`<slug>` = 説明から生成（小文字、スペース→ハイフン、非ASCII除去、最大30文字）

ディレクトリが存在しない場合は `mkdir -p` で作成する。

## 出力

保存後、以下を表示:
1. ファイルパス
2. レポート内容の2〜3行要約
3. おおよその語数
4. 案内: "機密情報の除去が必要な場合は `/sanitize <filename>` を実行してください"

Note: `/sanitize` は `~/Desktop/claude-outputs/reports/` 内のファイルも受け付ける。
