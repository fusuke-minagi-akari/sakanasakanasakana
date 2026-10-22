import { expect, test } from "claude-code/testing";

test("refuses temp-dir publishes, passes the rest", async ($, on) => {
  on("tool.call", () => ({ result: "published" }));
  const call = (a: Record<string, unknown>) =>
    $.tool.call({ tool: "Artifact", ...a } as never);
  expect((await call({ file_path: "/private/tmp/x/scratchpad/p.html" })).deny).toBeDefined();
  expect((await call({ action: "publish", file_path: "/var/folders/ab/p.html" })).deny).toBeDefined();
  expect((await call({ file_path: "/Users/me/Desktop/claude-outputs/artifacts/p.html" })).deny).toBeUndefined();
  expect((await call({ action: "read", file_path: "/tmp/p.html" })).deny).toBeUndefined();
});
