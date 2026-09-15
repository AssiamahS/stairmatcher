// StairMatch relay — a persistent live network of people on stair machines.
//
// Shape:
//   Lobby (singleton DO)  — registry of open rooms per mode, "who's climbing right now".
//   ClimbRoom (DO per room) — WebSocket fan-out of live telemetry, one room = one pack/race.
//
// A room is created on demand when nobody's open room for that mode has space,
// so a user who taps Join at 11:48 is climbing with whoever is live at 11:48.
// Scheduled events can later be modelled as rooms with a fixed startAt — the
// room code never assumes a wall-clock start.
//
// Every metric a client sends carries its provenance ({v, src}), because a
// phone can't know a StairMaster's real step count — see METRIC_SOURCES.

import { DurableObject } from "cloudflare:workers";

const MODES = ["pack", "race"];
const ROOM_CAP = 12;            // climbers per room before a new one opens
const CLIMBER_TTL_MS = 45_000;  // no telemetry for this long = dropped from the pack
const FINISHED_TTL_MS = 10 * 60_000; // finishers stay on the wall this long
const METRIC_SOURCES = ["pedometer", "watch_hr", "manual", "estimated", "ftms"];

const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", "access-control-allow-origin": "*", ...extra },
  });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "GET,POST,OPTIONS",
          "access-control-allow-headers": "content-type",
        },
      });
    }

    if (parts[0] !== "v1") return json({ ok: true, service: "stairmatch" });

    const lobby = env.LOBBY.get(env.LOBBY.idFromName("global"));

    // GET /v1/live — who's climbing right now (lobby aggregates every open room)
    if (parts[1] === "live" && parts.length === 2) return lobby.fetch(request);

    // POST /v1/join {mode} → {roomId}
    if (parts[1] === "join" && request.method === "POST") return lobby.fetch(request);

    // /v1/rooms/:id/ws | /v1/rooms/:id/snapshot
    if (parts[1] === "rooms" && parts[2]) {
      const room = env.ROOMS.get(env.ROOMS.idFromName(parts[2]));
      return room.fetch(request);
    }

    return json({ error: "not found" }, 404);
  },
};

// ---------------------------------------------------------------------------
// Lobby: room registry + live aggregate
// ---------------------------------------------------------------------------
export class Lobby extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS rooms (
      id TEXT PRIMARY KEY,
      mode TEXT NOT NULL,
      count INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`);
  }

  async fetch(request) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (parts[1] === "join") {
      let body = {};
      try { body = await request.json(); } catch { /* empty body = pack */ }
      const mode = MODES.includes(body.mode) ? body.mode : "pack";
      return json({ roomId: this.pickRoom(mode), mode });
    }

    if (parts[1] === "live") return json(await this.live());

    // Internal: rooms report their occupancy.
    if (parts[1] === "report" && request.method === "POST") {
      const { id, mode, count } = await request.json();
      this.report(id, mode, count);
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  }

  pickRoom(mode) {
    this.prune();
    const open = this.sql
      .exec(`SELECT id FROM rooms WHERE mode = ? AND count < ? ORDER BY count DESC, created_at ASC LIMIT 1`, mode, ROOM_CAP)
      .toArray();
    if (open.length) return open[0].id;
    const id = `${mode}-${crypto.randomUUID().slice(0, 8)}`;
    const now = Date.now();
    this.sql.exec(`INSERT INTO rooms (id, mode, count, created_at, updated_at) VALUES (?, ?, 0, ?, ?)`, id, mode, now, now);
    return id;
  }

  report(id, mode, count) {
    const now = Date.now();
    if (count <= 0) {
      this.sql.exec(`DELETE FROM rooms WHERE id = ?`, id);
      return;
    }
    this.sql.exec(
      `INSERT INTO rooms (id, mode, count, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET count = excluded.count, updated_at = excluded.updated_at`,
      id, mode, count, now, now,
    );
  }

  prune() {
    // A room that hasn't reported in 10 minutes is gone (its DO was evicted or it emptied).
    this.sql.exec(`DELETE FROM rooms WHERE updated_at < ?`, Date.now() - 10 * 60_000);
  }

  async live() {
    this.prune();
    const rooms = this.sql.exec(`SELECT id, mode, count, created_at FROM rooms ORDER BY created_at ASC`).toArray();
    const snapshots = await Promise.all(
      rooms.map(async (r) => {
        try {
          const stub = this.env.ROOMS.get(this.env.ROOMS.idFromName(r.id));
          const res = await stub.fetch(`https://room/v1/rooms/${r.id}/snapshot`);
          return await res.json();
        } catch {
          return null;
        }
      }),
    );
    const climbers = [];
    const roomList = [];
    for (const s of snapshots) {
      if (!s) continue;
      const active = s.climbers.filter((c) => !c.finished);
      roomList.push({ id: s.room.id, mode: s.room.mode, count: active.length, startedAt: s.room.startedAt, pack: s.pack });
      for (const c of active) climbers.push({ ...publicClimber(c), roomId: s.room.id, mode: s.room.mode });
    }
    return {
      now: Date.now(),
      climbing: climbers.length,
      rooms: roomList,
      climbers: climbers.sort((a, b) => b.elapsed - a.elapsed),
    };
  }
}

// ---------------------------------------------------------------------------
// ClimbRoom: one live pack or race
// ---------------------------------------------------------------------------
export class ClimbRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx = ctx;
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)`);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS climbers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      city TEXT,
      joined_at INTEGER NOT NULL,
      last_seen INTEGER NOT NULL,
      elapsed REAL NOT NULL DEFAULT 0,
      metrics TEXT NOT NULL DEFAULT '{}',
      finished INTEGER NOT NULL DEFAULT 0,
      finished_at INTEGER
    )`);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  meta(k) {
    const r = this.sql.exec(`SELECT v FROM meta WHERE k = ?`, k).toArray();
    return r.length ? r[0].v : null;
  }
  setMeta(k, v) {
    this.sql.exec(`INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v`, k, String(v));
  }

  async fetch(request) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean); // v1 rooms :id ws|snapshot
    const roomId = parts[2];
    if (!this.meta("id")) {
      this.setMeta("id", roomId);
      this.setMeta("mode", roomId.split("-")[0]);
      this.setMeta("startedAt", Date.now());
    }

    if (parts[3] === "snapshot") return json(this.snapshot());

    if (parts[3] === "ws") {
      if (request.headers.get("Upgrade") !== "websocket") return json({ error: "expected websocket" }, 426);
      const id = url.searchParams.get("id");
      const name = (url.searchParams.get("name") || "Climber").slice(0, 24);
      const city = (url.searchParams.get("city") || "").slice(0, 40) || null;
      if (!id) return json({ error: "id required" }, 400);

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.ctx.acceptWebSocket(server, [id]);
      server.serializeAttachment({ id });

      const now = Date.now();
      this.sql.exec(
        `INSERT INTO climbers (id, name, city, joined_at, last_seen) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, city = excluded.city, last_seen = excluded.last_seen, finished = 0, finished_at = NULL`,
        id, name, city, now, now,
      );
      await this.afterChange();
      server.send(JSON.stringify({ type: "hello", you: id, ...this.snapshot() }));
      return new Response(null, { status: 101, webSocket: client });
    }

    return json({ error: "not found" }, 404);
  }

  async webSocketMessage(ws, raw) {
    let msg;
    try { msg = JSON.parse(raw); } catch { return; }
    const { id } = ws.deserializeAttachment() || {};
    if (!id) return;
    const now = Date.now();

    if (msg.type === "telemetry") {
      const metrics = sanitizeMetrics(msg.metrics);
      const elapsed = Number.isFinite(msg.elapsed) ? Math.max(0, msg.elapsed) : 0;
      this.sql.exec(`UPDATE climbers SET elapsed = ?, metrics = ?, last_seen = ? WHERE id = ?`, elapsed, JSON.stringify(metrics), now, id);
      await this.afterChange();
    } else if (msg.type === "finish") {
      this.sql.exec(`UPDATE climbers SET finished = 1, finished_at = ?, last_seen = ? WHERE id = ?`, now, now, id);
      await this.afterChange();
    } else if (msg.type === "cheer") {
      // Lightweight social: relay a canned cheer to everyone else.
      const text = String(msg.text || "").slice(0, 40);
      const from = this.sql.exec(`SELECT name FROM climbers WHERE id = ?`, id).toArray()[0];
      this.broadcast({ type: "cheer", from: from?.name || "Someone", text }, id);
    }
  }

  async webSocketClose(ws) {
    await this.handleLeave(ws);
  }
  async webSocketError(ws) {
    await this.handleLeave(ws);
  }

  async handleLeave(ws) {
    const { id } = ws.deserializeAttachment() || {};
    // Don't drop instantly — a phone that loses signal for 20s should still be in the pack.
    // The alarm-driven prune removes climbers whose last_seen is stale.
    if (id) this.sql.exec(`UPDATE climbers SET last_seen = ? WHERE id = ? AND finished = 0`, Date.now() - CLIMBER_TTL_MS / 2, id);
    await this.afterChange();
  }

  async alarm() {
    await this.afterChange();
  }

  async afterChange() {
    const now = Date.now();
    this.sql.exec(`DELETE FROM climbers WHERE finished = 0 AND last_seen < ?`, now - CLIMBER_TTL_MS);
    this.sql.exec(`DELETE FROM climbers WHERE finished = 1 AND finished_at < ?`, now - FINISHED_TTL_MS);
    const snap = this.snapshot();
    this.broadcast({ type: "snapshot", ...snap });
    const active = snap.climbers.filter((c) => !c.finished).length;
    try {
      const lobby = this.env.LOBBY.get(this.env.LOBBY.idFromName("global"));
      await lobby.fetch("https://lobby/v1/report", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: snap.room.id, mode: snap.room.mode, count: active }),
      });
    } catch { /* lobby will prune us if we go quiet */ }
    if (snap.climbers.length) await this.ctx.storage.setAlarm(now + 15_000);
  }

  broadcast(obj, exceptId) {
    const data = JSON.stringify(obj);
    for (const ws of this.ctx.getWebSockets()) {
      const { id } = ws.deserializeAttachment() || {};
      if (exceptId && id === exceptId) continue;
      try { ws.send(data); } catch { /* closing */ }
    }
  }

  snapshot() {
    const rows = this.sql.exec(`SELECT * FROM climbers ORDER BY joined_at ASC`).toArray();
    const climbers = rows.map((r) => ({
      id: r.id,
      name: r.name,
      city: r.city,
      joinedAt: r.joined_at,
      lastSeen: r.last_seen,
      elapsed: r.elapsed,
      metrics: JSON.parse(r.metrics || "{}"),
      finished: !!r.finished,
      finishedAt: r.finished_at,
    }));
    const active = climbers.filter((c) => !c.finished);
    const avg = (key) => {
      const vals = active.map((c) => c.metrics[key]?.v).filter((v) => Number.isFinite(v));
      return vals.length ? Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 10) / 10 : null;
    };
    return {
      room: { id: this.meta("id"), mode: this.meta("mode"), startedAt: Number(this.meta("startedAt")) },
      climbers,
      pack: { size: active.length, avgSpm: avg("spm"), avgEffort: avg("effort"), avgLevel: avg("level") },
      now: Date.now(),
    };
  }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
const METRIC_KEYS = ["steps", "spm", "level", "hr", "effort", "floors", "kcal"];

/** Keep only known metrics, each as {v:number, src:<METRIC_SOURCES>, model?:string}. */
function sanitizeMetrics(input) {
  const out = {};
  if (!input || typeof input !== "object") return out;
  for (const k of METRIC_KEYS) {
    const m = input[k];
    if (!m || typeof m !== "object") continue;
    const v = Number(m.v);
    if (!Number.isFinite(v)) continue;
    const src = METRIC_SOURCES.includes(m.src) ? m.src : "estimated";
    out[k] = { v: Math.round(v * 100) / 100, src };
    if (typeof m.model === "string") out[k].model = m.model.slice(0, 40);
  }
  return out;
}

function publicClimber(c) {
  return {
    id: c.id,
    name: c.name,
    city: c.city,
    elapsed: c.elapsed,
    metrics: c.metrics,
    finished: c.finished,
  };
}
