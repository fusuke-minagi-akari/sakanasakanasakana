---
description: Generate a 日報 from today's git activity, Slack channel group messages, Notion activity, and optional user input — in the team's actual format
---

Generate a 日報 based on today's git activity, Slack messages (channel groups + broad search), Notion activity, Claude Code session history, and optional user input.

## Arguments

$ARGUMENTS

Arguments are optional. If provided, they may include:
- `稼働時間: ...` — working hours (e.g. "10:00-19:00")
- `次: ...` — what to do next
- `困っていること: ...` — blockers or concerns
- Extra context about what you worked on

---

## Instructions

### Step 0: Identity bootstrap

Read `~/.claude/scripts/standup_config.json` using the Read tool.

- If the file **exists** and contains `slack_user_id` and `notion_user_id`: load values.
- If missing either ID: follow the same discovery process as `/standup` Step 0 (call `slack_read_user_profile`, `notion-get-users`), then save the config.

Also check for `nippo_mentor_id` in the config. If missing:
- Default to `<MENTOR_SLACK_ID>` (<mentor name>) and save it to the config.

Load:
- `$SLACK_USER_ID` — the user's Slack ID
- `$NOTION_USER_ID` — the user's Notion user ID
- `$MENTOR_ID` — mentor's Slack ID (for mention in nippo)

---

### Step 0b: Channel groups setup

Check if `channel_groups` key exists in the config. It should look like:

```json
"channel_groups": {
  "onboarding-relevant": {
    "channel_ids": ["C...", "C..."],
    "channel_names": ["team_onboarding_fusuke-minagi", "1_team_onboarding_teammate"]
  },
  "dx dev simulation specific": {
    "channel_ids": ["C...", "C..."],
    "channel_names": ["pj_mithril-robot", "team_sim-domain1-arm"]
  }
}
```

**If `channel_groups` is missing or empty**, run channel discovery:

1. Run these `slack_search_channels` calls **in parallel**:
   - query: `"onboarding"` with `channel_types: "public_channel,private_channel"`, `limit: 10`
   - query: `"mithril simulation"` with `channel_types: "public_channel,private_channel"`, `limit: 10`
   - query: `"sim domain"` with `channel_types: "public_channel,private_channel"`, `limit: 10`

2. From results, build candidate channel lists for each group based on name patterns:
   - `onboarding-relevant`: channels with "onboarding" in name
   - `dx dev simulation specific`: channels with "mithril", "sim", "domain", or "pj_" in name

3. Auto-save the discovered channels to `standup_config.json` under `channel_groups`, including both channel IDs and names.

4. If channel IDs are unknown (search returned names only), resolve them via additional `slack_search_channels` calls for exact names, then save.

Load:
- `$CHANNEL_GROUPS` — map of group name → `{channel_ids, channel_names}`

---

### Step 1: Gather all sources — run Steps 1–4 simultaneously

**Execute Steps 1, 2, 3, and 4 simultaneously.** Merge results after all complete.

---

#### Step 1: Git activity

##### Resolve git identity
```bash
git config --global user.name
git config --global user.email
```

##### Git commits

Read repo list from `~/.claude/scripts/standup_repos.txt` (one path per line).

For each repo:

1. Verify the user has commits in this repo:
   ```bash
   git -C <repo_path> log --author="$GIT_AUTHOR" -1 --format="%an" 2>/dev/null
   ```
   Skip if empty.

2. Get today's commits:
   ```bash
   git -C <repo_path> log --author="$GIT_AUTHOR" --since="today 00:00" --format="%h %s" --no-merges 2>/dev/null
   ```

3. Read diffs for each commit:
   ```bash
   git -C <repo_path> show <hash> --stat --format="%h %s" 2>/dev/null
   ```

4. Check uncommitted work (only if user has commits in this repo):
   ```bash
   git -C <repo_path> diff --stat HEAD 2>/dev/null | tail -1
   ```

---

#### Step 2: Slack activity

Run **2a and 2b in parallel**.

##### 2a: Broad search (user's messages across all channels today)

Use `slack_search_public_and_private`:
- query: `from:<@$SLACK_USER_ID> after:YYYY-MM-DD before:YYYY-MM-DD` (today)
- `response_format: "concise"`, `limit: 15`, `include_context: false`, `sort: "timestamp"`

Skip trivial messages (greetings, single emoji, "ok", "確認").

##### 2b: Channel group deep read

For each channel in each `$CHANNEL_GROUPS` group (all in parallel), run **2 searches per channel simultaneously**:

1. **User's sent messages in channel:**
   - query: `from:<@$SLACK_USER_ID> in:#<channel_name> after:YYYY-MM-DD`
   - `response_format: "concise"`, `limit: 10`, `include_context: false`

2. **User's mentions / involvement in channel:**
   - query: `<@$SLACK_USER_ID> in:#<channel_name> after:YYYY-MM-DD`
   - `response_format: "concise"`, `limit: 10`, `include_context: true`, `max_context_length: 200`

De-duplicate against 2a results. Merge into a single list grouped by channel group name.

This surfaces context even when the user is mentioned but didn't write (e.g., someone asked them a question, or they were added to a thread).

---

#### Step 3: Notion activity

Run **3a and 3b in parallel**.

##### 3a: Pages created or updated by user today

Use `notion-search`:
```json
{
  "query": "作業 タスク 進捗",
  "query_type": "internal",
  "filters": {
    "created_date_range": {
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD"
    },
    "created_by_user_ids": ["$NOTION_USER_ID"]
  },
  "page_size": 10,
  "max_highlight_length": 150
}
```

Also run a second `notion-search` with a broader query (no creator filter, but date filter today) to catch pages the user edited but didn't create:
```json
{
  "query": "今日 更新 作業",
  "query_type": "internal",
  "filters": {
    "created_date_range": {
      "start_date": "YYYY-MM-DD",
      "end_date": "YYYY-MM-DD"
    }
  },
  "page_size": 10,
  "max_highlight_length": 150
}
```

##### 3b: Meeting notes today

Use `notion-query-meeting-notes` with filter for today:
```json
{
  "filter": {
    "operator": "and",
    "filters": [
      {
        "property": "created_time",
        "filter": {
          "operator": "date_range",
          "value": {
            "type": "exact",
            "value": {
              "type": "daterange",
              "start_date": "YYYY-MM-DD",
              "end_date": "YYYY-MM-DD"
            }
          }
        }
      }
    ]
  }
}
```

Extract: meeting titles, attendees, key action items or topics from today's meetings.

---

#### Step 4: Claude Code session context

```bash
ls -lt ~/.claude/projects/*/sessions/*/transcript.jsonl 2>/dev/null | head -10
```

Scan the most recent session transcript for today's non-git work (research, debugging, planning, code review, tool setup, etc.). Keep it brief — extract only what's meaningfully different from git/Slack/Notion activity.

---

### Step 4.5: Assess source quality + automatic Slack fallback

After all parallel steps complete, tally:

- `$GIT_COUNT` = total commits found today across all repos
- `$SLACK_COUNT` = non-trivial messages from 2a + 2b combined (0 if MCP unavailable)
- `$NOTION_COUNT` = distinct Notion pages/meetings found today (0 if none/MCP unavailable)
- `$SESSION_TASKS` = distinct non-git tasks from Claude Code session (0 if none)

#### Automatic Slack fallback

If `$SLACK_COUNT < 3` AND `slack_search_public_and_private` is available:

Extract the 2 most distinctive keywords from today's git commits or Notion pages (e.g. `detect_fallen`, `YOLO`, `VLM`). Run up to 2 alternate Slack searches **in parallel**:

```
slack_search_public_and_private query="from:<@$SLACK_USER_ID> <keyword1>" response_format="concise" limit=10
slack_search_public_and_private query="from:<@$SLACK_USER_ID> <keyword2>" response_format="concise" limit=10
```

Merge any new non-trivial messages in.

#### If zero commits AND zero Slack messages AND zero Notion

Extend the git search window to `--since="yesterday 00:00"` and try once more. Note in やったこと: `（本日コミットなし・前日分を参照）`.

---

### Step 4.8: Ask for supplemental URLs or images

After gathering all context, use `AskUserQuestion`:

```
questions:
  - question: "URLや画像があれば共有してください（PR、Notion、スクリーンショット等）"
    header: "補足資料"
    multiSelect: false
    options:
      - label: "スキップ"
        description: "補足なし。このまま日報を作成します。"
      - label: "URLを貼る"
        description: "GitHub PR・Notion・Qiita 等のリンクを追記します。"
      - label: "画像を貼る"
        description: "スクリーンショットや図をパスで指定します。"
      - label: "URLも画像も貼る"
        description: "両方を追記します。"
```

- If **スキップ**: proceed immediately.
- If **URLを貼る** or **URLも画像も貼る**: user types URLs in "Other" field.
  - GitHub PR/issue URL → `gh pr view <url>` or `gh issue view <url>` via Bash
  - Notion URL → `notion-fetch` with page ID from URL
  - Any other URL → `WebFetch`
  - File under appropriate section (やったこと / 次やること / 困っていること)
- If **画像を貼る** or **URLも画像も貼る**: user provides file path. Use `Read` — Claude is multimodal.

---

### Step 5: Compose the 日報

#### 機密情報フィルター（作成前に必ず適用）

| カテゴリ | 禁止例 | 代替表現 |
|----------|--------|---------|
| クライアント企業名 | （実企業名）、○○株式会社 | 内部PJコードのみ（例: kalmia, nile-melchior） |
| 金額・契約額 | （金額） | 記載しない |
| AWSアカウントID / ARN | `（AWSアカウントID）` | 記載しない |
| クライアントを特定できるドメイン | client.co.jp | 記載しない |
| NDA対象のビジネス情報 | 調達条件、契約条件 | 記載しない |

内部コードネーム（kalmia, nile-melchior 等）・AKARIのGitHubリポジトリ名・チームメンバー名は記載して良い。

---

Use the **exact format** from `#team_onboarding_fusuke-minagi`:

```
日報 YYYY-MM-DD (曜日)
<@MENTOR_ID>

稼働時間
<from arguments, or leave blank>

やったこと

- カテゴリ1（例: Kalmia, Claude, 共通業務）
    - 具体的な作業内容
    - 具体的な作業内容
- カテゴリ2
    - 具体的な作業内容

次やること
- <inferred from WIP diffs, open PRs, Notion TODOs, or arguments>

困っていること
- <from arguments, or "特になし">
```

#### Format rules

- **Header**: plain text `日報 YYYY-MM-DD (曜日)` — no `#` markdown
- **Mentor**: `<@$MENTOR_ID>` on line 2 — always include
- **稼働時間**: use argument if provided; otherwise leave blank
- **やったこと**: group by project/category with `-` bullets and 4-space indented sub-bullets
  - Include repo name in category if multiple repos
  - Translate commit messages into readable Japanese
  - Include non-git work from Slack, Notion, and session
  - Include meetings from Notion meeting notes (brief: meeting name + outcome)
  - One sub-bullet per distinct task; be specific but concise
- **次やること**: infer from uncommitted WIP, open PRs, Notion TODOs, or `次:` argument
- **困っていること**: use `困っていること:` argument, or `特になし`

---

### Step 6: Save as .md and .pdf

1. Save to `~/Desktop/claude-outputs/nippo/nippo_YYYY-MM-DD.md`
2. Generate PDF:
   ```bash
   python3 ~/.claude/scripts/md-to-pdf-with-mermaid.py \
     ~/Desktop/claude-outputs/nippo/nippo_YYYY-MM-DD.md
   ```
3. Show the full text in conversation
4. Tell the user both file paths and to copy-paste the **plain text** into `#team_onboarding_fusuke-minagi`
5. Report source coverage (not part of Slack-paste text):
   ```
   調査範囲: git ($GIT_COUNT件) · Slack ($SLACK_COUNT件) · Notion ($NOTION_COUNT件) · session ($SESSION_TASKS件)
   ```
   If any source was unavailable:
   ```
   ⚠️ <source> MCP が応答しませんでした。
   ```
