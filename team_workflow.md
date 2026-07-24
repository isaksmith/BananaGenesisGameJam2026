# Team Workflow — [GAME NAME] Game Jam

## Ground rules (read before you touch anything)
1. **Everyone uses the exact same Godot version:** [FILL IN, e.g. 4.x.x]
2. **GDScript only** (no C#).
3. **Never edit the same .tscn scene as someone else at the same time.**
   Scenes don't merge — they corrupt. Call it out in voice chat first.
4. **Pull `main` before you start a task and before you push.** ~every 30–60 min.
5. **Commit small and often** with clear messages.

## How we avoid conflicts: everyone owns different scenes
The game is built from many small scenes that get *instanced* into each other,
so we rarely touch the same file.

| Person | Owns |
|--------|------|
| [A]    | Player scene + script |
| [B]    | Enemies / obstacles (each its own scene) |
| [C]    | UI / menus / HUD |
| [D]    | Levels / world layout |
| [E]    | Systems (score, audio, game state) + **integrator: owns Main.tscn** |

Only the **integrator** assembles pieces into `Main.tscn`. If you need your scene
added to Main, ping the integrator instead of editing Main yourself.

## Git flow (lightweight)
```bash
git pull                       # always start here
git checkout -b player-jump    # short-lived branch for your task
# ...work, test in Godot...
git add -A
git commit -m "player: add jump + coyote time"
git pull origin main           # catch up before merging
git checkout main
git merge player-jump
git push
```

## If you get a conflict in a .tscn file
STOP. Do not hand-edit it. Tell the team. Cleanest fix: one version wins,
the other person re-applies their change manually in the editor.

## File & naming conventions (decided up front — no exceptions)

Last jam died in a mess of duplicate files, stand-ins mixed with finals, and five
naming styles at once. These rules prevent every bit of that.

### 1. One naming style for everything
- `snake_case`, all lowercase. **No spaces, no `#`, no double extensions.**
  - `mask sprite.png` ❌  →  `mask_sprite.png` ✅
  - `evilMonke.png.png` ❌  →  `evil_monke.png` ✅
  - `portrait#1_painting.tscn` ❌  →  `portrait_1_painting.tscn` ✅
- Name assets by **role, not by look**: `player_idle.png`, not `cute_clown_frame.png`.
  Role-names survive redesigns.

### 2. One home per file type — never mix them
```
project.godot            # ONLY config files live at the root
icon.svg
/scenes                  # ONLY .tscn — grouped by area:
    /player  /enemies  /ui  /levels
/scripts                 # ONLY .gd  (or keep a script beside its scene — pick ONE way)
/assets                  # ONLY art / audio / fonts:
    /sprites  /audio  /fonts
    /_placeholder        # ALL stand-in art goes here (underscore sorts it to top)
```
Nothing loose at the project root. A scene never goes in /scripts; a script never
goes in /assets.

### 3. Stand-in → final: same name, swap in place
- Every placeholder lives in `/assets/_placeholder/`.
- When real art arrives, **overwrite the file at the same path with the same name**,
  then delete the placeholder. Scenes reference art by path, so a same-name swap
  updates the art everywhere and you NEVER end up with two versions.

### 4. Two Godot habits that prevent orphans & duplicates
- **Rename/move files inside Godot's FileSystem dock, never in Finder.** Godot
  auto-updates every reference (and the `.uid`); Finder silently breaks them.
- **When you reorganize, delete the original in the SAME commit.** Move + delete
  together, or don't move.

### 5. Reuse over sprawl
One reusable `back_button.gd` on every button — not one script per button. Fewer
files, fewer names, fewer conflicts.

## Nightly cleanup checkpoint (10 min)
Each night, one person sweeps for stray files, wrong-folder files, and unused
placeholders. Ten minutes nightly beats an unusable repo on submission day.
