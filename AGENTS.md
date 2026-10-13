# Agent Guidelines for Pollen Ranger

> **Start here:** Read `DESIGN.md` first to understand the game concept, mechanics, and visual style.

## Project Overview

Pollen Ranger is a first-person greenhouse reclamation game built in Godot 4.7. You are a thumb-sized seed-pod golem armed with a dandelion sniper, purging a creeping gray rot ("The Blight") from an overgrown greenhouse.

## Key Principles

### Scale
Everything is **HUGE** from the player's perspective. The player is thumb-sized:
- A clay pot is 2+ meters tall
- A hanging basket is a platform, not a decoration
- Soil grids cover large areas, not tiny patches

### Feel Over Realism
- Movement should feel **floaty and lightweight** (you're made of seeds and fluff)
- Projectiles should be **fast but visible** with trails
- Gliding should feel **peaceful**, not frantic
- Cleansing Blight should feel **satisfying** — punchy particle effects, audio cues

### Metroidvania Structure
The greenhouse is divided into biomes (Orchid Tropics, Cactus Desert, Compost Catacombs). Each biome:
- Has a boss (Queen Weevil)
- Is locked until the previous biome is cleansed
- Opens new traversal options when cleared (vines, updrafts, etc.)

## Code Style

- Use GDScript with static typing: `var x: int = 5`
- Document "feel" goals in comments: `# Should feel floaty, like you're weightless`
- Keep scripts focused — one responsibility per file
- Use `@onready` for node references
- Prefer signals for inter-node communication

## Directory Structure

```
scenes/
  player/     # Player controller, camera, arm cannon
  props/      # Modular greenhouse pieces (pots, trellis, baskets)
  enemies/    # Blighted creatures, bosses
  ui/         # HUD, menus
scripts/     # Singletons and utility scripts
assets/
  models/     # GLTF files for props
  textures/   # Albedo, normal, roughness maps
  shaders/    # Blight/Bloom, water, particles
  audio/      # SFX and music
```

## Running and Testing

**CRITICAL: Always verify the game launches before considering any work complete.**

### Launch the Game
```bash
flatpak run org.godotengine.Godot --path /home/kivlor/Code/pollen-ranger res://scenes/test_movement.tscn
```

This runs the game directly (not the editor). The main test scene is `test_movement.tscn`.

### Before Marking Work Done
1. **Run the game** using the command above
2. **Check the terminal output** for errors:
   - `SCRIPT ERROR` - Script has syntax or type errors
   - `ERROR: Failed to load script` - Script couldn't compile
   - `ERROR: referenced non-existent resource` - Missing file reference
3. **Verify the game window opens** and is playable
4. **Test the changed functionality** in-game

### Common Issues
- `Could not find type "X"` - Class not found, use `preload()` or remove type hint
- `Member "X" redefined` - Trying to @export a property that already exists in parent class
- `Can't create sub resource of type 'X'` - Invalid resource type (e.g., ConeMesh doesn't exist in Godot 4, use CylinderMesh or PrismMesh)
- Missing icon.svg - Create a simple SVG in `assets/textures/icon.svg`

### Opening the Editor (for scene editing)
```bash
flatpak run org.godotengine.Godot --path /home/kivlor/Code/pollen-ranger
```

## What Agents Should Do

- ✅ Implement mechanics that match the MDK + Metroid Prime feel
- ✅ Add comments explaining intent and "feel" goals
- ✅ **Run the game and verify it launches before marking work done**
- ✅ Test in the provided test scenes
- ✅ Keep performance in mind (target 60+ FPS)
- ❌ Don't add realistic physics (we want game-feel, not simulation)
- ❌ Don't make things too dark or grim — this is a garden, not a horror game
- ❌ Don't mark work complete if there are script errors or the game won't launch

## References

- **MDK (1997)**: For the dandelion sniper and glider feel
- **Metroid Prime**: For first-person platforming and scan visor
- **Kena: Bridge of Spirits**: For the "cleansing corruption" visual style
