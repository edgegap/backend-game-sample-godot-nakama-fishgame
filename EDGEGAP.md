# Fish Game on Edgegap + Nakama

This fork runs every online match of Fish Game on its own dedicated server on
[Edgegap](https://edgegap.com). [Nakama](https://heroiclabs.com) keeps doing
accounts, matchmaking and the leaderboard, and starts the servers through the
[Edgegap Fleet Manager for Nakama](https://github.com/edgegap/nakama-edgegap).

Upstream ran each match on one player's machine (the "host"), relayed through
Nakama. Here no player hosts: a headless Godot server near the players runs the
match and decides hits, deaths, rounds and the winner.

```
Player ──email sign-in──▶ Nakama ◀──────────── events, results ───────────┐
Player ──matchmaker ticket──▶ Nakama ──Fleet Manager──▶ Edgegap deployment │
                                         (near the matched players)        │
Game server boots, listens on UDP 7777 ──READY──────────────────────────────┘
Nakama ──notification: server IP + port──▶ each player
Player ──ENet──▶ game server: checks the player's Nakama session, then plays
Match won ──▶ server records the win in Nakama ──STOP──▶ deployment ends
```

## What's where

| Path | What it does |
|---|---|
| `autoload/OnlineMatch.gd` | Client: matchmaker ticket, server address notification, ENet connection. Server: lets matched players in. |
| `autoload/EdgegapServer.gd` | Dedicated server mode: listens, reports READY / connections / STOP to Nakama, stops itself. |
| `Main.gd`, `Game.gd`, `actors/Player.gd`, `components/Hitbox.gd` | Game flow. Online, the server (peer 1) owns rounds, pickups, hits and deaths. |
| `nakama/` | Nakama 3.39 + a Go module: Fleet Manager, matchmaker hook, authoritative `fish_game_wins` leaderboard. |
| `server/Dockerfile` | Exports the "Linux Server" preset to a `.pck` and runs it with headless Godot. |
| `tests/` | Local smoke test, and the network test client used locally and on Edgegap. |

## Requirements

- Godot 4.7 (4.3 or later should work).
- Docker.
- An Edgegap account and API token.
- A public HTTPS address for Nakama. Edgegap servers call Nakama back, so
  `localhost` won't work; for testing, a tunnel is enough (step 2).

## 1. Put the game server on Edgegap

Build the image from the repository root and push it to your Edgegap registry
(dashboard > Container Registry has the project, username and token):

```bash
docker build --platform linux/amd64 -f server/Dockerfile -t registry.edgegap.com/<project>/fishgame-godot:1.0.0 .
```

```bash
docker push registry.edgegap.com/<project>/fishgame-godot:1.0.0
```

In the Edgegap dashboard, create the application `fishgame-godot` and a
version `1.0.0`:

- Image `<project>/fishgame-godot`, tag `1.0.0`, with your registry username and token.
- 0.5 vCPU, 512 MB.
- One port: name `gameport`, 7777, UDP.
- A max duration (30 minutes is plenty; the server also stops itself).

The server needs no environment variables of its own: the Fleet Manager passes
it Nakama's callback URLs on every deployment.

## 2. Run Nakama

```bash
cp nakama/.env.example nakama/.env
```

Fill in `nakama/.env`:

- `EDGEGAP_API_TOKEN`: your Edgegap API token, with its `token ` prefix. It is
  org-wide, so it stays in this file and in Nakama only.
- `EDGEGAP_APPLICATION`, `INITIAL_EDGEGAP_VERSION`, `EDGEGAP_PORT_NAME`: the
  application, version and port name from step 1.
- `NAKAMA_ACCESS_URL`: Nakama's public HTTPS address.
- `NAKAMA_HTTP_KEY`: a long random string.

For a test on your own machine, a Cloudflare quick tunnel gives Nakama a public
address. Put the `https://….trycloudflare.com` URL it prints in
`NAKAMA_ACCESS_URL`:

```bash
docker run -d --name fishgame-tunnel cloudflare/cloudflared:latest tunnel --no-autoupdate --url http://host.docker.internal:7350
```

Then start Nakama and Postgres:

```bash
docker compose -p fishgame -f nakama/docker-compose.yml up -d --build
```

## 3. Play

Point the game at Nakama, either by editing the defaults at the top of
`autoload/Online.gd` or on the command line:

```bash
godot --path . -- --nakama-host=your-tunnel.trycloudflare.com --nakama-port=443 --nakama-scheme=https
```

Players should reach Nakama through its public address too: Nakama stores the
IP each player signs in from, and Edgegap uses those IPs to put the server near
them.

Start two copies of the game, pick **Online**, create an account in each, and
press **Match** in both. After "Match found! Starting a game server...",
both land on the ready screen of the same Edgegap server. The first fish to win
5 rounds wins the match, and gets +1 on the leaderboard.

### Without Nakama or Edgegap

For netcode work, run a server and connect clients straight to it:

```bash
godot --headless --path .
```

```bash
godot --path . -- --connect=127.0.0.1:7777
```

With no Nakama configured, the server lets anyone in and stops when the match
ends.

## Tests

| Test | Command |
|---|---|
| Local play: the map loads, fish land, pick up, swing and throw without errors | `godot --path . --script res://tests/smoke_test.gd` |
| Network, local server | `godot --headless --path . -- --test-auto-hit`, then twice: `godot --headless --path . --script res://tests/net_test_client.gd -- --client --connect=127.0.0.1:7777` |
| End to end on Edgegap | Set `FISHGAME_TEST_AUTO_HIT=true` in `nakama/.env`, then twice: `godot --headless --path . --script res://tests/net_test_client.gd -- --client --timeout=300 --email=<unique>@example.com --nakama-host=<tunnel host> --nakama-port=443 --nakama-scheme=https` |

`--test-auto-hit` (or `FISHGAME_TEST_AUTO_HIT`, which Nakama passes to the
server in the instance metadata) makes the server hit one fish per round, so
matches finish without anyone playing. Leave it off for real games.

## How the server behaves

- It starts in server mode when Godot runs headless (or with `-- --server`).
- Once listening, it sends `READY` with its own IP and external port. Nakama
  then tells the matched players where to connect.
- It only accepts players whose Nakama session is valid, as checked with
  Nakama's `/v2/account`, and who were matched to this server.
- It reports the connected user IDs to Nakama every 5 seconds when they change.
- It sends `STOP`, which makes Nakama stop the deployment:
  - when the match is won (after recording the win),
  - when fewer than 2 players are left mid-match,
  - when everyone leaves,
  - when nobody joins within 60 seconds,
  - after 20 minutes.

## What's server-authoritative, and what isn't

The server decides who gets hit, who dies, pickups, spawns, rounds, the winner
and leaderboard wins. Players can't post wins themselves: the leaderboard is
authoritative, and `report_match_result` refuses player sessions.

Each player still owns their fish's movement and sends its position, like
upstream. A modified client could move faster or teleport. Moving movement to
the server, with client prediction, is the next step for a competitive game.

## Known limits

- ENet is UDP, which browsers can't use, so the HTML5 export can't play online.
  A web build would need Godot's WebSocket peer and a WS port with TLS Upgrade.
- Private matches by ID were removed: every match comes from the matchmaker.
  The Fleet Manager's `instance_create` / `instance_join` RPCs could bring them
  back.
- Most art and music are CC BY-NC (see `assets/LICENSE.txt`).
