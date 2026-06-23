# Custom Weapon Import Guide

This folder dynamically loads weapon assets at game startup. You can import models from your Tarkov collection or other sources directly.

## How to Import Weapons

1. Download a weapon model in **GLB** or **gITF** format from your Sketchfab collection:
   [Sketchfab Tarkov Collection](https://sketchfab.com/SingularPlural/collections/tarkov-ac21ff7fce7e4da6af46e7726dcdc9cf)
2. Place the `.glb` or `.gltf` file directly into this folder:
   `res://assets/weapons/`
3. Launch the game! The model will be automatically registered, scaled, and added to your weapon cycle (selectable via Keys `1`, `2`, `3`, etc. or Mouse Scroll).

## Stat Configurations based on Keywords

The dynamic importer assigns stats automatically based on keywords found in the model's filename (case-insensitive):

*   **Shotgun** (e.g. `remington_shotgun.glb`):
    *   Fires 8 pellets with spread
    *   Slow, pump-action (0.9s fire rate)
    *   6-round magazine capacity
*   **Sniper** or **Snipe** (e.g. `m700_sniper.glb`):
    *   Extremely high damage (95)
    *   Ultra-precise (0.001 spread)
    *   Slow fire rate (1.3s)
*   **Default (Rifle / Pistol)**:
    *   Medium damage (26)
    *   Fully automatic (0.12s fire rate)
    *   30-round magazine capacity

## Advanced Muzzle Placement (Optional)

If the muzzle flash is not aligned with the barrel of your custom model, you can build a scene template:
1. Create a scene in Godot inheriting from `Node3D`.
2. Name it your weapon's name, attach the `res://scripts/weapon.gd` script, and configure its parameters in the Inspector.
3. Drop your model inside the scene.
4. Add a child `Node3D` named `MuzzlePoint` and place it exactly at the tip of the weapon's barrel.
5. Save the scene as a `.tscn` file inside this folder (`res://assets/weapons/`). The importer will load the custom scene with your precise muzzle placement instead of guessing it!
