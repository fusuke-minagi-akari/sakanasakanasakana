import type { Register } from "claude-code";

const k = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`);

export const register: Register = (on) => {
  on("turn.complete", ($, e, next) => {
    // main loop only: subagent turns and interrupts are noise
    if (!e.agentId && !e.isAborted) {
      const u = e.usage;
      const tok = u
        ? ` · ${k(u.input_tokens + u.cache_read_input_tokens + u.cache_creation_input_tokens)} in · ${k(u.output_tokens)} out`
        : "";
      $.ui.toast(`⏱ ${(e.durationMs / 1000).toFixed(1)}s${tok}`, { timeoutMs: 10000 });
    }
    return next(e);
  });
};
