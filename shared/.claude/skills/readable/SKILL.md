---
name: readable
description: Rewrite English text or information so it is fast to read and hard to misread — conclusion first, clear structure, plain words, scannable layout — without losing or changing any facts. Use when the user says "make this readable", "clean up this text", "rewrite for clarity", or pastes a messy English note, Slack thread, report, spec, or dump of information to tidy up. English only; Japanese text goes to the yomiyasu skill.
metadata:
  short-description: Make English text easier to read, losslessly
---

# Readable

Rewrite the given text so a busy reader gets it on the first pass. Output the rewrite only, in English (unless asked to translate). Keep code, identifiers, product names, and numbers as-is. For Japanese text use the yomiyasu skill instead; in mixed EN/JA text, touch only the English parts.

## Hard rules (never break)

- **Lossless.** Keep every fact, number, unit, date, name, path, command, link, condition, caveat, and causal link. Do not add claims. If something is ambiguous, keep it ambiguous and flag it in one line after the rewrite (`⚠ unclear: …`).
- **No new meaning.** Don't soften or strengthen certainty ("may" stays "may").
- **Preserve code blocks, quotes, and tables' data verbatim.** Only their surrounding prose changes.
- Respect the user's CLAUDE.md / AGENTS.md rules (NDA filters, pronoun rules) — they override this skill.

## Process

1. **Find the point.** What must the reader know or do? Put it first (BLUF).
2. **Group.** Cluster related facts; order by importance, then time, then detail.
3. **Pick the shape** that fits the content, not habit:
   | Content | Shape |
   |---|---|
   | One idea | 1–3 short sentences, no headings |
   | Steps / procedure | Numbered list |
   | Parallel items | Bullets (same grammatical form each) |
   | Compare ≥2 things on ≥2 attributes | Table |
   | Long doc (>~300 words) | Short headings + summary line on top |
   Don't bullet a narrative argument; don't add headings to a 5-line message.
4. **Rewrite sentences** (rules below).
5. **Cut.** Delete filler, repetition, throat-clearing. Target ~30–50% shorter with zero fact loss (PR bodies: use `light`, since CLAUDE.md says not to compress them).
6. **Check:** diff facts against the original (every number/name present?), skim test (can the bold/first lines alone carry the message?).

## English

- One idea per sentence; aim ≤20 words, hard cap ~30.
- Active voice, concrete subject: "The job failed" > "A failure was observed".
- Plain words: use > utilize, start > commence, because > due to the fact that, now > at this point in time.
- Verbs over nominalizations: "decide" > "make a decision".
- Lead lists and paragraphs with the key word; bold only the 1–3 things that matter most.
- Specific over vague: "3 of 10 runs failed" > "some runs failed".
- Drop hedges and filler (basically, actually, just, I think that, in order to → to) unless they carry real uncertainty.
- Consistent terms: pick one name per thing and stick to it.


## Output

- The rewritten text, ready to paste.
- Then, only if needed, ≤3 lines: `⚠` unclear points, or facts you could not place. No commentary on what you changed unless asked.
- If the user asks for a level: `light` = fix sentences only, keep structure; `full` (default) = restructure + rewrite; `tldr` = add a 1–3 line summary on top and nothing else changes.
