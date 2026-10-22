import { expect, test } from "claude-code/testing";
import { findings, OUTBOUND, OUTBOUND_BASH, parseTerms, strings } from "./check";

test("flags IDs, ARNs, pronouns and terms; passes clean text", () => {
  const terms = parseTerms("# comment\nAcmeCorp\n\n");
  expect(terms).toEqual(["AcmeCorp"]);
  expect(findings(["account 123456789012 here"], [])).toEqual(['AWS account ID "123456789012"']);
  expect(findings(["arn:aws:iam::x"], []).length).toBe(1);
  expect(findings(["She fixed it", "彼が直した"], []).length).toBe(2);
  expect(findings(["met acmecorp today"], terms)).toEqual(['NDA term "AcmeCorp"']);
  // clean: they/彼ら, header/there, uuid tail, 13-digit ms timestamp
  expect(findings(["they and 彼ら fixed the header there", "a1b2-123456789012", "1727150000123"], terms)).toEqual([]);
});

test("skips id/url keys and scopes to outbound tools", () => {
  expect(strings({ page_id: "123456789012", text: "hi", nested: [{ body: "x" }] })).toEqual(["hi", "x"]);
  expect(OUTBOUND.test("mcp__claude_ai_Slack__slack_send_message")).toBe(true);
  expect(OUTBOUND.test("mcp__claude_ai_Slack__slack_read_channel")).toBe(false);
  expect(OUTBOUND.test("Artifact")).toBe(true);
  expect(OUTBOUND_BASH.test('gh pr comment 3 -b "x"')).toBe(true);
  expect(OUTBOUND_BASH.test("git status")).toBe(false);
});
