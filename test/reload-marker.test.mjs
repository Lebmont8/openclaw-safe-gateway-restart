import assert from "node:assert/strict";
import test from "node:test";

import { parseHealthJson, readReloadMarker } from "../lib/reload-marker.mjs";

test("selects the newest channel start marker", () => {
  assert.equal(readReloadMarker({
    channels: {
      telegram: { lastStartAt: 100 },
      discord: { lastStartAt: 220 },
    },
  }), 220);
});

test("accepts ISO timestamps and ignores invalid channels", () => {
  const marker = readReloadMarker({
    channels: {
      telegram: { lastStartAt: "2026-08-16T02:00:00.000Z" },
      broken: { lastStartAt: "not-a-date" },
    },
  });
  assert.equal(marker, Date.parse("2026-08-16T02:00:00.000Z"));
});

test("parses health without exposing the full payload", () => {
  assert.deepEqual(parseHealthJson(JSON.stringify({
    ok: true,
    channels: { telegram: { lastStartAt: 42 } },
    secrets: { token: "must-not-be-returned" },
  })), { ok: true, marker: 42 });
});
