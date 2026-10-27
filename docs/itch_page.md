# Brickstellar — itch.io page

## Short description (tagline)

Fly a gun-ship paddle through 120 levels of shaped, moving bricks, beat a boss in every world and bring down THE ARCHITECT.

## Description

**Brickstellar** is a flat, colorful brick breaker where your paddle is a ship and the bricks fight back.

Smash pictures built from triangles, hearts, stars and hexagons. Dodge debris from giant bosses. Chain combos while the music climbs with every brick you break.

### Features

- **120 levels in 12 worlds.** Six themes, each with a harder "II" version, and a boss at the end of every world.
- **Bricks that move.** Bricks orbit, sway like waves, spin, and fade into phantoms the ball passes straight through.
- **A ship, not a paddle.** Your gun upgrades from single shot to double, triple, laser, big laser and homing missiles. Hold Space to boost and fill your energy for Overdrive.
- **Power-ups worth chasing:** multiball, wide ship, safety barrier, slow and fast ball, wider or tighter arena, extra lives.
- **Three stars per level.** Clear it, beat the par time, don't lose a life.
- **Online leaderboards** with clear times for every level.
- **Level editor:** paint your own levels with every brick shape and motion, then play them instantly.
- **14 ships to unlock** through progress and high scores.
- **The final boss, THE ARCHITECT,** changes form four times.

### Controls

| Key | Action |
|---|---|
| A / D or ← / → | Move |
| Space | Launch / bump the ball (hold to boost) |
| E | Overdrive (when energy is full) |
| Q (hold) | Pull the ball toward you (uses energy) |
| Esc | Pause |

### macOS note

The game isn't signed with an Apple certificate yet. The first time you open it, **right-click the app → Open**, then confirm.

### Credits

Music and sound effects: CC0 (Shapeforms Audio, Space Music Pack and CC0 music loops). Fonts: Kenney (CC0). Made with Godot.

---

## Page settings

- **Genre:** Action
- **Tags:** breakout, brick-breaker, arcade, retro, colorful, boss-battle, level-editor, singleplayer, casual, shoot-em-up
- **Release status:** Released (or "In development" if you plan more updates)
- **Pricing:** your choice ("No payments" or "Paid" with a suggested price)
- **Platforms:** macOS (add Windows / Linux when those builds are uploaded)

## Images (docs/itch/)

| File | Use on itch.io |
|---|---|
| `cover.png` (630x500) | Cover image (`cover@2x.png` 1260x1000 if you want a sharper one) |
| `screenshot_1.jpg` | Gameplay: house level, triple gun, combo, power-ups |
| `screenshot_2.jpg` | Boss fight: THE MONOLITH with multiball |
| `screenshot_3.jpg` | PHANTOM world: fading bricks, barrier, score popups |
| `screenshot_4.jpg` | Quest select: 12 worlds, stars |
| `screenshot_5.jpg` | Level editor |
| `screenshot_6.jpg` | Final boss: THE ARCHITECT |

Re-render the cover after changing it: `godot --write-movie <out>.png --fixed-fps 30 --quit-after 12 res://tools/cover/cover.tscn`, then crop the centered 1360x1080 frame and scale to 630x500.
