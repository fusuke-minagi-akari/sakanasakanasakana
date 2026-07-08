---
description: Research a topic or project across GitHub, Notion, and Slack — outputs a rich .md summary with optional Mermaid diagrams
---

Research a topic, project, or keyword across GitHub, Notion, and Slack. Synthesize everything into a structured Markdown report tailored to the topic type — useful for newcomers, project managers, and engineers alike.

## Arguments

$ARGUMENTS

The entire argument string is the **topic** to research. It can be:
- A project name: `kalmia`, `Trellis2`, `daily-task-assistant`
- A technical topic: `倒れ缶検出`, `depth estimation`, `FOV bug`
- A person: `西宮直志`, `Rumina Satoi`, `gilmiwired`
- A broad area: `Jetson Orin ML pipeline`

---

## Instructions

### Step 0: Parse topic and detect mode

Set `$TOPIC` = the full argument string (trim whitespace).
Set `$TOPIC_SLUG` = `$TOPIC` lowercased, spaces replaced with `-`, non-ASCII stripped — used in the output filename.
Set `$TODAY` = today's date (YYYY-MM-DD).

**Classify `$TOPIC_MODE`** — pick exactly one:

| Mode | When to use | Examples |
|------|-------------|---------|
| `person` | Topic looks like a person's name (first + last, Japanese name, or a GitHub/Slack handle) | `Rumina Satoi`, `西宮直志`, `gilmiwired` |
| `project` | Topic matches a project codename, repo name, or tool name | `kalmia`, `Trellis2`, `daily-task-assistant`, `akari-claude-code` |
| `technical` | Topic is a concept, bug, feature, or technical area — not a person or project name | `depth estimation`, `FOV bug`, `PlacoIK`, `Jetson pipeline` |

If ambiguous (e.g. a person + topic like `西宮 PlacoIK`), prefer `person` and treat the rest as context to filter results.

---

### Step 0.5: Check for previous report (change delta)

```bash
ls ~/Desktop/claude-outputs/research/research_$TOPIC_SLUG_*.md 2>/dev/null | sort
```

If a previous `.md` file exists **with a date different from today**:
- Read it with the Read tool
- Note: status badge, contributor names, open PR numbers, last-activity dates
- After writing the main report body in Step 4, append a `## 変更点` section (see template below)

If no previous report exists, skip this step entirely — do **not** mention "first run" in the output.

---

### Step 1: Search all sources in parallel

**Remote API only — no local data.**
Do NOT read local git repositories, local files, standup outputs, nippo files, or any file system data. Do NOT use information from the current conversation context or previously generated reports. Every fact in the final report must come exclusively from the live API calls made in this step (GitHub search, Notion search/fetch, Slack search). Treat any prior knowledge of the topic from this session as zero — start fresh from the search results.

**While searching, track:** any other AKARI project codenames or repo names mentioned alongside `$TOPIC` in PR bodies and Slack messages — these become **Related Projects** in the report.

Run all searches simultaneously.

#### GitHub

```bash
# Repos matching topic
gh search repos "$TOPIC" --json name,description,url,updatedAt --limit 5 2>/dev/null

# PRs matching topic (open and recently closed)
gh search prs "$TOPIC" --sort updated --order desc \
  --json number,title,repository,state,url,updatedAt,author --limit 10 2>/dev/null

# Issues mentioning the topic
gh search issues "$TOPIC" --sort updated --order desc \
  --json number,title,repository,state,url,updatedAt,author --limit 8 2>/dev/null

# Code search (find files/functions containing the term)
gh search code "$TOPIC" --json path,repository,url --limit 8 2>/dev/null
```

For each relevant PR or issue found, read its full body:
```bash
gh pr view <url> --json title,body,comments,state,author,reviews 2>/dev/null
# or
gh issue view <url> --json title,body,comments,state,author 2>/dev/null
```

#### Repo-scoped deep dive (project mode)

Once the target repository is identified from the search results, fetch **all** PRs from that repo — not just the ones whose title/body matched the keyword. This catches PRs with Japanese titles, unrelated wording, or older PRs missed by keyword search:

```bash
# Replace OWNER/REPO with the identified repo (e.g. AKARI-Inc/kalmia-robot-learning)
gh pr list --repo OWNER/REPO \
  --json number,title,state,author,updatedAt,createdAt,reviewRequests,reviews \
  --limit 30 2>/dev/null
```

For each **open** PR: compare `createdAt` with today's date. If the PR has been open > 7 days AND `reviews` shows no approval (empty or only comments), mark it as a **review bottleneck** 🕐. These get flagged in `## 次のステップ`.

#### Notion

```bash
notion-search query="$TOPIC" query_type=internal page_size=8 max_highlight_length=200
```

For each result that looks substantive (task pages, spec docs, design docs, project pages, member profiles — not just database rows), fetch the full content:
```bash
notion-fetch id=<page_id>
```
Limit full fetches to top 4 most relevant pages to avoid bloat.

#### Slack

Search topic-first and unbiased — **do not anchor to the current user's messages**:

```bash
# Primary: all mentions of the topic across all channels
slack_search_public_and_private query="$TOPIC" response_format="concise" limit=15 include_context=true max_context_length=300

# Threads discussing the topic (catches richer discussion)
slack_search_public_and_private query="$TOPIC is:thread" response_format="concise" limit=8
```

**If primary Slack search returns < 5 results**, run fallback searches automatically:
```bash
# Fallback 1: Japanese keywords extracted from GitHub PR titles
slack_search_public_and_private query="<Japanese keywords from PRs>" response_format="concise" limit=10

# Fallback 2: main repo name if different from topic
slack_search_public_and_private query="<repo name>" response_format="concise" limit=10

# Fallback 3: top technology name from search results
slack_search_public_and_private query="<top tech keyword>" response_format="concise" limit=8
```
Note which fallback was used in the `## 調査範囲` section.

**Person mode only** — after identifying the person's Slack ID from their Notion profile or via `slack_search_users`:
```bash
# Messages sent by this person
slack_search_public_and_private query="from:<@$PERSON_SLACK_ID>" response_format="concise" limit=10 include_context=false
```

**While reading Slack results, extract decision markers:**
Scan each message for patterns like:
- `〇〇を使うことにしました` / `〜に決めました` / `〜にします`
- `方針変更:` / `方針:` / `decided to` / `we'll go with` / `〜で行きます`
- `〜をやめることにした` / `〜に切り替え`

For each match, note: what was decided, approximate date, and which Slack channel. These populate `## 意思決定ログ` in Template A. Skip trivial decisions (e.g. "今日のランチにします") — only capture architectural, tooling, or process decisions.

**Do not hardcode any channel ID.** Channel-specific search is only used if the user explicitly passes `in:#channel` in the topic string.

---

### Step 1.5: Assess search quality — before writing anything

After all searches complete, tally **meaningful, on-topic results** (exclude false positives from unrelated external repos):

- `$GITHUB_COUNT` = number of AKARI-relevant PRs / repos / issues found
- `$SLACK_COUNT` = number of Slack messages found
- `$NOTION_COUNT` = number of Notion pages fetched
- `$TOTAL` = sum of the above

#### Tier classification

| $TOTAL | Sources with results | Action |
|--------|---------------------|--------|
| ≥ 8 | ≥ 2 | **Full report** — proceed to Step 2 normally |
| 3–7 | any | **Cautious report** — proceed, but add a warning banner (see below) |
| < 3 | any | **Thin — trigger reformulation** (see below) |

#### Thin result: keyword reformulation (automatic)

When `$TOTAL < 3`, before asking the user, try up to 3 alternate search passes **in parallel**:

1. **Japanese equivalent** — if topic is English/romaji, try the Japanese reading or common Japanese alias (e.g. `kalmia` → `倒れ缶`, `daily-task-assistant` → `タスク管理`)
2. **Repo / full name** — if the topic could be a short alias, try the likely repo name (e.g. `kalmia` → `kalmia-robot-learning`)
3. **Key tech extracted** — use any tech terms found in the thin results so far (e.g. `Qwen`, `Piper`, `melchior`)

Run the same GitHub + Notion + Slack searches with each alternate term. Recount after.

#### Still thin after reformulation ($TOTAL < 3): ask the user

Use `AskUserQuestion` — **do not generate a report yet**:

```
question: "「$TOPIC」の調査結果が少なすぎます（GitHub: $GITHUB_COUNT件 / Slack: $SLACK_COUNT件 / Notion: $NOTION_COUNT件）。どうしますか？"
options:
  - "別のキーワードを入力する" → user types a new term; restart from Step 1 with that term
  - "チャンネルを指定する（例: in:#pj_kalmia_robotic-recover）" → user types channel; restart with that filter
  - "担当者の名前で検索する" → user types a person name; restart in person mode
  - "薄いままでもレポートを生成する" → proceed to Step 2 with the thin data; output thin report format
  - "中止する" → stop, output only a brief summary of what was tried
```

#### Cautious report (3–7 results): warning banner

When $TOTAL is 3–7, add this block immediately after the report header:

```markdown
> ⚠️ **証拠不足注意** — この調査は限られた情報源（GitHub: N件 / Slack: N件 / Notion: N件）に基づいています。内容の信頼性が低い可能性があります。別キーワードでの再検索を推奨します。
```

#### Thin report format (when user chooses "薄いままでも生成")

Use this compact format instead of the full template — no synthesis, no PDF:

```markdown
# 調査メモ: $TOPIC（情報不足）
> $TODAY — 注: 証拠が少なく信頼性が低いため、正式レポートではなくメモ形式で出力します。

## 試したキーワード
- "$TOPIC"（元のキーワード）
- "$ALT1"（フォールバック1）
- "$ALT2"（フォールバック2）

## 見つかった情報（断片・未検証）
[bullet list of raw facts found — no synthesis, no confidence claims]

## 調査ソース別結果
| ソース | 件数 | 備考 |
|--------|------|------|
| GitHub | N件 | |
| Notion | N件 | |
| Slack  | N件 | |

## 推奨する次のステップ
- `/research <別のキーワード>` で再検索
- `/research $TOPIC in:#<channel>` でチャンネルを指定
- 担当者が分かれば `/research <person name>` でその人の活動から調査
```

**Do not generate a PDF for thin/memo reports.**

---

### Step 2: Analyze and synthesize

After collecting all results, reason through. **Base everything strictly on what the searches returned — not on session context or prior knowledge.**

1. **What is this?** — What problem does this project/topic solve? Who cares and why?
2. **Who is involved?** — Build the contributor list from **all sources equally weighted**: GitHub PR authors, Slack message authors, Notion assignees/creators. Sort by recency of contribution. Do not weight by proximity to the current user. If the current user appears prominently in search results, treat them the same as any other contributor — do not elevate or suppress.
   - For each contributor, calculate days since last activity. Mark 🔴 in 最終活動 if > 30 days.
3. **What's the technical approach?** — Architecture, key algorithms, tools, languages.
4. **What's the current state?** — In progress, blocked, shipped, experimental?
5. **Health signal** — When was the last meaningful activity? Any explicit blockers mentioned?
   - 🟢 Active: PR/commit/Slack activity within the last 7 days
   - 🟡 Slow: last activity 2–4 weeks ago
   - 🔴 Stalled: no activity > 4 weeks, or an explicit blocker found
6. **What happened recently?** — Last 2–4 weeks of activity.
7. **What's next?** — Open issues, pending PRs, Notion tasks, planned work.
8. **Evidence gaps** — Identify: Notion tasks without assignees, open PRs with no reviewer, Slack threads with no resolution, topics mentioned in passing with no follow-up. These populate `## 不明点`.
9. **Source counts** — Tally: GitHub PRs found, GitHub Issues found, Notion pages fetched, Slack messages found. These go in `## 調査範囲`.
10. **Related projects** — List any other AKARI repos/codenames mentioned alongside `$TOPIC` in the search results. Note the relationship type (依存先, 共有インフラ, 派生).
11. **Activity trend** — For project mode: count PRs per 2-week bucket over the last 8 weeks. If ≥ 6 data points exist, include a `xychart-beta` bar chart.
12. **Contradiction detection** — Compare signals across sources. Flag any inconsistencies explicitly in `## 不明点`:
    - Slack says "詰まった/blocked/問題あり" but GitHub shows recent merges → possible stale message or unlogged fix
    - Notion marks a task "完了/Done" but the related PR is still open → sync gap
    - A contributor is active in Notion/Slack but has no recent GitHub activity → may have shifted roles
    - Two sources name different tools/frameworks for the same component → flag and cite both with dates
13. **Glossary terms** — For project and technical modes: collect AKARI-specific or project-specific jargon seen in the search results that a newcomer wouldn't know (e.g. `melchior`, `PlacoIK`, `WorkSpaceMap`, `Euler cluster`). For each term, extract a brief definition from the search results themselves (PR descriptions, Notion pages, Slack messages). Skip widely known terms (Python, YOLO, Docker, ROS, etc.). These populate `## 用語集` in Templates A and C. Omit the section entirely if all terms are standard.

---

### Step 3: Decide which Mermaid diagrams to include

Use diagrams **only where they genuinely add clarity** — don't force them. Choose from:

| Diagram type | When to use |
|---|---|
| `flowchart TD` | System architecture, data pipeline, decision flow |
| `sequenceDiagram` | How components interact (e.g. robot → VLM → arm) |
| `timeline` | Project history, milestone sequence |
| `gitGraph` | Branch/PR strategy if complex |
| `pie` | Who owns what % of work, or task distribution |
| `xychart-beta` | Activity trend (PR count per 2-week bucket), or metric trends |

Limit to **1–2 diagrams** maximum. Only include if the diagram makes the report easier to understand than prose alone.

For **project mode**: if ≥ 6 PR data points span ≥ 4 weeks, add a `xychart-beta` activity trend chart in `## 活動トレンド`.

---

### Step 4: Write the report

#### 機密情報フィルター（作成前に必ず適用）

以下の情報は**絶対に出力しない**。NDA対象情報のため。

| カテゴリ | 禁止例 | 代替表現 |
|----------|--------|---------|
| クライアント企業名 | （実企業名）、○○株式会社 | 内部PJコードのみ使う（例: kalmia, nile-melchior） |
| 金額・契約額 | （金額）、年間コスト○○円 | 記載しない |
| AWSアカウントID / ARN | `（AWSアカウントID）`、`arn:aws:...` | 記載しない |
| クライアントを特定できるドメイン | client.co.jp、クライアント固有URL | 記載しない |
| NDA対象のビジネス情報 | 調達条件、契約条件、先方事業詳細 | 記載しない |

内部コードネーム（kalmia, nile-melchior 等）・AKARIのGitHubリポジトリ名・チームメンバー名は記載して良い。

---

Save to `~/Desktop/claude-outputs/research/research_$TOPIC_SLUG_$TODAY.md`.

Use the template that matches `$TOPIC_MODE`. Omit any section where no meaningful data exists.

---

#### Template A: Project mode

```markdown
# Research: <$TOPIC>
> <$TODAY> — Sources: GitHub · Notion · Slack

## TL;DR
> Two to four sentences. What is this, what's the current state, what matters most.

---

## 概要 — What is this?
What problem this solves, why it exists, who it's for. Written for someone who has never heard of it.

---

## 関係者 — People
All active contributors, sorted by recency. Equally weighted across GitHub / Slack / Notion — not filtered by who the current user knows.
| 名前 | GitHub | 役割 | 最終活動 | 主な貢献 |
|------|--------|------|---------|---------|
| ![](https://github.com/<handle>.png?size=24) Name | `<handle>` | ... | YYYY-MM-DD | ... |

*(最終活動が30日以上前の場合は日付に 🔴 を付ける)*

---

## 技術スタック — Tech Stack
Key tools, languages, frameworks, and infrastructure. Inferred from repo contents, PR descriptions, and Slack discussions.
| レイヤ | 技術 / ツール |
|--------|-------------|
| ... | ... |

*（根拠: 直近 30 日以内の PR・Slack・Notion）*

---

## 技術概要 — How it works
Key technical approach and architecture. How the components fit together.
Include a Mermaid diagram here if architecture is non-trivial.

---

## 現状とヘルス — Status & Health

> **ステータス:** 🟢 Active / 🟡 Slow / 🔴 Stalled — [one-line reason]

**リスク・懸念:**
- [explicit blockers or open questions found in data]
- If none found: 特になし

---

## 活動トレンド — Activity Trend
*(PR + merge count per 2-week period — include only if ≥ 6 data points over ≥ 4 weeks)*

```xychart-beta
xychart-beta
  title "PR activity (2-week buckets)"
  x-axis ["W1", "W3", "W5", "W7"]
  bar [N, N, N, N]
```

---

## 最近の活動 — Recent Activity (last ~30 days)
Bullets of meaningful events: commits, PRs merged, Slack decisions, Notion updates.
### GitHub
### Slack
### Notion

---

## 意思決定ログ — Key Decisions
*(Slack から抽出した設計・方針・技術選定の決定事項。新規参加者が「なぜそうなっているのか」を理解するための記録)*
*(決定が見つからない場合はこのセクションを省略)*

| 日付 | 決定内容 | 根拠・チャンネル |
|------|---------|--------------|
| YYYY-MM | 〇〇を使うことにした | #channel — 理由: ... |

---

## 関連プロジェクト — Related Projects
Other repos, projects, or tools this project depends on or interacts with. Omit if none found.
| プロジェクト | 関係 | 最終活動 |
|------------|------|---------|
| ... | 依存先 / 共有インフラ / 派生 | ... |

---

## はじめ方 — Getting Started
Concrete first steps for someone joining this project today.

1. **クローン:** `git clone <repo URL>`
2. **最初に読む:** [<Notion page title>](<Notion URL>)
3. **最初に動かす:** `<first runnable command from README or launch/ scripts>` （要確認 if not found）
4. **最初に話す:** <most recently active contributor name>
5. **参加する:** Slack `#<main channel name>`

*（不明な項目は「最初に話す人」に確認）*

---

## 次のステップ — What's Next
Open PRs, pending tasks, planned work inferred from the data.

*(Review bottlenecks: open PRs waiting > 7 days without an approval are marked 🕐)*

| 優先度 | タスク | 担当 | 備考 |
|--------|--------|------|------|
| 高 | 🕐 PR #N — `<title>` | レビュー待ち N日 | open N日、未承認 |

---

## 不明点 — Open Questions
Gaps the search data could not answer — good questions to ask the team.
- [Notion task without assignee]
- [Open PR with no reviewer]
- [Slack thread with no resolution]
- [Section with thin evidence]
- [**矛盾**: Slack では「〇〇が詰まっている」とあるが GitHub では直近マージあり — どちらが最新？]
If no gaps found: 特になし

---

## 用語集 — Glossary
*(このプロジェクト固有の用語・コードネーム。新規参加者向け。一般的な技術用語（Python, YOLO 等）は省略)*
*(プロジェクト固有の用語が見つからない場合はこのセクションを省略)*

| 用語 | 説明 | 出典 |
|------|------|------|
| `melchior` | AKARI 内製シミュレータ | PR body |
| `PlacoIK` | AKARI 独自の逆運動学ソルバー | Notion |

---

## 参照 — References
| Source | Link | 説明 |
|--------|------|------|
| GitHub | [PR #N](url) | ... |
| Notion | [Title](url) | ... |
| Slack | #channel YYYY-MM-DD | ... |

---

## 変更点 — What Changed Since Last Report
*(このセクションは前回レポートが存在する場合のみ記載。存在しない場合は丸ごと省略)*
> 前回レポート: YYYY-MM-DD

- **新規 PR:** ...
- **ステータス変化:** 🟢→🟡 など
- **新規参加者:** ...
- **クローズしたタスク/PR:** ...
- **変化なし:** 上記以外は前回から変更なし

---

## 調査範囲 — Sources Checked
| ソース | 結果件数 | 備考 |
|--------|---------|------|
| GitHub PRs | N件 | |
| GitHub Issues | N件 | |
| Notion pages fetched | N件 | |
| Slack messages | N件 | フォールバック検索「<term>」を使用（該当する場合のみ） |

---
*Generated by /research — review before sharing.*
```

---

#### Template B: Person mode

```markdown
# Research: <$TOPIC>
> <$TODAY> — Sources: GitHub · Notion · Slack

## TL;DR
> Two to three sentences: who this person is, what team, what they're currently working on.

---

## プロフィール — Profile
Role, team, background. Source from Notion member page if available.
| 項目 | 内容 |
|------|------|
| 役職 | ... |
| 所属 | ... |
| GitHub | `<handle>` |
| 経歴 | ... (brief, from Notion bio) |

---

## 担当プロジェクト — Projects
What this person works on, sorted by recency of activity. Inferred from GitHub PRs, Notion tasks, Slack channels.
| プロジェクト | 役割 | 最終活動 |
|------------|------|---------|
| ... | ... | ... |

---

## 最近の活動 — Recent Activity (last ~30 days)
Neutral view — what this person has contributed, not filtered through the current user's lens.
### GitHub
### Slack
### Notion

---

## 得意領域 — Expertise
Inferred from PR topics, commit subjects, and Slack discussion patterns — not from the current user's subjective view.
- [topic area]: [evidence — e.g. "5 PRs on X in the last 2 months"]

---

## 不明点 — Open Questions
Gaps the search data could not answer.
- [projects mentioned with no detail]
- [Notion tasks with no status]
If no gaps found: 特になし

---

## 参照 — References
| Source | Link | 説明 |
|--------|------|------|

---

## 調査範囲 — Sources Checked
| ソース | 結果件数 |
|--------|---------|
| GitHub PRs / commits | N件 |
| Notion pages fetched | N件 |
| Slack messages | N件 |

---
*Generated by /research — review before sharing.*
```

---

#### Template C: Technical topic mode

```markdown
# Research: <$TOPIC>
> <$TODAY> — Sources: GitHub · Notion · Slack

## TL;DR
> Two to three sentences: what this concept/technique is, where it's used at AKARI, who the main experts are.

---

## 概要 — What is this?
Explain the concept itself. Assume the reader is an engineer but unfamiliar with this specific topic.

---

## どこで使われているか — Where it's used
Repos, files, and functions where this topic appears. Source from GitHub code search and PR history.
| リポジトリ | ファイル / モジュール | 用途 |
|-----------|-------------------|------|
| ... | ... | ... |

---

## 誰が詳しいか — Who to ask
Top contributors to relevant code and discussions. Equally weighted from GitHub + Slack + Notion.
| 名前 | GitHub | 根拠 |
|------|--------|------|
| ... | `<handle>` | ... PRs / ... Slack messages on this topic |

---

## 現状とヘルス — Status & Health

> **ステータス:** 🟢 Active / 🟡 Slow / 🔴 Stalled — [one-line reason]

**リスク・懸念:**
- [open issues, known bugs, unresolved questions]

---

## 最近の活動 — Recent Activity (last ~30 days)
### GitHub
### Slack
### Notion

---

## 不明点 — Open Questions
Gaps the search data could not answer.
- [open questions or unresolved threads]
- [**矛盾**: 複数ソース間で情報が食い違っている点]
If no gaps found: 特になし

---

## 用語集 — Glossary
*(このトピック固有の用語。一般的な技術用語は省略)*
*(固有用語が見つからない場合はこのセクションを省略)*

| 用語 | 説明 | 出典 |
|------|------|------|
| ... | ... | ... |

---

## 参照 — References
| Source | Link | 説明 |
|--------|------|------|

---

## 調査範囲 — Sources Checked
| ソース | 結果件数 |
|--------|---------|
| GitHub PRs / code search | N件 |
| Notion pages fetched | N件 |
| Slack messages | N件 |

---
*Generated by /research — review before sharing.*
```

---

**Writing rules (all modes):**
- Write in Japanese where natural (section content), English for technical terms and code
- Be precise but accessible — assume the reader is a smart engineer unfamiliar with this project
- Bold key terms on first use
- Cite specific evidence: PR numbers, Notion page titles, Slack dates — don't make things up
- **Thin evidence:** if a section has < 2 independent sources, add an italic note: *（情報源が少ないため不確実）*. Do not pad.
- Tables > prose for lists of people, references, task status
- **Staleness:** in the People table, append 🔴 to 最終活動 dates that are > 30 days ago
- **GitHub avatars:** in people tables, prepend `![](https://github.com/<handle>.png?size=24)` before the name if the GitHub handle is known
- **Section dividers:** use `---` between every major `##` section
- **TL;DR and Status badge:** render as `>` blockquotes (callout style in PDF)
- **Do not mention or infer gender** — never use he/she/her/his/彼/彼女 or any gendered language. Refer to people by name or role only (e.g. "Rumina は〜" not "彼女は〜")
- **Never include raw system IDs** — no Slack user IDs (e.g. `U060UHXD48K`), no Notion page UUIDs. Use display names, channel names (e.g. `#dev-team-service-squad`), and Notion page titles with their URL instead.

---

### Step 5: Save as .md and .pdf

After writing the `.md` file, generate a PDF using the Mermaid pipeline script:

```bash
python3 ~/.claude/scripts/md-to-pdf-with-mermaid.py \
  ~/Desktop/claude-outputs/research/research_$TOPIC_SLUG_$TODAY.md
```

This script:
1. Renders each `mermaid` code block to a PNG via `@mermaid-js/mermaid-cli`
2. Substitutes `<img>` tags pointing to the PNGs
3. Runs `md-to-pdf` with `~/.claude/scripts/md-to-pdf-config.js`
4. Cleans up temp files

PNG files land in `~/Desktop/claude-outputs/research/diagrams/`.

Both output files:
- `~/Desktop/claude-outputs/research/research_$TOPIC_SLUG_$TODAY.md`
- `~/Desktop/claude-outputs/research/research_$TOPIC_SLUG_$TODAY.pdf`

### Step 6: Report back

Show the full report text in conversation. Tell the user both file paths (.md and .pdf). Note any sources that returned no results. State which `$TOPIC_MODE` was detected.
