# StairMatch

Never climb alone. You get on a StairMaster in LA, someone gets on one in New York,
and you're in the same live room: same clock, their cadence next to yours, a pack that
notices when you fall off it.

## What's here

- `StairMatch/` — iPhone app (SwiftUI, iOS 26). Lobby = who's climbing right now, worldwide.
  Join drops you into the open room for your mode (Pack or Race). No scheduled slots.
- `StairMatchWatch/` — Apple Watch app. Runs the Stair Stepper workout, streams heart rate,
  cadence and steps to the phone, buzzes when you drop off the pack.
- `Shared/` — metric model with provenance + the wire protocol.
- `worker/` — Cloudflare Worker: a `Lobby` Durable Object (room registry, live board) and one
  `ClimbRoom` Durable Object per room (WebSocket fan-out). Rooms are created on demand and
  capped at 12; scheduled events can be added later as rooms with a fixed start.

## Where the numbers come from

A phone can't read a gym console, so every metric carries its source and the app shows it:

| source      | meaning                                                          |
|-------------|------------------------------------------------------------------|
| `pedometer` | Apple Watch / iPhone motion sensor (steps, steps per minute)      |
| `watch_hr`  | Apple Watch heart rate                                           |
| `manual`    | the machine level you typed                                      |
| `estimated` | modelled from level and time, model name attached, never console truth |
| `ftms`      | Bluetooth Fitness Machine Service (Stair Climber Data), future   |

Effort (0–100) = 60% heart-rate reserve + 40% cadence, so a level 6 beginner and a level 12
athlete sit in the same pack honestly.

## Running the relay locally

```
cd worker && npm install && npm run dev        # http://127.0.0.1:18787
python3 test/smoke.py                          # or: node test/smoke.mjs (node 22+)
```

Point the phone at it: `defaults write com.assiamah.stairmatcher relayURL http://<mac-ip>:18787`.

## Deploy

```
cd worker && npx wrangler login && npx wrangler deploy
```

iOS builds run in CI (`.github/workflows/ci.yml`): unsigned compile check, then cloud-signed
archive → TestFlight when the ASC secrets are present.
