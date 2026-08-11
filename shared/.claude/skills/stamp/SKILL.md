---
name: stamp
description: Slackのリンク（メッセージ/スレッド/チャンネル）から文脈を読み、そのチャンネルの文化に合う既存スタンプを選んでリアクションを付ける。
argument-hint: <slack-url> [--dry-run]
---

# /stamp — Slackメッセージに最適なスタンプを押す

`$ARGUMENTS` = Slack permalink（+ 任意で `--dry-run`）。

## 1. URLをパース

`https://<ws>.slack.com/archives/<CHANNEL_ID>/p<TS>` →
- channel_id = `C...` / `D...`
- message_ts = `p1234567890123456` → `1234567890.123456`（後ろ6桁の前に `.`）
- `?thread_ts=X` があればスレッド返信。無ければ親メッセージ
- `/archives/<CHANNEL_ID>` のみ（`p...` 無し）→ チャンネル最新メッセージ群が対象。どれに押すか曖昧なら聞く

## 2. 文脈を読む

1. `slack_read_thread(channel_id, message_ts)` — 対象メッセージ + スレッド
2. `slack_read_channel(channel_id, limit=15)` — **周辺文脈 + チャンネル文化**（重要）
3. 対象が既に押されているスタンプを確認（`slack_read_thread` の detailed に含まれる）

### 外部リンクの中身

メッセージ本文がリンクだけの場合、中身を読まないと選べない。

| リンク | 取得方法 |
|--------|---------|
| x.com / twitter.com | `WebFetch https://api.fxtwitter.com/i/status/<ID>` — **x.com 直fetchは402で失敗する**。本文・引用元本文・`media.all[].url`（画像URL）が取れる。画像の中身が本題の場合は下記「X画像」参照 |
| GitHub | `gh` CLI |
| Notion | `notion-fetch` |
| その他 | `WebFetch` |
| 取得不能 | 諦めて文脈のみで判断。無理に内容を推測しない |

添付画像のみのメッセージ → `slack_read_file` で読む。

### X画像（本文が1行でも画像に本題があることが多い）

```
WebFetch https://api.fxtwitter.com/i/status/<ID>   # 本文 + 引用元 + media.all[].url
curl -s -o <scratchpad>/x1.jpg "https://pbs.twimg.com/media/<ID>.jpg?name=orig"
Read <scratchpad>/x1.jpg                            # 画像として読める
```

- **引用元ツイートの画像も落とす**（`tweet.quote.media.all`）。文脈の半分がそこにある
- `?name=orig` を付けないと縮小版
- `pbs.twimg.com` への `curl -s` は settings.json の allow 済み。それ以外のホストは deny に当たる可能性あり → 落ちたら本文のみで判断し「画像未確認」と明記
- スクショの縦長ツイートは1枚ずつ Read（複数枚を1回で読ませようとしない）

## 3. スタンプを選ぶ

### 全スタンプは列挙できない（重要）

`slack_search_emojis` は **1回200件でアルファベット順に打ち切られる**（`a` で検索 → `:baba:` 付近で切れる）。ページングなし。ワークスペースのカスタム絵文字は数千件規模なので **全件把握は不可能**。全件が本当に必要なら Slack Web API `emoji.list`（`emoji:read` スコープのトークン）が必要 —— このMCPには無い。

代わりに:

1. **`slack_read_channel` の Reactions 欄** = そのチャンネルで実際に使われているスタンプ = 文化。一次ソース。
2. **メッセージの語彙そのものを検索語にする。** 汎用の褒めスタンプ（`sugoi`,`tensai`）だけでなく、本文のキーワードを直接引く。カンマ区切りで一括。
   - **ローマ字とかな/漢字の両方で引く。** 絵文字名は `:ギャル:` `:完全に_理解した:` `:解決_済み:` のように日本語のものもあり、ローマ字検索では絶対に出ない。これを飛ばすと最適なスタンプを見逃す
3. 感情バケットも引く: `kusa`(笑) / `omaetensai`,`tensai`(賢い) / `wakaru`系(共感) / `naruhodo`系(学び) / `sugoi`,`yabai`系(感嘆) / `arigatou`系(感謝) / `kaiketsu`系(解決)

選定基準:
- **本文固有のフック > 汎用の褒め。** 「ギャルを召喚して解決した」なら `:ギャル:` が `:sugoi:` に勝つ。そのメッセージにしか押せないスタンプが理想
- 既に押されているスタンプに乗るのは「同意」表明としてはアリだが、新しい視点を足す方が良い
- カジュアルなチャンネルに `white_check_mark` のような業務スタンプを押さない。逆も同様
- **1個だけ押す。** 複数指示された時のみ複数

## 4. 押す

`slack_add_reaction(channel_id, message_ts, emoji)` — コロン無しの名前。

出力は3行以内:
```
<チャンネル名> / <投稿者>: <メッセージ要約1行>
→ :選んだスタンプ: （理由10語以内）
```

`--dry-run` なら押さずに候補3件と理由だけ出す。

## 注意

- **取り消せない。** MCPに `remove_reaction` は無い。押したら人間が手で外すしかない。確信が無ければ `--dry-run` で候補を出して確認を取る
- 公開チャンネルへのリアクションは他人に見える。攻撃的・皮肉に読めるスタンプは選ばない
- ネガティブな内容（障害・失敗報告）に `kusa` 等の笑い系を押さない
- 人物に性別を推定するスタンプを選ばない
