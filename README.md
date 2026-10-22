"Fish Game" for Godot
=====================

**"Fish Game" for Godot** is a 2-4 player online game built in the
[Godot](https://godotengine.org/) game engine, created as a demonstration of
[Nakama](https://heroiclabs.com/), an open-source scalable game server.

![Animated GIF showing gameplay](assets/screenshots/gameplay.gif)

> **This fork runs online matches on dedicated servers on [Edgegap](https://edgegap.com),
> started by Nakama through the [Edgegap Fleet Manager](https://github.com/edgegap/nakama-edgegap),
> and is ported to Godot 4. See [EDGEGAP.md](EDGEGAP.md) for how it works and how to run it.**
> The original, peer-hosted version is at [heroiclabs/fishgame-godot](https://github.com/heroiclabs/fishgame-godot).

Licence
-------

**The code and the art are under different licences. Most of the art, music
and sound in this repository may not be used commercially.**

* **Code:** [Apache 2.0](LICENSE.txt), except the addons and UI code listed
  below, which are MIT.
* **Art, music and sound:** everything in [assets/](assets/) is
  © 2021 [Heroic Labs](https://heroiclabs.com/) under
  [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)
  ([assets/LICENSE.txt](assets/LICENSE.txt)), unless its folder says otherwise.
  That covers the fish and other sprites, backgrounds, tilesets, UI art, music
  and sound effects (`assets/backgrounds/`, `assets/music/`, `assets/sounds/`,
  `assets/sprites/`, `assets/tilesets/`, `assets/ui/`, and the gameplay GIF in
  `assets/screenshots/`). CC BY-NC means **non-commercial use only**, with
  credit to Heroic Labs.
* **CC0 exceptions:** the Monogram font in [assets/fonts/](assets/fonts/) and
  the Kenney tiles in [assets/kenney-platform-deluxe/](assets/kenney-platform-deluxe/)
  are CC0 (see [CREDITS-CC0.txt](CREDITS-CC0.txt)) and can be used anywhere.

You can use this repository to learn from and to try Edgegap and Nakama. **If
you ship a game based on it, commercial or otherwise sold, you must replace the
CC BY-NC art, music and sound with assets you have the rights to.** The code
can be reused under its own licence.

Other licences in the code:

* The [Snopek State Machine](https://gitlab.com/snopek-games/godot-state-machine) included in [addons/snopek-state-machine/](addons/snopek-state-machine/) is licensed under the MIT License.
* Most of the UI code (included in [main/](main/)) and some other auxilary code files originate from the [WebRTC and Nakama addon for Godot](https://gitlab.com/snopek-games/godot-nakama-webrtc), which is licensed under the MIT License.
* The [Nakama Godot client](https://github.com/heroiclabs/nakama-godot) in [addons/com.heroiclabs.nakama/](addons/com.heroiclabs.nakama/) is licensed under the Apache 2.0 License.

Playing the game from source
----------------------------

### Dependencies ###

You'll need:

* [Godot](https://godotengine.org/download) 4.7 (4.3 or later should work).
* [Docker](https://docs.docker.com/get-docker/), for Nakama and the game server image.
* An [Edgegap](https://edgegap.com) account, to host online matches.

### Running the game from source ###

1. Download the source code to your computer.
2. Open Godot and "Import" the project.
3. Press F5 or click the play button in the upper-right corner to start the game.

"Local" play works right away. For "Online" play, set up Nakama and the game
server as described in [EDGEGAP.md](EDGEGAP.md).

Licence
-------

See [Licence](#licence) at the top: the code is Apache 2.0 / MIT, but most art,
music and sound are CC BY-NC 4.0 (non-commercial) and must be replaced before
you ship a game.
