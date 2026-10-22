// Pure scan, no $: the validator can't follow $ across imports, so index.ts owns every $ call.

// Outbound = sends, posts, or writes something another person can read.
export const OUTBOUND =
  /^(Artifact|mcp__claude_ai_(Slack|Notion|Gmail|Google_Drive|Google_Calendar|Claude_Docs)__.*(send|reply|forward|draft|schedule|create|update|comment|batch|share|copy|move|duplicate|upload).*)$/;

// Bash commands that publish text: PR/issue bodies, gists, commit messages.
export const OUTBOUND_BASH = /\bgh\s+(pr|issue|release|gist|api)\b|\bgit\s+commit\b/;

const RULES: [string, RegExp][] = [
  // 12 digits not inside a hex run, so UUID/Notion-id fragments don't trip it
  ["AWS account ID", /(?<![0-9a-fA-F-])\d{12}(?![0-9a-fA-F-])/],
  ["ARN", /\barn:aws[a-z-]*:/i],
  ["gendered pronoun", /\b(he|she|him|his|her|hers|himself|herself)\b/i],
  ["gendered pronoun", /彼女|彼(?!ら|岸|方)/],
];

// ids and urls are routing, not prose, and are hex-ish enough to false-positive
const SKIP_KEY = /(id|ids|url)$/i;

export function strings(v: unknown, out: string[] = [], key = ""): string[] {
  if (SKIP_KEY.test(key)) return out;
  if (typeof v === "string") out.push(v);
  else if (Array.isArray(v)) for (const x of v) strings(x, out);
  else if (v && typeof v === "object")
    for (const [k, x] of Object.entries(v)) strings(x, out, k);
  return out;
}

// `terms`: one per line from ~/.claude/nda-terms.txt, '#' comments; matched case-insensitively
export function parseTerms(text: string): string[] {
  return text
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l !== "" && !l.startsWith("#"));
}

export function findings(texts: readonly string[], terms: readonly string[]): string[] {
  const hits = new Set<string>();
  for (const t of texts) {
    for (const [label, re] of RULES) {
      const m = t.match(re);
      if (m) hits.add(`${label} "${m[0]}"`);
    }
    const low = t.toLowerCase();
    for (const term of terms) if (low.includes(term.toLowerCase())) hits.add(`NDA term "${term}"`);
  }
  return [...hits];
}
