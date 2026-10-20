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

License
-------

This project is licensed under the Apache 2.0 License, with the following exceptions: 

* The font (in [assets/fonts/](https://github.com/heroiclabs/fishgame-godot/blob/main/assets/fonts)) and a handful of art assets (in [assets/kenney-platform-deluxe/](https://github.com/heroiclabs/fishgame-godot/blob/main/assets/kenney-platform-deluxe)) originate from CC0 sources (see [CREDITS-CC0.txt](https://github.com/heroiclabs/fishgame-godot/blob/main/CREDITS-CC0.txt)).
* The remaining art, music and sound assets are licensed under the [CC BY-NC License](https://github.com/heroiclabs/fishgame-godot/blob/main/assets/LICENSE.txt).
* The [Snopek State Machine](https://gitlab.com/snopek-games/godot-state-machine) included in [addons/snopek-state-machine/](https://github.com/heroiclabs/fishgame-godot/tree/main/addons/snopek-state-machine) is licensed under the MIT License.
* Most of the UI code (included in [main/](https://github.com/heroiclabs/fishgame-godot/tree/main/main)) and some other auxilary code files originate from the [WebRTC and Nakama addon for Godot](https://gitlab.com/snopek-games/godot-nakama-webrtc), which is licensed under the MIT License.

