"""Same smoke test for a Mac without node 22 (python websockets)."""
import asyncio, json, sys, urllib.request
BASE = __import__('os').environ.get('BASE', 'http://127.0.0.1:18787'); WS = BASE.replace("http", "ws")
import websockets
def post(path, body):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), headers={"content-type": "application/json"}, method="POST")
    return json.load(urllib.request.urlopen(req))
def get(path): return json.load(urllib.request.urlopen(BASE + path))
def ok(c, m):
    if not c: print("FAIL:", m); sys.exit(1)
async def main():
    r1 = post("/v1/join", {"mode": "pack"})["roomId"]; r2 = post("/v1/join", {"mode": "pack"})["roomId"]
    ok(r1 == r2, "same room"); race = post("/v1/join", {"mode": "race"})["roomId"]; ok(race.startswith("race-"), "race room")
    async with websockets.connect(f"{WS}/v1/rooms/{r1}/ws?id=a1&name=Sly&city=New%20Jersey") as a, \
               websockets.connect(f"{WS}/v1/rooms/{r1}/ws?id=b2&name=Marcus&city=NYC") as b:
        await a.recv(); await b.recv()
        await a.send(json.dumps({"type": "telemetry", "elapsed": 61, "metrics": {"steps": {"v": 120, "src": "pedometer"}, "spm": {"v": 72, "src": "pedometer"}, "level": {"v": 7, "src": "manual"}, "hr": {"v": 140, "src": "watch_hr"}, "bogus": {"v": 1, "src": "x"}}}))
        await b.send(json.dumps({"type": "telemetry", "elapsed": 30, "metrics": {"steps": {"v": 40, "src": "nope"}, "spm": {"v": 68, "src": "estimated", "model": "stairmaster-generic-v1"}, "level": {"v": 6, "src": "manual"}}}))
        last = None
        for _ in range(6):
            m = json.loads(await asyncio.wait_for(b.recv(), 2))
            if m["type"] == "snapshot": last = m
            if last and len(last["climbers"]) == 2 and all(c["metrics"] for c in last["climbers"]): break
        ok(last and len(last["climbers"]) == 2, "two climbers")
        sly = next(c for c in last["climbers"] if c["id"] == "a1"); marcus = next(c for c in last["climbers"] if c["id"] == "b2")
        ok(sly["metrics"]["steps"]["src"] == "pedometer" and sly["metrics"]["hr"]["v"] == 140, "provenance kept")
        ok("bogus" not in sly["metrics"], "unknown keys dropped")
        ok(marcus["metrics"]["steps"]["src"] == "estimated" and marcus["metrics"]["spm"]["model"] == "stairmaster-generic-v1", "coerced + model kept")
        ok(last["pack"]["size"] == 2 and last["pack"]["avgSpm"] == 70, f"avg spm {last['pack']['avgSpm']}")
        await a.send(json.dumps({"type": "cheer", "text": "Keep going!"}))
        m = json.loads(await asyncio.wait_for(b.recv(), 2)); ok(m["type"] == "cheer" and m["from"] == "Sly", "cheer relayed")
        live = get("/v1/live"); ok(live["climbing"] == 2, f"live 2 got {live['climbing']}")
        ok(any(c.get("city") == "NYC" for c in live["climbers"]), "city on board")
        ok(next(r for r in live["rooms"] if r["id"] == r1)["count"] == 2, "room count in lobby")
        await a.send(json.dumps({"type": "finish"}))
        for _ in range(4):
            m = json.loads(await asyncio.wait_for(b.recv(), 2))
            if m["type"] == "snapshot" and next(c for c in m["climbers"] if c["id"] == "a1")["finished"]: break
        else: ok(False, "finisher on wall")
        live2 = get("/v1/live"); ok(live2["climbing"] == 1, f"live after finish {live2['climbing']}")
    print("smoke ok:", r1, race, "avg spm", last["pack"]["avgSpm"])
asyncio.run(main())
