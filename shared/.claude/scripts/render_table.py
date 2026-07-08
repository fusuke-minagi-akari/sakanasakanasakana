#!/usr/bin/env python3
"""Render a JSON table as a styled PNG image for Slack sharing."""

import json
import sys
import os


def render_table(data, output_path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.font_manager as fm

    # Use a CJK-capable font (macOS Hiragino Sans, with fallbacks)
    cjk_fonts = ["Hiragino Sans", "Hiragino Maru Gothic Pro", "YuGothic", "Noto Sans CJK JP"]
    available = {f.name for f in fm.fontManager.ttflist}
    font_family = next((f for f in cjk_fonts if f in available), None)
    if font_family:
        plt.rcParams["font.family"] = font_family
    plt.rcParams["font.size"] = 11

    headers = data["headers"]
    rows = data["rows"]
    title = data.get("title", "")

    n_cols = len(headers)
    n_rows = len(rows)
    col_width = max(2.0, min(3.5, 14 / n_cols))
    fig_w = n_cols * col_width
    fig_h = max((n_rows + 1) * 0.55 + (1.0 if title else 0.3), 2.5)

    fig, ax = plt.subplots(figsize=(fig_w, fig_h))
    ax.axis("off")

    if title:
        ax.set_title(title, fontsize=14, fontweight="bold", pad=20, loc="left")

    table = ax.table(
        cellText=rows,
        colLabels=headers,
        loc="center",
        cellLoc="center",
    )

    table.auto_set_font_size(False)
    table.set_fontsize(11)
    table.auto_set_column_width(list(range(n_cols)))
    table.scale(1.0, 1.6)

    # Style header
    for j in range(n_cols):
        cell = table[0, j]
        cell.set_facecolor("#2C3E50")
        cell.set_text_props(color="white", fontweight="bold")
        cell.set_edgecolor("#1A252F")

    # Alternate row colors
    for i in range(1, n_rows + 1):
        for j in range(n_cols):
            cell = table[i, j]
            cell.set_facecolor("#F8F9FA" if i % 2 == 0 else "#FFFFFF")
            cell.set_edgecolor("#DEE2E6")

    plt.savefig(output_path, bbox_inches="tight", dpi=150, facecolor="white", pad_inches=0.3)
    plt.close()
    print(f"Saved: {output_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: render_table.py <output.png> < input.json", file=sys.stderr)
        sys.exit(1)
    output_path = sys.argv[1]
    data = json.load(sys.stdin)
    render_table(data, output_path)
