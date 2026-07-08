#!/usr/bin/env python3
"""
Render Mermaid code blocks in a Markdown file to PNG images,
embed them as <img> tags, then generate a PDF via md-to-pdf.

Usage:
    python3 md-to-pdf-with-mermaid.py <input.md>

Output:
    <input>.pdf  (same directory as input)
    diagrams/    (PNG files, same directory as input)
"""

import sys
import re
import subprocess
import os
from pathlib import Path


CONFIG = Path.home() / ".claude/scripts/md-to-pdf-config.js"
MERMAID_CLI = ["npx", "--yes", "@mermaid-js/mermaid-cli"]


def render_mermaid(mermaid_src: str, out_png: Path) -> bool:
    """Render a mermaid string to a PNG. Returns True on success."""
    mmd = out_png.with_suffix(".mmd")
    mmd.write_text(mermaid_src, encoding="utf-8")
    result = subprocess.run(
        MERMAID_CLI + ["-i", str(mmd), "-o", str(out_png), "-b", "white", "--scale", "2"],
        capture_output=True, text=True,
    )
    mmd.unlink(missing_ok=True)
    if out_png.exists():
        return True
    print(f"  [mermaid] render failed:\n{result.stderr.strip()}", file=sys.stderr)
    return False


def process(md_path: Path) -> Path:
    content = md_path.read_text(encoding="utf-8")

    img_dir = md_path.parent / "diagrams"
    img_dir.mkdir(exist_ok=True)

    pattern = re.compile(r"```mermaid\n(.*?)```", re.DOTALL)
    counter = 0

    def replace(match: re.Match) -> str:
        nonlocal counter
        counter += 1
        src = match.group(1)
        slug = md_path.stem.replace(" ", "-")
        png_path = img_dir / f"{slug}_diagram_{counter}.png"

        print(f"  [mermaid] rendering diagram {counter} → {png_path.name}")
        if render_mermaid(src, png_path):
            # Use absolute path so md-to-pdf can find it regardless of cwd
            return f'<img src="{png_path}" alt="diagram {counter}" style="max-width:100%;display:block;margin:16px auto;">'
        else:
            # Fall back: keep original code block
            return match.group(0)

    rendered_content = pattern.sub(replace, content)

    # Write a temporary .rendered.md next to the original
    temp_md = md_path.with_name(md_path.stem + ".rendered.md")
    temp_md.write_text(rendered_content, encoding="utf-8")

    # Run md-to-pdf on the temp file
    pdf_out = md_path.with_suffix(".pdf")
    temp_pdf = temp_md.with_suffix(".pdf")

    cmd = ["md-to-pdf", str(temp_md)]
    if CONFIG.exists():
        cmd += ["--config-file", str(CONFIG)]

    print(f"  [md-to-pdf] generating PDF...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    # md-to-pdf writes to the same dir as input; rename to canonical name
    if temp_pdf.exists():
        temp_pdf.rename(pdf_out)
    else:
        print(f"  [md-to-pdf] error: {result.stderr.strip()}", file=sys.stderr)

    temp_md.unlink(missing_ok=True)
    return pdf_out


def main():
    if len(sys.argv) < 2:
        print("Usage: md-to-pdf-with-mermaid.py <input.md>")
        sys.exit(1)

    md_path = Path(sys.argv[1]).resolve()
    if not md_path.exists():
        print(f"File not found: {md_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Processing: {md_path.name}")
    pdf = process(md_path)
    if pdf.exists():
        print(f"Done → {pdf}")
    else:
        print("PDF generation failed.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
