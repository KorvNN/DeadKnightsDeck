<p>
  <img src="icon.svg" alt="Dead Knight's Deck" width="96" align="left">
</p>

# Dead Knight's Deck<br><sup><sup><em>"The knight is dead. The deck is not."</em></sup></sup>

Dead Knight's Deck is a 3D roguelike shooter built with Godot 4.6. Fight through
procedural stages, draft upgrades, evolve a growing weapon set, and push one run
deeper through the knight's afterlife.

## Highlights

- Fast first-person combat against escalating enemy waves
- Procedural garden mazes, castle floors, boss arenas, and branching afterlife stages
- Three-card level-up drafts with common, rare, epic, and legendary upgrades
- Pistols, revolvers, rifles, shotguns, sniper rifles, and weapon evolutions
- Critical hits, piercing rounds, burn and frost effects, grenades, shields, and lifesteal
- Run persistence across stages for health, ammunition, cards, gold, and progression
- Local leaderboard ranked by stage reached and completion time

## Quick start

Install [Godot 4.6](https://godotengine.org/), then open `project.godot` in the
editor and run the project with <kbd>F5</kbd>.

```bash
git clone https://github.com/KorvNN/DeadKnightsDeck.git
cd DeadKnightsDeck
godot --editor project.godot
```

## Controls

| Action | Control |
| --- | --- |
| Move | <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> |
| Look / shoot | Mouse / left click |
| Heavy attack | Right click |
| Jump / sprint | <kbd>Space</kbd> / <kbd>Shift</kbd> |
| Reload | <kbd>R</kbd> |
| Interact | <kbd>E</kbd> |
| Switch weapon | <kbd>Q</kbd> |
| Throw grenade | <kbd>G</kbd> |

## Project structure

| Path | Contents |
| --- | --- |
| `scenes/` | Player, enemies, stages, effects, and menus |
| `scripts/` | Combat, progression, procedural generation, and UI logic |
| `resources/cards/` | Draftable upgrades and weapon evolutions |
| `resources/weapons/` | Data-driven weapon definitions |
| `assets/` | Models, textures, audio, fonts, and visual effects |

Third-party audio credits and bundled asset licenses remain with their respective
files under `assets/` and `addons/`.
