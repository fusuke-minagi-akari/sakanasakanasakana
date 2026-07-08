# dotfiles

herdr + Claude Code のターミナルカスタマイズを保存・バージョン管理・別マシンへ書き出すためのリポジトリ。
構成は [void2610/dotfiles](https://github.com/void2610/dotfiles) を参考に、`install.sh` でシンボリックリンクを張る方式。

Personal dotfiles for [herdr](https://herdr.dev) + Claude Code terminal setup. `install.sh` symlinks each tracked file into `$HOME`, backing up anything it would overwrite to `~/backup`.

## 中身 / What's tracked

| リポジトリ内パス | リンク先 | 役割 |
|---|---|---|
| `home/.local/bin/show` | `~/.local/bin/show` | `show <path>` — ファイルを herdr + Kitty 用の in-terminal ビューアへ自動振り分け（画像→`chafa -f kitty`、動画→`mpv --vo=kitty`、md→`glow`）。 |
| `home/.local/bin/herdr-branch-labels.sh` | `~/.local/bin/herdr-branch-labels.sh` | git ブランチ可視化デーモン。workspace サイドバーラベルと各 pane のボーダータイトルに `<repo> · <branch> · <N>Δ · PR#<n>` を書き込む。 |
| `home/.config/herdr/config.toml` | `~/.config/herdr/config.toml` | herdr 本体設定（通知・サウンド・テーマ・キーバインド・kitty_graphics 等）。 |
| `home/.claude/hooks/herdr-claude-done.sh` | `~/.claude/hooks/herdr-claude-done.sh` | Claude Code の Stop フック → herdr のカスタム完了バナー + サウンド。 |
| `home/Library/LaunchAgents/dev.herdr.branchlabels.plist.tmpl` | `~/Library/LaunchAgents/dev.herdr.branchlabels.plist`（生成） | branch-labels デーモンを常駐させる launchd ジョブ。絶対パスが要るためリンクせず、`$HOME` を埋めて**生成**する。 |

## インストール / Install

```sh
git clone <this-repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh            # link + plist 生成 + launchd 起動
./install.sh --dry-run  # 変更せず動作だけ表示
./install.sh --no-load  # リンク/生成のみ、launchd は触らない
```

- 既存の実ファイルは `~/backup/<相対パス>` に退避してからリンクに置き換える（上書き破壊なし）。
- リポジトリ内を編集すればリンク先に即反映（`config.toml` 編集後は `herdr server reload-config`、スクリプト編集後は `launchctl kickstart -k gui/$UID/dev.herdr.branchlabels`）。

## herdr が管理するフック / herdr-managed hook

`~/.claude/hooks/herdr-agent-state.sh`（agent の idle/working/blocked 状態を報告）は **herdr が生成・上書き**するため、このリポジトリでは追跡しない。新マシンでは:

```sh
herdr integration install claude
```

を実行して再生成する（`~/.claude/settings.json` に SessionStart エントリも書かれる）。

## 依存 / Dependencies

`herdr` `git` `jq` `gh` `perl`（branch-labels 用）、`chafa` `mpv` `glow`（`show` 用、無ければ該当タイプでヒント表示）。macOS 前提（launchd / `md5 -qs`）。

## 追跡しないもの / Not tracked

ログ・ソケット・キャッシュ・`session.json`・`release-notes.json`（`.gitignore` 参照）。実行時に生成される状態ファイル。
