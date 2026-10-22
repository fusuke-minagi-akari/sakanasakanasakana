import type { EngineInterface, Register } from "claude-code";
import { findings, OUTBOUND, OUTBOUND_BASH, parseTerms, strings } from "./check";

async function verdict($: EngineInterface, texts: string[]): Promise<string | undefined> {
  const home = await $.env.get("HOME");
  if (await $.fs.exists(`${home}/.claude/nda-guard.off`)) return undefined;
  const terms = await $.fs.read(`${home}/.claude/nda-terms.txt`).then(parseTerms, () => []);
  const hits = findings(texts, terms);
  if (hits.length === 0) return undefined;
  return `nda-guard refused this outbound call (CLAUDE.md NDA/pronoun rules): ${hits.join(", ")}. Rewrite without them (names or roles instead of pronouns; drop IDs/ARNs/client names) and retry. If this is a false positive, ask the user; they can disable the guard with: touch ~/.claude/nda-guard.off`;
}

export const register: Register = (on) => {
  on("tool.call", { tool: OUTBOUND }, async ($, e, next) => {
    const texts = strings(e);
    // Artifact carries a path, not the page: scan the file it would publish
    const path = (e as { file_path?: unknown }).file_path;
    if (typeof path === "string") texts.push(await $.fs.read(path).catch(() => ""));
    const deny = await verdict($, texts);
    return deny ? { deny } : next(e);
  });

  on("tool.call", { tool: "Bash" }, async ($, e, next) => {
    if (!OUTBOUND_BASH.test(e.command)) return next(e);
    const deny = await verdict($, [e.command]);
    return deny ? { deny } : next(e);
  });
};
