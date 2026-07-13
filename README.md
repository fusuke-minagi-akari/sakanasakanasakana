# sakanasakanasakana

herdr + Claude Code のターミナル環境を保存・バージョン管理・別マシンへ書き出すための dotfiles。
構成は [void2610/dotfiles](https://github.com/void2610/dotfiles) を参考に、`install.sh` でシンボリックリンクを張る方式。

Personal dotfiles for [herdr](https://herdr.dev) + Claude Code. `install.sh` symlinks each tracked file into `$HOME`, backing up anything it would overwrite to `~/backup`.

## これは何をするか / What it does

- **`show <path>`** — ファイル/フォルダを herdr + Kitty 用ビューアへ自動振り分け。画像→`chafa`、動画/音声→`mpv`、markdown→`glow`、**PDF→ページ画像**、**diff→色付き**、**CSV→整列表**、**JSON→`jq`**、コード→エディタ、フォルダ→`open`。追加ツール無しでも動く（poppler/delta/csvkit があればより綺麗）。※新タイプ(pdf/diff/csv/json)は現状 macOS 版のみ、Linux 版は未移植。
- **`notify <cmd…>`** — コマンド実行 → 完了時に herdr 通知（所要時間 + 終了コード、成功/失敗で音変化）。長時間タスク向け。cross-OS。
- **`clip <path…>`** — ファイルをクリップボードへ file object として載せる（macOS=osascript / Linux=xclip）。
- **git ブランチ可視化デーモン** — herdr の workspace サイドバー + 各 pane ボーダーに `<repo> · <branch> · <N>Δ · PR#<n>` を表示。macOS は launchd、Linux は systemd で常駐。
- **herdr 本体設定** — 通知・サウンド・テーマ・キーバインド・kitty_graphics を再現。
- **Claude Code 設定** — settings.json / CLAUDE.md / hooks / commands / skills / scripts をバージョン管理。
- **1 コマンドで新マシンへ展開** — `install.sh` が symlink を張り（既存は `~/backup` へ退避）、OS 別サービスを登録。依存や launchd/systemd の差は Claude Code が `SETUP.md` を読んで吸収する。

要は「herdr + Claude Code のターミナル環境まるごと」を保存・バージョン管理し、別マシンへ再現可能にするリポジトリ。

## レイアウト / Layout

OS ごとに適用範囲を分ける。各ディレクトリは `$HOME` をミラーする。

```
sakanasakanasakana/
├── install.sh          # 依存(端末stack)インストール + shared/ + <os>/ を $HOME へ symlink
├── lib/deps.sh         # 状態認識インストーラ（herdr/kitty/CLI、install.sh が source）
├── packages/           # 端末stackのパッケージ一覧: brew.txt / apt.txt / pacman.txt
├── bootstrap.sh        # 追加: Claude機能用の extras（node/python/matplotlib）
├── deps/               # extras マニフェスト: requirements.txt(pip) / npm-global.txt
├── DEPENDENCIES.md     # 機能 → 依存マトリクス（何が何を要るか）
├── SETUP.md            # OS 適応の手順書（Claude Code が読む）
├── CLAUDE.md           # Claude Code 自動読込のプロジェクト指示 + ガードレール
├── .github/workflows/  # CI（shellcheck + dry-run マトリクス）
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

## セットアップ & インストール / Setup & Install

まず clone:

```sh
git clone git@github.com:fusuke-minagi-akari/sakanasakanasakana.git ~/sakanasakanasakana
cd ~/sakanasakanasakana
```

以降は 2 通り。**方法 A（推奨）** は OS 差（依存インストール・launchd/systemd）まで面倒を見る。

### 方法 A: Claude Code に任せる / Let Claude Code set it up

clone したディレクトリで Claude Code を起動し、こう頼む:

```
このリポジトリをこのマシンにセットアップして
```

Claude Code は root の `CLAUDE.md` を自動で読み、`SETUP.md` の手順（OS 判定 → `install.sh`[端末stack依存 + symlink + サービス] → `bootstrap.sh`[Claude機能extras] → herdr hook 再生成 → per-user config → 検証）に沿って適応させる。NDA ガードレール込み。

### 方法 B: 手動 / Manual

```sh
./install.sh            # 依存(herdr/kitty/CLI) + symlink + example 展開 + launchd 起動
./install.sh --dry-run  # 変更せず動作だけ表示
./install.sh --no-deps  # 依存インストールを飛ばして symlink だけ
./bootstrap.sh          # 追加: node/python/matplotlib（/diagram, report, 表PNG 用）
```

**2 層構成:**
- **Layer 1（端末stack）** — `install.sh` が `lib/deps.sh` 経由で状態認識インストール（herdr, kitty, glow chafa mpv jq gh git file）。一覧は `packages/{brew,apt,pacman}.txt`。cross-OS・テスト済み — **触らない**。
- **Layer 2（Claude機能extras、任意）** — `bootstrap.sh` が Layer 1 に無い物だけ追加（node/python/matplotlib、`--npm` で npm globals）。Layer 1 は一切触らない。

機能→依存の全体は **[`DEPENDENCIES.md`](DEPENDENCIES.md)**。

- 既存の実ファイルは `~/backup/<相対パス>` に退避してから symlink へ置換（破壊なし）。
- リポジトリ内を編集すれば即反映（`config.toml` 編集後 `herdr server reload-config`／スクリプト編集後 `launchctl kickstart -k gui/$UID/dev.herdr.branchlabels`、Linux は `systemctl --user restart herdr-branch-labels`）。
- Linux はサービス登録が手動（systemd user unit）。`SETUP.md` §2 にそのまま貼れる unit あり。

詳細な OS 別手順書は **[`SETUP.md`](SETUP.md)**。

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

全機能→依存の完全なマトリクス（機能ごとに何が core / optional か、OS 別パッケージ名）は **[`DEPENDENCIES.md`](DEPENDENCIES.md)**。Layer 1 一覧は `packages/*.txt`（`install.sh` 経由）、Layer 2 extras は `deps/`（`bootstrap.sh` 経由）。

ざっくり: `herdr`+`kitty`（`install.sh` が自動導入）+ `git jq gh perl file`（daemon）、`chafa mpv glow`（show）、`node`+`npx`（diagram/kalmia/report）、`python3`+`matplotlib`+CJK フォント（表 PNG）。daemon の `hashkey` は macOS `md5` 前提（`md5` 無い distro では共有キーに劣化、ラベル自体は表示）。OS 差はサービス管理（macOS=launchd 自動 / Linux=systemd user unit、`SETUP.md` §2）。caveman プラグイン・MCP サーバ・melchior wrapper は手動（`DEPENDENCIES.md` §6）。

OS 別 `show`/`clip` の追加ツール: **Linux** = `kitten`(Kitty)・flatpak `io.mpv.Mpv`・`micro`・`xdg-open`・`xclip`・`realpath`。**macOS** = `chafa`(icat は herdr PTY 越しで不可)・`mpv`・`glow`・`${EDITOR}`/`micro`・`open`・`pbcopy`/`osascript`。

## 追跡しないもの / Not tracked

ログ・ソケット・キャッシュ・`session.json`・`history.jsonl`・`projects/`・`sessions/`・`settings.local.json`・`.credentials.json`・実 `standup_config.json`/`devices.txt`（`.gitignore` 参照）。
