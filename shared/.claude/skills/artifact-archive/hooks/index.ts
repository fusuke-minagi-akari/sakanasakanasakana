import type { Register } from "claude-code";

// scratchpad lives under /tmp (or /private/tmp, /var/folders) and is wiped with the session
const EPHEMERAL = /^\/(private\/)?(tmp|var\/folders)\//;

type ArtifactArgs = { action?: string; file_path?: string; asset?: boolean };

export const register: Register = (on) => {
  // Artifact is not in the generated tool union, so match it by RegExp
  on("tool.call", { tool: /^Artifact$/ }, (_$, e, next) => {
    const a = e as unknown as ArtifactArgs;
    const isPublish = (a.action ?? "publish") === "publish" && !a.asset;
    if (isPublish && a.file_path && EPHEMERAL.test(a.file_path)) {
      return {
        deny: "Publishing from a temp dir is refused (CLAUDE.md output rule). Save the file to ~/Desktop/claude-outputs/artifacts/<kebab-case-name>.html (mkdir -p first) and publish from there, so the source outlives the session.",
      };
    }
    return next(e);
  });
};
