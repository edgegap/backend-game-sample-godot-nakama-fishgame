# Fish Game on Edgegap + Nakama: migration plan

> Status: Phases 0-4 done and tested end to end on Edgegap (2026-10-20). The setup guide is [EDGEGAP.md](EDGEGAP.md). Phase 5 (publishing) and the art licence question are still open.

Fork: https://github.com/edgegap/fishgame-godot (upstream `heroiclabs/fishgame-godot`, archived, Apache-2.0 code, CC BY-NC art/music).

Goal: keep Nakama for accounts, matchmaking and leaderboards, and move the match itself onto a headless Godot dedicated server that the Nakama matchmaker starts on Edgegap through [edgegap/nakama-edgegap](https://github.com/edgegap/nakama-edgegap).

## What the game does today

- **Engine / backend:** Godot 3.2.3, bundled Nakama Godot addon 2.x, Nakama 2.15 + CockroachDB in `docker-compose.yml`. About 2,500 lines of GDScript.
- **Transport:** `NakamaMultiplayerBridge` (`autoload/OnlineMatch.gd`). Godot's high-level multiplayer (`rpc`, `remotesync`, `master`) runs over Nakama's realtime socket, so all game traffic is relayed through Nakama. There's no WebRTC and no game server.
- **Authority:** the first player in the match is peer 1, the host. The host runs the game flow (`Main.gd` ready/score/round, `Game.gd` setup handshake), the pickup spawners (`objects/TimedGenerator.gd`) and pickup physics (`pickups/Pickup.gd`). Each player owns their own fish: movement is sent by `update_remote_player` in `actors/Player.gd`, and the victim decides whether a hit landed (`components/Hitbox.gd` checks `body.is_network_master()`).
- **Nakama features used:** email auth, socket matchmaker (`+properties.client_version`), create/join match by ID, client-written leaderboard `fish_game_wins` (`Main.gd:update_wins_leaderboard`).
- **Modes:** local 2-player on one machine, plus online.

Good news: the code already uses Godot's high-level multiplayer with peer 1 as authority. Swapping the bridge for ENet and making peer 1 a headless server replaces the host role. It's not a rewrite.

## Target architecture

```
Client ──email auth──▶ Nakama (Go plugin: nakama-edgegap + game module)
Client ──socket.add_matchmaker──▶ Nakama matchmaker
                       └─ OnMatchmakerMatched ─▶ FleetManager.Create(userIds, metadata{user_ids})
                                                   └─▶ Edgegap deploy (placed by player IPs)
Game server boots ─ ENet listen 7777/UDP ─ POST NAKAMA_INSTANCE_EVENT_URL {READY}
Nakama ──notification 111 {IpAddress, Port, InstanceId}──▶ each client
Client ──ENet──▶ <ip>:<external port>, hello RPC {user_id, username}
Server ── POST NAKAMA_CONNECTION_EVENT_URL {connections:[user_ids]} (batched ~5 s)
Match won (5 rounds) ─ server reports result to Nakama (leaderboard) ─ POST {STOP} ─▶ deployment stops
```

Instance ID = `ARBITRIUM_REQUEST_ID` (that's what the Unity server plugin uses).

## Decisions to confirm

1. **Godot version: port to Godot 4.3+ (recommended).** Edgegap's Godot plugin and docs require 4.3+, Nakama's Godot addon 3.4 targets Godot 4, and a Godot 3.2 sample in 2026 looks dated. The cost is a GDScript 2 port (`yield`→`await`, `setget`, `remotesync`→`@rpc`, `export`→`@export`, `instance()`→`instantiate()`, KinematicBody2D→CharacterBody2D, TileMap changes) of about 2.5k lines. The alternative is staying on Godot 3.6, which is faster to an e2e result but isn't covered by our plugin or docs.
2. **Authority for v1: server replaces the host, plus server-side hits and scoring.** Fish movement stays client-owned for v1, since full server-side movement with prediction would be a rewrite. Hit detection (`Hitbox.gd`), deaths, pickups, spawners, rounds and the winner move to the server. This removes the obvious cheats (immortality, fake wins) and keeps the diff readable. Full server movement is a possible v2.
3. **Leaderboard written by the server, not the client.** Make `fish_game_wins` authoritative. The server calls a custom S2S RPC `report_match_result` (Nakama `http_key` as a **hidden** env var on the app version) with the winner's user_id. Clients can no longer post wins.
4. **Private matches:** v1 is matchmaker only. "Create/Join by ID" can come back later through the plugin's `instance_create` / `instance_join` RPCs (v2).
5. **Art licence (CC BY-NC):** check with legal whether an Edgegap-published sample counts as commercial use. If it does, replace the BY-NC assets with CC0 ones (Kenney already covers some of them). Keep this separate from the netcode work.

## Repo layout after the work

```
/                      Godot project (unchanged location, keeps the fork diff readable)
autoload/EdgegapServer.gd   headless server bootstrap: env, ENet, Nakama events, self-stop
autoload/OnlineMatch.gd     rewritten: matchmaker ticket → notification → ENet client
nakama/                Go module: main.go, Dockerfile (pluginbuilder 3.39), docker-compose (Postgres), local.yml.example
server/Dockerfile      game server image (Godot headless + .pck)
EDGEGAP.md             setup + run guide (replaces this plan)
```

## Work breakdown

### Phase 0: Port to Godot 4 (if decision 1 = yes)
- Upgrade the project with Godot 4.3's converter, then fix it by hand. Replace the bundled Nakama addon with nakama-godot 3.4 (Godot 4).
- Keep the bridge for now. Done when local 2-player mode and the old relayed online mode both play a full match.

### Phase 1: Nakama backend (`nakama/`)
- Copy `main.go`, `Dockerfile` and `docker-compose.yml` from nakama-edgegap (Nakama 3.39, Postgres).
- Register `OnAuthenticateUpdateEmail` (the plugin's sample only registers Custom; Fish Game uses email auth) so player IPs are stored for placement.
- Add `OnMatchmakerMatched` from the plugin README. Pass `metadata{"user_ids", "usernames"}` and use the 6-argument `Create` (the README sample is missing `latencies`).
- Port `fish_game.lua`: create the `fish_game_wins` leaderboard as authoritative in `InitModule`, and add the S2S `report_match_result` RPC.
- Env: `EDGEGAP_API_TOKEN`, `EDGEGAP_APPLICATION=fishgame-godot`, `INITIAL_EDGEGAP_VERSION`, `EDGEGAP_PORT_NAME=gameport`, `NAKAMA_ACCESS_URL` (https).
- **Blocker for e2e:** Edgegap deployments must reach Nakama over public https (event URLs, webhooks). For testing, expose local Nakama through a `cloudflared` quick tunnel. Publicly, document Heroic Cloud or a VM.

### Phase 2: Dedicated server (`autoload/EdgegapServer.gd`)
- Start as a server when `DisplayServer.get_name() == "headless"` or `--server` is passed. `ENetMultiplayerPeer.create_server(7777, 4)`.
- Read `ARBITRIUM_REQUEST_ID`, `NAKAMA_INSTANCE_EVENT_URL`, `NAKAMA_CONNECTION_EVENT_URL` and `NAKAMA_INSTANCE_METADATA` (expected user_ids).
- POST `READY` once listening. Accept only expected user_ids in the hello RPC, kick anyone else. Batch the connection list every ~5 s.
- Self-stop by POSTing `STOP` (with `get_tree().quit()` as a fallback):
  - Match won.
  - Fewer than 2 players left.
  - Nobody connected within 60 s.
  - A hard cap of 20 min.
- Game changes:
  - The server is peer 1 and has no fish, so filter it out of `players` in `Main.gd`/`Game.gd`.
  - The server owns ready/round/score (already gated on `is_network_server()`).
  - Move hit checks in `Hitbox.gd` to the server.
  - Skip UI and music when headless.
- Linux export preset "Linux Server" (dedicated server mode, strip visuals), plus `server/Dockerfile` (base: `edgegap_generate_dockerfile` for Godot, non-root user).

### Phase 3: Client (`OnlineMatch.gd`, screens)
- Remove `NakamaMultiplayerBridge`. Keep the socket matchmaker ticket (`min 2 / max 4`, `client_version`).
- Handle `received_notification`:
  - 111 → `ENetMultiplayerPeer.create_client(ip, port)` → hello RPC.
  - 112/113 → error screen.
- Match screen: keep only "Matchmaker". Ready screen: list connected players from the server, not Nakama presences.
- Leaderboard screen unchanged (reads only).
- Nakama host/port/scheme/key from a config file or command-line args, so the same client build works locally and against the tunnel.

### Phase 4: Edgegap + e2e
- Use the Edgegap MCP:
  - App `fishgame-godot`.
  - Version with port `gameport` 7777 UDP, 0.5 vCPU / 512 MB (`edgegap_validate_server_config`) and env `NAKAMA_HTTP_KEY` hidden.
  - Push to the Edgegap registry.
- Local first: Nakama compose + `docker run` server with fake env + 2 clients connecting directly.
- Then real: 2 clients on the same machine → matchmaker → deployment near us → full 5-round match → leaderboard +1 for the winner → deployment stops itself (check `edgegap_get_deployment`).
- Clean up test deployments and record leftover resources.

### Phase 5: Publish
- `EDGEGAP.md` guide, README section, GitHub Actions export for client + server image.
- Follow-ups: Edgegap docs page "Godot + Nakama sample", and an `edgegap-godot` skill in agent-skills (the pack has no Godot skill yet).

## Risks

- The Godot 4 port of physics and animation can change game feel. Compare against upstream builds.
- Client-owned movement means teleport/speed cheats are still possible in v1. Say so in the README.
- ENet over UDP doesn't work in HTML5 exports. The web client would need WebSocket (port `ws`); out of scope for v1.
- Nakama notifications arrive only on an open socket. The client keeps it open while matchmaking.
