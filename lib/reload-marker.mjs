export function readReloadMarker(health) {
  const channels = health?.channels;
  if (!channels || typeof channels !== "object") return null;
  let newest = null;
  for (const channel of Object.values(channels)) {
    const value = channel?.lastStartAt;
    const numeric = typeof value === "number" ? value : Date.parse(String(value || ""));
    if (!Number.isFinite(numeric)) continue;
    newest = newest === null ? numeric : Math.max(newest, numeric);
  }
  return newest;
}

export function parseHealthJson(text) {
  const health = JSON.parse(String(text || ""));
  return {
    ok: health?.ok === true,
    marker: readReloadMarker(health),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let input = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) input += chunk;
  try {
    const result = parseHealthJson(input);
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`invalid health JSON: ${error?.message || String(error)}\n`);
    process.exit(1);
  }
}
