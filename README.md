# Banana Genesis

A comedy monkey-civilization jam game built in **Godot 4.7**. Explore a jungle hub, enter shrines, invent wheels, cook bananas, defend your stash, and outrun a leopard in the maze.

**Repos:** [BananaGenesisGameJam2026](https://github.com/isaksmith/BananaGenesisGameJam2026)

## Run

1. Install [Godot 4.7+](https://godotengine.org/download) (Forward Plus).
2. Open this folder as a project (`project.godot`).
3. Press **F5** / Play — main scene is `scenes/main.tscn`.

```bash
godot --path .
```

## Controls

| Action | Keys |
|--------|------|
| Move | `WASD` / Arrow keys |
| Jump | `Space` |
| Interact / Enter shrine | `E` |
| Exit minigame | `Esc` / `Q` (where enabled) |

## Modes

From the **home hub**, walk to a shrine and press **E**:

| Shrine | Mode |
|--------|------|
| **Banana Chef** | Short-order kitchen — prep, blend, serve banana dishes |
| **Banana Defense** | Protect the stash from gorilla thieves for 30s (or clear them early) |
| **Banana Maze** | Collect every banana while a leopard hunts you (3 lives) |
| **Wheel Trails** | Draw a steering wheel, then ride themed courses in a banana cart |

### Wheel trails

Draw your own wheel shape, then race across themed courses such as Gap Gorge, Needle Pass, Frost Fjord, Desert Sky, Moon Graveyard, Lunar Void, and Tiger Trail. Wheel size and roundness change jump, grip, and what you can clear.

## Project layout

```
scenes/          Hub, minigames, UI
scripts/         Gameplay logic
assets/sprites/  Characters, platforms, shrine art
assets/audio/    Hub + trail music, SFX
assets/video/    Hub / defense / maze background loops
assets/credits/  Third-party asset credits
```

## Credits

Third-party itch.io / FreePixel / Kenney assets are listed in [`assets/credits/ITCH_CREDITS.md`](assets/credits/ITCH_CREDITS.md). Please support those creators if you can.

## Play online (itch.io)

A browser build is exported with Godot’s **Web** preset (single-threaded, Compatibility/WebGL):

1. In Godot: **Project → Export → Web → Export Project**  
   (preset is saved in `export_presets.cfg`; output goes to `builds/web/`).
2. Zip the **contents** of `builds/web/` so `index.html` is at the zip root  
   (also produced as `builds/banana-genesis-web.zip`).
3. On [itch.io](https://itch.io/game/new): create a project → **Kind: HTML** → upload the zip → enable **This file will be played in the browser**.
4. Viewport size: **1280 × 720**. Pricing: **No payments / free**.

## License

Jam project — see asset credit files for third-party terms. Game code is provided for the jam unless otherwise noted.
