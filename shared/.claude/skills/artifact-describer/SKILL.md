---
name: artifact-describer
description: Turn any topic into one richly-sourced explainer Artifact that reads for a total newcomer and holds up for a domain expert, with real images/diagrams/charts gathered or produced (not invented). Use when the user asks to "explain", "describe", "write up", or "make a page/artifact about" a subject and wants a shareable, media-rich reference — not a quick chat answer, not a status page (that's `project-artifact`'s job), not a dumbed-down picture explainer (that's `eli5`'s job).
argument-hint: <topic or subject>
---

# artifact-describer — dual-audience explainer artifact

Produces one Artifact that works two ways at once: a newcomer reads the visible layer and
gets it; an expert expands the detail and finds it rigorous. Built on the built-in
`Artifact` tool — this skill only adds subject research, media sourcing, and the
primer/deep-dive structure. It does not reimplement layout, color, or diagram mechanics;
follow `artifact-design` (mandatory before writing any artifact) and `dataviz` /
`artifact-diagramming` for those.

## Step 0 — clarify before touching anything (mandatory, no shortcuts)

Never infer scope. Ask the user (one round, batched) whenever any of these is unclear from
the request:

- **Exact subject and boundary** — a broad noun ("explain CRISPR") can mean the mechanism,
  the history, the ethics debate, or all three. Ask which, or confirm "all of it."
- **Where it's coming from** — general public knowledge (web research) vs. an internal
  project/codebase (repo, Notion, Slack — consider handing that gathering to the `research`
  skill first, then use this skill to turn its findings into the artifact) vs. both.
- **Anything that smells sensitive** — an internal client/project name, contract terms, or
  anything the global confidentiality filter would catch. Flag it and ask before including.

If the request is already unambiguous (clear topic, clear source domain, nothing sensitive),
skip the question and proceed — don't ask for the sake of asking.

## Step 1 — gather real material

- **General-knowledge subject:** WebSearch + WebFetch. Prefer primary/authoritative sources
  (official docs, papers, standards bodies, Wikipedia/Wikimedia Commons) over blogs.
- **Internal subject:** repo (`Read`/`Grep`/`git log`), Notion, Slack — or reuse a prior
  `/research` run if one exists for this topic.
- Pull real figures/numbers/quotes, not paraphrase-from-memory. Note each source inline as
  you collect it (URL or path) — you'll need it for captions and the reading-list section.
- If a source conflicts with another, or a fact can't be verified, say so in the artifact
  rather than picking one silently.

## Step 2 — plan the visuals, don't default to prose

For every major section, decide before writing whether a picture would carry more than a
paragraph would, then pick the right *kind* — don't reach for a screenshot by default:

| Need | Use | How |
|---|---|---|
| A real photo/figure/screenshot that exists online | Gathered image | **Default path:** `curl`/`wget` it to the scratchpad dir, base64-encode, inline as `<img src="data:image/…;base64,…">`. Needs no capability declaration and no separate publish step — verified working. **Do not** point `<img src>` at the remote URL; the Artifact CSP blocks all external image/media hosts, it renders broken instead of erroring. Reach for `Artifact` `action: "upload_asset"` (which does need the artifact already published, and an existing `url`) only when data-URI inlining is actually the wrong call — many images, a large file, or letting page viewers add their own — not as the default. |
| A chart from real numbers you gathered | Produced chart | Inline SVG or a CSP-safe charting approach per `dataviz` — real data only, never a plausible-looking mock. |
| An architecture/flow/state diagram | Produced diagram | Mermaid fence or inline SVG per `artifact-diagramming`. |
| A short demo/motion clip | Gathered or produced | Same data-URI path as images if small and openly licensed; otherwise a captioned still + an outbound link to the source video rather than embedding — don't fight the CSP or a multi-MB payload for a media element likely to render blank. |
| Simple motion (a process, a sequence) | Produced animation | CSS animation over a video file — smaller, self-contained, no asset needed. |
| An interactive worth having (not decoration) | Produced, client-side | Plain inline `<script>` + `<canvas>`/SVG — e.g. a small real computation run live in the page (a simulation, a recomputation from the gathered numbers) beats a static chart when the mechanism itself is the point. Still needs no capability. |

Never fabricate a chart, screenshot, or number to fill a gap — an honest "no figure for this"
beats an invented one. Before downloading anything gathered, confirm it's actually reusable —
check the source's license/author (Wikimedia Commons file pages state both plainly) — and
caption every gathered image with source name, author, license, and a link back.

## Step 3 — structure for two readers in one page

Don't build two separate documents or a beginner/expert tab split — that fragments the
narrative and doubles the maintenance. Instead, **progressive disclosure per section**:

- Each section opens with a short, jargon-light paragraph anyone can follow — the primer
  layer, always visible.
- Follow it with `<details><summary>Deeper: …</summary>…</details>` holding the
  expert layer: mechanism detail, edge cases, formulas, caveats, links to primary sources.
  Native `<details>`, no JS — works with the CSP, degrades fine, is keyboard/print friendly.
- A glossary or inline `<abbr title="…">` for jargon terms introduced in the primer layer.
- A **table of contents** near the top (anchor links to each section id) plus "back to top"
  links after long sections — the page will be long, it must stay navigable without relying
  on browser find alone.
- A closing **sources / further reading** list — every gathered fact, image, and figure
  traces back to something in it.

## Step 4 — build and publish

1. Load `artifact-design` (calibrate the design pass) — mandatory per the `Artifact` tool's
   own rules. `artifact-capabilities` is only needed if step 2 actually reached for
   `upload_asset` or another runtime capability; skip it for a plain data-URI build.
2. Write the HTML to the scratchpad dir, fully self-contained: inline all CSS, embed
   gathered/produced media as data URIs or inline SVG directly in the file. Splice large
   base64 blobs in with a script (e.g. Python/sed reading the source file and the HTML
   template separately) rather than pasting them through the conversation — a 90KB image
   becomes a 90KB context read otherwise.
3. Set the page's own `<title>` to the subject (not "Explainer") — it wins over the
   `Artifact` tool's `title` parameter whenever both are given, so don't bother passing both.
   Pick a fitting favicon.
4. Publish with `Artifact`. Re-read the published page once before calling it done (`Artifact
   action: "read"`, or grep the saved local copy): confirm no leftover template placeholders,
   the image data URI is actually present (not the remote URL), every `<details>`/TOC anchor
   id has a matching target, and nothing is clipped.

## What this skill is not

- Not a project status tracker → `project-artifact`.
- Not a simplify-everything picture explainer → `eli5` (community skill, not installed
  here) if the user explicitly wants that instead.
- Not a slide deck → the AKARI `slide/*` plugins.
