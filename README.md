# sakanasakanasakana

herdr + Claude Code のターミナル環境を保存・バージョン管理・別マシンへ書き出すための dotfiles。
構成は [void2610/dotfiles](https://github.com/void2610/dotfiles) を参考に、`install.sh` でシンボリックリンクを張る方式。

Personal dotfiles for [herdr](https://herdr.dev) + Claude Code. `install.sh` symlinks each tracked file into `$HOME`, backing up anything it would overwrite to `~/backup`.

## レイアウト / Layout

OS ごとに適用範囲を分ける。各ディレクトリは `$HOME` をミラーする。

```
sakanasakanasakana/
├── install.sh          # uname 判定 → shared/ + <os>/ を反映
├── shared/             # 全OS共通（$HOME ミラー）
│   ├── .local/bin/           show, herdr-branch-labels.sh
│   ├── .config/herdr/        config.toml
│   └── .claude/              settings.json, CLAUDE.md, hooks/, commands/, skills/, scripts/
├── macos/              # Darwin 限定
│   └── Library/LaunchAgents/ dev.herdr.branchlabels.plist.tmpl
└── linux/              # Linux 限定（herdr + Kitty 前提の上書き）
    ├── .local/bin/           show（Kitty 版）, clip
    └── .config/herdr/        config.toml（Linux キーバインド）
```

`install.sh` は常に `shared/` を反映し、その上に `uname` で判定した `macos/` か `linux/` を重ねる。同一リポジトリで Mac と Linux 両方をまかなう。

## 追跡している主な物 / What's tracked

**herdr / ターミナル**
| パス | 役割 |
|---|---|
| `.local/bin/show` | `show <path>` — ファイル/フォルダを自動振り分け。**shared**（クロスOS）は 画像→`chafa -f kitty`、動画→`mpv --vo=kitty`、md→`glow`。**linux** 上書き版は herdr + Kitty 前提: フォルダ→`xdg-open`、画像→`kitten icat`、動画→flatpak `mpv --vo=kitty`、md→`glow`、コード/テキスト→`micro`（pane 内エディタ, マウス+キーボード）。 |
| `linux/.local/bin/clip` | `clip <path>…` — ファイルを X クリップボードに **file object**（`xclip -target text/uri-list`）として載せ、ファイルマネージャ/チャット/メールへ添付貼り付け可能に。abs パスを `file://` URI に percent-encode。X11 前提。 |
| `.local/bin/herdr-branch-labels.sh` | git ブランチ可視化デーモン。workspace サイドバー + 各 pane ボーダーに `<repo> · <branch> · <N>Δ · PR#<n>`。 |
| `.config/herdr/config.toml` | herdr 本体設定（通知・サウンド・テーマ・キーバインド・kitty_graphics）。**linux** 上書きは `prefix=alt+x`・矢印 pane 移動・agent walk・cheatsheet pane。 |
| `macos/…/dev.herdr.branchlabels.plist.tmpl` | 上記デーモンの launchd 常駐ジョブ。絶対パスが要るため symlink せず `$HOME` を埋めて生成。 |

**Claude Code**
| パス | 役割 |
|---|---|
| `.claude/settings.json` | Claude 設定（hooks・permissions 等）。パスは `$HOME` でテンプレ化済み。 |
| `.claude/CLAUDE.md` | グローバル指示（NDA フィルタ等）。※後述のサニタイズ済み。 |
| `.claude/hooks/herdr-claude-done.sh` | Claude 完了 → herdr バナー + サウンド。 |
| `.claude/commands/*.md` | カスタムスラッシュコマンド（standup/nippo/research 含む、サニタイズ済み）。 |
| `.claude/skills/*` | カスタムスキル。 |
| `.claude/scripts/*` | 補助スクリプト（render_table.py, md-to-pdf 等）。 |

## インストール / Install

```sh
git clone git@github.com:fusuke-minagi-akari/sakanasakanasakana.git ~/sakanasakanasakana
cd ~/sakanasakanasakana
./install.sh            # link + plist 生成 + example 展開 + launchd 起動
./install.sh --dry-run  # 変更せず動作だけ表示
./install.sh --no-load  # launchd は触らない
```

- 既存の実ファイルは `~/backup/<相対パス>` に退避してから symlink へ置換（破壊なし）。
- リポジトリ内を編集すれば即反映（`config.toml` 編集後 `herdr server reload-config`／スクリプト編集後 `launchctl kickstart -k gui/$UID/dev.herdr.branchlabels`）。

## 初回セットアップの手当て / Post-install

1. **herdr state hook（herdr 管理）** — `~/.claude/hooks/herdr-agent-state.sh` は herdr が生成・上書きするため追跡しない。再生成:
   ```sh
   herdr integration install claude
   ```
2. **per-user config（`*.example` から seed）** — 秘匿値を含む設定は `.example` テンプレートのみコミット。`install.sh` が実ファイル不在時のみ複製する（既存は上書きしない）。中身を自分の値で埋める:
   - `~/.claude/scripts/standup_config.json` ← `standup_config.example.json`（Slack/Notion ID 等）
   - `~/.claude/scripts/devices.txt` ← `devices.example.txt`（SSH ホスト）
   - `.claude/skills/kalmia/SKILL.md` の `<KALMIA_NOTION_COLLECTION_ID>` を実 ID に。

## サニタイズ / Sanitization

NDA・PII を含む値はコミット前に汎用プレースホルダへ置換済み（クライアント企業名・AWS アカウント ID・金額・Slack/Notion ID・同僚名・LAN IP）。ルールや構造は保持、具体値のみ除去。実値は各自ローカルで補完する（`*.example` + `.gitignore` で保護）。

## 依存 / Dependencies

`herdr` `git` `jq` `gh` `perl`（branch-labels）、`chafa` `mpv` `glow`（shared `show`）。Linux `show`/`clip` は `kitten`（Kitty）・flatpak `io.mpv.Mpv`・`glow`・`micro`・`xdg-open`・`xclip`・`realpath` を使う。macOS 前提の箇所あり（launchd, `md5 -qs`）。

## 追跡しないもの / Not tracked

ログ・ソケット・キャッシュ・`session.json`・`history.jsonl`・`projects/`・`sessions/`・`settings.local.json`・`.credentials.json`・実 `standup_config.json`/`devices.txt`（`.gitignore` 参照）。
