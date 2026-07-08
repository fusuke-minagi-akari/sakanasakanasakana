---
description: Generate a Slack-ready standup update from recent git, GitHub, Slack, and Notion activity
---

Generate a standup update in the team's format for `#dev_team_simulation_per`.

## Arguments

$ARGUMENTS

Arguments are optional. If provided, they may include:
- `search: <text>` — keyword search mode: find matching content across all sources (last 30 days)
- Any unrecognized free text (no `key:` prefix) → treated as implicit `search:` terms
- Extra repo paths to scan (in addition to the config file)

---

## Instructions

### Step 0: Identity bootstrap

Read `~/.claude/scripts/standup_config.json` using the Read tool.

- If the file **exists** and contains both `slack_user_id` and `notion_user_id`: load those values as `$SLACK_USER_ID` and `$NOTION_USER_ID`. Done.
- If the file **does not exist** or is missing either ID:
  1. **Slack ID**: call `slack_read_user_profile` with no arguments → the current user's profile → extract `id` (e.g. `U012ABC3DEF`) and `real_name`
  2. **Notion ID**: call `notion-get-users` with `user_id: "self"` → extract `id` (UUID) and `name`
  3. Write `~/.claude/scripts/standup_config.json` with the Write tool:
     ```json
     {
       "slack_user_id": "<extracted>",
       "slack_display_name": "<extracted real_name>",
       "notion_user_id": "<extracted uuid>",
       "notion_user_name": "<extracted name>",
       "last_updated": "<YYYY-MM-DD>"
     }
     ```
  4. Announce: "Identity saved to `~/.claude/scripts/standup_config.json` — won't need to look up again next time."
  5. Use the extracted IDs as `$SLACK_USER_ID` and `$NOTION_USER_ID` for the rest of this run.

---

### Step 0.5: Parse arguments and determine date range

#### Parse arguments

| Pattern | Action |
|---------|--------|
| `search: <text>` | Set `$SEARCH_TERMS` to `<text>` |
| Free text with no `key:` prefix | Set `$SEARCH_TERMS` to that text |
| Extra paths (start with `/` or `~`) | Add to repo scan list |

If `$SEARCH_TERMS` is non-empty → **keyword search mode** (skip date range logic, use last 30 days).
If `$SEARCH_TERMS` is empty → **normal standup mode** — continue with date range logic below.

#### Date range logic (normal mode only)

```bash
TODAY=$(date +%Y-%m-%d)
DOW=$(date +%u)   # 1=Mon … 7=Sun
```

**Step A — Walk backwards to find `$SINCE_DATE`:**

Starting from yesterday, walk day by day backwards. For each date, determine if it is a non-working day:
- **Weekend**: Saturday (DOW=6) or Sunday (DOW=7)
- **Japanese national holiday**: Use your knowledge of Japan's public holiday schedule, including 振替休日 rules (when a fixed-date holiday falls on Sunday, the following Monday becomes a substitute holiday). Key fixed holidays: 元日 1/1, 建国記念日 2/11, 天皇誕生日 2/23, 昭和の日 4/29, 憲法記念日 5/3, みどりの日 5/4, こどもの日 5/5, 海の日 (3rd Mon Jul), 山の日 8/11, 敬老の日 (3rd Mon Sep), 秋分の日 (≈9/22–23), スポーツの日 (2nd Mon Oct), 文化の日 11/3, 勤労感謝の日 11/23. Also account for 国民の休日 (bridge holiday: when a non-holiday weekday is sandwiched between two holidays).

Keep walking backwards until you reach a working day. That date is `$PREV_WORKING_DAY`. Set `$SINCE_DATE = $PREV_WORKING_DAY`.

Examples:
- Today = Monday (no holidays) → `$SINCE_DATE` = last Friday
- Today = Tuesday after a Monday holiday → `$SINCE_DATE` = last Friday
- Today = Tuesday after 5/3–5/5 連休 → `$SINCE_DATE` = last Friday before the 連休

**Step B — Classify the period:**

Count the gap between `$SINCE_DATE` and today:
- 1 day gap (yesterday was a working day): `$PERIOD_LABEL = "昨日"` — no special note
- 2–3 day gap (weekend only): `$PERIOD_LABEL = "週末 (M/D–M/D)"`
- 1+ holidays involved: `$PERIOD_LABEL = "連休 (M/D–M/D)"`

Set `$NONWORKING_START` = the day after `$SINCE_DATE` (first non-working day).

**Step C — Detect holiday work:**

After gathering all activity (Steps 1–4), check whether any activity occurred during `$NONWORKING_START` → yesterday:
- If **yes**: update label to `$PERIOD_LABEL += "（休日中作業あり）"` and combine all activity
- If **no**: only report `$SINCE_DATE` activity; mention "休日中は作業なし" only if the gap was ≥ 2 days

**Step D — Fallback (zero activity):**

If after all steps, **no activity is found anywhere** (no commits, no PRs, no Slack, no Notion), extend `$SINCE_DATE` back by one more working day (skipping weekends/holidays) and re-run Steps 1–4 once. Note in output: "（前営業日まで遡りました）".

---

### Step 0.8: Fetch today's weather

Use `WebFetch` to retrieve current weather for **Tokyo** (the user's location):

```
https://wttr.in/Tokyo?format=j1
```

Extract from the JSON:
- `current_condition[0].weatherDesc[0].value` — weather description (e.g. "Sunny", "Overcast", "Light rain")
- `current_condition[0].temp_C` — temperature in °C
- `current_condition[0].FeelsLikeC` — feels-like temperature

Store as `$WEATHER_DESC`, `$WEATHER_TEMP`, `$WEATHER_FEELS`.

If the fetch fails (network error, timeout), skip silently — treat weather as unknown.

---

### Step 1: Gather all sources — run Steps 1–4 in parallel

**Execute Steps 1, 2, 3, and 4 simultaneously** where the tool supports it. Do not wait for git before starting Slack; do not wait for Slack before starting Notion. Merge results after all calls complete.

#### Step 1: Git activity

Read the repo list from `~/.claude/scripts/standup_repos.txt` (one path per line), plus any extra paths from arguments.

Also resolve git author identity:
```bash
git config --global user.name
git config --global user.email
```

**Normal mode** — for each repo:
1. Verify the user has commits (skip if not):
   ```bash
   git -C <repo_path> log --author="$GIT_AUTHOR" -1 --format="%an" 2>/dev/null
   ```
2. Get commit hashes since `$SINCE_DATE`:
   ```bash
   git -C <repo_path> log --author="$GIT_AUTHOR" --since="$SINCE_DATE 00:00" --format="%h %ad" --date=short --no-merges 2>/dev/null
   ```
   Note each commit's date so you can later classify it as "working day" vs "non-working day".
3. Read the actual diff for each commit:
   ```bash
   git -C <repo_path> show <hash> --stat --format="%h %s" 2>/dev/null
   git -C <repo_path> show <hash> --format="" --no-stat -p 2>/dev/null
   ```
4. Check uncommitted work (always, regardless of commit history):
   ```bash
   git -C <repo_path> diff --stat HEAD 2>/dev/null | tail -1
   git -C <repo_path> diff HEAD 2>/dev/null
   ```

**Keyword search mode** — scan all repos regardless of recent commit history, last 30 days:
```bash
# Match in commit messages
git -C <repo_path> log --author="$GIT_AUTHOR" --since="30 days ago" \
  --grep="$SEARCH_TERMS" --format="%h %ad %s" --date=short --no-merges 2>/dev/null

# Match in diff content (lines added/removed containing the term)
git -C <repo_path> log --author="$GIT_AUTHOR" --since="30 days ago" \
  -S"$SEARCH_TERMS" --format="%h %ad %s" --date=short --no-merges 2>/dev/null
```
For any matching hashes, show `--stat` to summarize what files changed.

---

#### Step 2: GitHub activity

**Normal mode** only (skip in keyword search mode unless `$SEARCH_TERMS` relates to PRs/issues):

```bash
# Recent PRs by the user
gh search prs --author @me --sort updated --order desc \
  --json number,title,repository,state,url,updatedAt --limit 10 2>/dev/null

# PRs awaiting the user's review
gh search prs --review-requested @me --sort updated --order desc \
  --json number,title,repository,state,url,updatedAt --limit 5 2>/dev/null
```

Filter to items where `updatedAt` >= `$SINCE_DATE`. Skip stale PRs.

---

#### Step 3: Slack activity

Use the `slack_search_public_and_private` MCP tool.

**Normal mode:**
1. User's messages since `$SINCE_DATE` in the kalmia channel:
   - query: `from:<@$SLACK_USER_ID> in:<#C0EXAMPLEID> after:$SINCE_DATE before:$TODAY`
   - `response_format: "concise"`, `limit: 15`, `include_context: false`
2. User's messages across all channels since `$SINCE_DATE`:
   - query: `from:<@$SLACK_USER_ID> after:$SINCE_DATE before:$TODAY`
   - `response_format: "concise"`, `limit: 15`, `include_context: false`

Note the date of each message. Messages on non-working days count as "holiday work".

**Keyword search mode:**
1. User's messages matching the terms (no date limit):
   - query: `from:<@$SLACK_USER_ID> $SEARCH_TERMS`
   - `response_format: "concise"`, `limit: 10`, `include_context: true`
2. Channel-wide discussion matching the terms (catches threads the user was part of):
   - query: `in:<#C0EXAMPLEID> $SEARCH_TERMS`
   - `response_format: "concise"`, `limit: 10`, `include_context: true`, `max_context_length: 300`

In both modes, skip trivial messages (greetings, single emoji, "ok", "confirmed").

---

#### Step 4: Notion context

Use `notion-search` and `notion-fetch` MCP tools.

**Normal mode** — find active tasks to inform today's plan:
1. Active kalmia/robot tasks with recent timestamps:
   - `notion-search` query: `kalmia robot`, query_type: internal, page_size: 5, max_highlight_length: 100
   - Note titles updated in the last 3 days — these likely represent ongoing work
2. If the above yields little, also search:
   - `notion-search` query: `simulation dev task`, query_type: internal, page_size: 4, max_highlight_length: 100

Keep this lightweight — just titles and timestamps. Only fetch full content if a title is ambiguous.

**Keyword search mode:**
1. Search directly for `$SEARCH_TERMS`:
   - `notion-search` query: `$SEARCH_TERMS`, query_type: internal, page_size: 5, max_highlight_length: 200
2. For each result that looks like a task/spec page, fetch it for a snippet:
   - `notion-fetch` with the page ID
   - Extract the first 3-5 relevant lines

Use `$NOTION_USER_ID` from config with `created_by_user_ids` filter if results are too broad.

---

---

### Step 4.5: Assess source quality + automatic Slack fallback

After all parallel searches complete, tally meaningful results:

- `$GIT_COUNT` = total commits found across all repos
- `$SLACK_COUNT` = non-trivial Slack messages found (0 if MCP unavailable)
- `$NOTION_COUNT` = Notion pages found (0 if MCP unavailable)

#### Automatic Slack fallback (normal mode only)

If `$SLACK_COUNT < 3` AND `slack_search_public_and_private` is available:

Extract the 2 most distinctive keywords from git commit messages (e.g. `detect_fallen`, `YOLO`, `VLM`, `缶`). Run up to 2 alternate Slack searches **in parallel**:

```
slack_search_public_and_private query="from:<@$SLACK_USER_ID> <keyword1>" response_format="concise" limit=10
slack_search_public_and_private query="from:<@$SLACK_USER_ID> <keyword2>" response_format="concise" limit=10
```

Merge any new non-trivial messages into `$SLACK_COUNT`. Note which fallback keyword was used.

#### Source transparency

Track which sources returned data:
- `$SOURCES_USED` = comma-separated list of sources with results (e.g. `git, GitHub, Slack`)
- `$SOURCES_FAILED` = sources that returned 0 results or were unavailable (e.g. `Notion (MCP unavailable)`)

This will be appended as a compact note at the end of the output (see Step 5).

---

### Step 5: Compose output

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

**Normal standup mode** — write `~/Desktop/claude-outputs/standup/standup_YYYY-MM-DD.txt`.

#### Format (match team style exactly)

```
YYYY/MM/DD（曜日）
<greeting>
• ProjectName
    ◦ タスク1
    ◦ タスク2
        ▪ サブタスク（必要な場合のみ）
• 別プロジェクト
    ◦ タスク
```

Use actual Unicode: `•` (U+2022), `◦` (U+25E6), `▪` (U+25AA). Indent with 4 spaces per level.

#### Date line

Format: `YYYY/MM/DD（曜日）` — e.g. `2026/04/13（月）`

If today is the first day back after a weekend/holiday gap ≥ 2 days, append a note on the greeting line rather than the date line.

#### Greeting line

One short casual line — same style as the user's past posts (mix of Japanese and English, personal remark).

**Base the greeting primarily on today's weather** (`$WEATHER_DESC` + `$WEATHER_TEMP`):

| Weather | Example greeting |
|---------|-----------------|
| Sunny / Clear, warm (≥18°C) | `いい天気ですね。` / `気持ちいい陽気です。` |
| Hot (≥28°C) | `暑くなってきました。` / `もう夏みたいですね。` |
| Cloudy | `どんよりしてますが頑張ります。` |
| Rain / Drizzle | `雨ですね。` / `傘忘れずに。` |
| Heavy rain / Storm | `土砂降りです。` / `外出たくない天気ですね。` |
| Cold (≤8°C) | `寒いですね。` / `まだ冬みたいな気温です。` |
| Snow | `雪が降ってます！` |
| Unknown (fetch failed) | Fall back to day/season heuristic below |

**Layer in day/situation naturally** (one phrase, not two separate sentences):
- Monday or post-holiday + nice weather → `週明けですが、いい天気なので気分は上々です。`
- Friday + rain → `花金なのに雨ですね。`
- If worked through holiday → mention it naturally: `週末も少し動いてたので、${weather comment}です。`

**Rules:**
- One sentence max — weather comment and day context merged naturally, not concatenated
- Casual, in the user's voice — not formal, not stiff
- No emojis

#### Project sections (today's plan)

Infer what to work on TODAY from all gathered sources:

| Signal | → Today's task |
|--------|----------------|
| Uncommitted git diff in repo X | "続き" of whatever that diff is doing |
| Open PR needing attention | レビュー / 修正 / マージ対応 |
| Recent commit that's a partial fix | 続きの実装 / テスト / コミット |
| Slack discussion about a topic | 関連タスクの継続 |
| Notion task with recent timestamp | そのタスクの進捗 |

Group tasks by **project name** (use the user's own project name conventions: Kalmia, Claude, Jetson, 共通業務, 私用, etc. — infer from the repo names and Slack context).

**Task writing style:**
- Action verbs, present/future tense: 〜する, 〜を進める, 〜の続き
- Concise — one line per task where possible
- Sub-bullets only when a task has genuinely distinct sub-steps
- 3–6 tasks total across all projects is typical; don't over-list

**If $SINCE_DATE gap was ≥ 2 days and no holiday activity found:** add `（週末・連休中は作業なし）` as the last bullet under the most relevant project, or as a standalone line after the greeting if all projects are on hold.

#### Example output

```
2026/04/14（火）
週明けです。
• Kalmia
    ◦ 倒れ缶検出 SPEC.md の変更をコミット・PR 作成
    ◦ 缶アセット Deformation / Rescale バグ修正
    ◦ PR #14（Qwen VLM 2D-bbox [Jetson/Mac/Euler]）対応
• daily-task-assistant
    ◦ README の続き書いてコミット
• 共通業務
    ◦ AirCourse 残り進める
```

---

**Keyword search mode** — write `~/Desktop/claude-outputs/standup/standup_YYYY-MM-DD_search-<terms>.txt`:

```
Search: "<terms>" — YYYY-MM-DD

Git matches (last 30 days):
• [<repo>] <date> — <commit summary> (<hash>)

Slack matches:
• <date> in #<channel>: <message summary>

Notion matches:
• <page title> — <highlight snippet>
```

If no matches for a source: `• No matches found.`

---

### Step 6: Save and report

Show the full output text in the conversation. Tell the user where it was saved. Remind them to review the greeting line and copy-paste into `#dev_team_simulation_per`.

Also report source coverage in a compact line (not part of the Slack-paste text):

```
調査範囲: git ($GIT_COUNT件) · GitHub ($GH_COUNT件) · Slack ($SLACK_COUNT件) · Notion ($NOTION_COUNT件)
```

If any source returned 0 results due to MCP unavailability (not just empty results), note it:
```
⚠️ Slack / Notion MCP が応答しませんでした。git + GitHub のみ。
```
