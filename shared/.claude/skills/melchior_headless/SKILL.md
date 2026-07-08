---
name: melchior_headless
description: 任意の Melchior プログラムをヘッドレス + autopilot で起動するラッパーを実行。cpolaris (uv) venv 対応、リポジトリ非依存。クローン済みリポジトリの root から melchior プログラム (scene_tuner 等) をヘッドレス起動・撮影したいときに使う。
argument-hint: "[-d auto_dir] [--show|--vd] [--size WxH] <command...>"
---

# /melchior_headless — ヘッドレス Melchior ラッパー実行

グローバルインストール済みラッパーを呼ぶ。リポジトリへコピー不要。

- ラッパー本体: `~/.local/share/melchior-headless/melchior_headless.sh`
- 依存サブdir: `~/.local/share/melchior-headless/melchior_headless/` (sitecustomize.py + _mhl_autopilot.py) — `.sh` と同じ階層必須
- op プロトコル (cmd_*.json): `~/.local/share/melchior-headless/README.md` 参照
- 仕組み: PYTHONPATH 注入で `melchior.update` をフック → 毎フレーム auto_dir の cmd_*.json を処理。macOS=画面外/BetterDisplay 疑似ヘッドレス、Linux=専用 Xvfb :99-199

## 前提チェック

実行前に確認:
1. **cwd = 対象リポジトリの root** (cwd 相対で `outputs/` 作成 + `uv run` 解決)。違えば cd するかユーザーに確認
2. 対象 env に `melchior` + `PIL` が import 可能 (cpolaris venv = `task setup`→`uv sync` で構築済み)。無い repo ではフックは no-op、コマンドは素通し実行

## 引数の解析

`$ARGUMENTS` をそのままラッパーへ渡す。先頭のフラグ (`-d/--show/--vd/--size/--use-display`) はラッパー用、`--` 以降または最初の非フラグ以降が実行コマンド。

- `-d auto_dir`     cmd_*.json 監視ディレクトリ (省略時 `outputs/debug/autopilot_<PID>`)
- `--show`          (macOS) ウィンドウを画面内に残す (デバッグ)
- `--vd`            (macOS) BetterDisplay 仮想ディスプレイへ移動
- `--size WxH`      (Linux) Xvfb 画面サイズ (既定 1920x1080)
- `--use-display :N` (Linux) 既存 X server 再利用

引数にコマンドが無ければユーザーに確認 (例: `uv run python launch/debug/scene_tuner_all.py`)。

## 実行

`UV_NO_SYNC=1` を付けて melchior の C++ 再ビルドを毎回回避する:

```bash
UV_NO_SYNC=1 ~/.local/share/melchior-headless/melchior_headless.sh $ARGUMENTS
```

PATH に `~/.local/share/melchior-headless` が通っていれば `melchior_headless.sh $ARGUMENTS` で可。

## 例

```bash
# scene tuner (Demo シーン)。printf でシーン選択を stdin 投入
cd ~/repo/<clone>
printf '0\n' | UV_NO_SYNC=1 ~/.local/share/melchior-headless/melchior_headless.sh \
    -d outputs/debug/ap1 uv run python launch/debug/scene_tuner_all.py
```

## トラブルシュート

- フック未発火 (`_MhlFinder` が sys.meta_path に無い): PYTHONPATH 注入失敗。`.sh` と `melchior_headless/` サブdir が同階層か確認
- macOS で合成停止: `orderOut` 禁止。`--show` か `--vd` を使う
- Linux で llvmpipe に落ちる: NVIDIA 機なら `__GLX_VENDOR_LIBRARY_NAME=nvidia` 自動 export されるか確認 (nvidia-smi 必要)
- `melchior` import 不可: 対象 repo で env 未構築。`task setup` を先に実行
