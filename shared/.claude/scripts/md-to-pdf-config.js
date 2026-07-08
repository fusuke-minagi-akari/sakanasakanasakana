module.exports = {
  stylesheet: [],
  css: `
    body { font-family: "Helvetica Neue", Arial, "Hiragino Kaku Gothic ProN", "Meiryo", sans-serif; font-size: 13px; line-height: 1.7; max-width: 900px; margin: 0 auto; padding: 20px 40px; color: #24292e; }
    h1 { border-bottom: 2px solid #0366d6; padding-bottom: 8px; color: #0366d6; }
    h2 { border-bottom: 1px solid #e1e4e8; padding-bottom: 4px; color: #24292e; margin-top: 28px; }
    h3 { color: #444; }
    table { border-collapse: collapse; width: 100%; margin: 16px 0; font-size: 12px; }
    th { background: #f6f8fa; padding: 8px 12px; border: 1px solid #dfe2e5; text-align: left; font-weight: 600; }
    td { padding: 7px 12px; border: 1px solid #dfe2e5; }
    tr:nth-child(even) td { background: #f9fafb; }
    code { background: #f6f8fa; padding: 2px 5px; border-radius: 3px; font-size: 11px; font-family: "SFMono-Regular", Consolas, monospace; }
    pre { background: #f6f8fa; padding: 14px; border-radius: 6px; overflow-x: auto; border: 1px solid #e1e4e8; }
    pre code { background: none; padding: 0; }
    blockquote { border-left: 3px solid #0366d6; margin: 0; padding: 0 16px; color: #6a737d; }
    .mermaid { text-align: center; margin: 20px 0; }
  `,
  body_class: [],
  highlight_style: "github",
  marked_options: {},
  pdf_options: {
    format: "A4",
    margin: { top: "20mm", right: "20mm", bottom: "20mm", left: "20mm" },
    printBackground: true
  },
  launch_options: {}
}
