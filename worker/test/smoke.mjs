// Smoke test against a running `wrangler dev` (node 22+: global WebSocket).
// Verifies: join creates a room, two climbers land in the same pack, telemetry
// keeps its provenance, the live board sees both, finish lands on the wall.
const BASE = process.env.BASE || "http://127.0.0.1:18787";
const WS = BASE.replace(/^http/, "ws");
const assert = (c, m) => { if (!c) { console.error("FAIL:", m); process.exit(1); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const join = async (mode) => (await (await fetch(`${BASE}/v1/join`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ mode }) })).json()).roomId;

const r1 = await join("pack");
const r2 = await join("pack");
assert(r1 === r2, `second joiner should land in the open room (${r1} vs ${r2})`);
const race = await join("race");
assert(race !== r1 && race.startsWith("race-"), "race joins its own room");

function climber(room, id, name, city) {
  const ws = new WebSocket(`${WS}/v1/rooms/${room}/ws?id=${id}&name=${name}&city=${city}`);
  const state = { snaps: [], cheers: [] };
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.type === "snapshot" || m.type === "hello") state.snaps.push(m); if (m.type === "cheer") state.cheers.push(m); };
  return new Promise((res) => (ws.onopen = () => res({ ws, state })));
}

const a = await climber(r1, "a1", "Sly", "New%20Jersey");
const b = await climber(r1, "b2", "Marcus", "NYC");
await sleep(300);
a.ws.send(JSON.stringify({ type: "telemetry", elapsed: 61, metrics: { steps: { v: 120, src: "pedometer" }, spm: { v: 72, src: "pedometer" }, level: { v: 7, src: "manual" }, hr: { v: 140, src: "watch_hr" }, effort: { v: 71, src: "watch_hr" }, bogus: { v: 1, src: "x" } } }));
b.ws.send(JSON.stringify({ type: "telemetry", elapsed: 30, metrics: { steps: { v: 40, src: "nope" }, spm: { v: 68, src: "estimated", model: "stairmaster-generic-v1" }, level: { v: 6, src: "manual" } } }));
await sleep(400);

const last = b.state.snaps.at(-1);
assert(last && last.climbers.length === 2, "both climbers in the snapshot");
const sly = last.climbers.find((c) => c.id === "a1");
assert(sly.metrics.steps.src === "pedometer" && sly.metrics.hr.v === 140, "provenance preserved");
assert(!("bogus" in sly.metrics), "unknown metric keys dropped");
const marcus = last.climbers.find((c) => c.id === "b2");
assert(marcus.metrics.steps.src === "estimated", "unknown source coerced to estimated");
assert(marcus.metrics.spm.model === "stairmaster-generic-v1", "model name kept");
assert(last.pack.size === 2 && last.pack.avgSpm === 70, `pack avg spm 70, got ${last.pack.avgSpm}`);

a.ws.send(JSON.stringify({ type: "cheer", text: "Keep going!" }));
await sleep(300);
assert(b.state.cheers.length === 1 && b.state.cheers[0].from === "Sly", "cheer relayed to the other climber");
assert(a.state.cheers.length === 0, "cheer not echoed to sender");

const live = await (await fetch(`${BASE}/v1/live`)).json();
assert(live.climbing === 2, `live board counts 2, got ${live.climbing}`);
assert(live.climbers.find((c) => c.city === "NYC"), "city visible on the board");
assert(live.rooms.find((r) => r.id === r1)?.count === 2, "room count reported to lobby");

a.ws.send(JSON.stringify({ type: "finish" }));
await sleep(400);
const wall = b.state.snaps.at(-1);
assert(wall.climbers.find((c) => c.id === "a1").finished === true, "finisher stays on the wall");
const live2 = await (await fetch(`${BASE}/v1/live`)).json();
assert(live2.climbing === 1, `finished climber leaves the live count, got ${live2.climbing}`);

a.ws.close(); b.ws.close();
console.log("smoke ok: rooms", r1, race, "| pack avg spm", last.pack.avgSpm);
process.exit(0);
