# Assets

Third-party art lives here, one folder per pack. Nothing in here is required to
run the project: every `ModelProp` falls back to its blockout box when the model
file is missing, so the house still opens, runs and scores correctly without any
of it.

## kenney_furniture

**Kenney Furniture Kit** — https://kenney.nl/assets/furniture-kit
Licence: **CC0 1.0 Universal** (public domain). No attribution required, though
it is credited here and in the report anyway, because it is good manners.

Install:

1. Download the kit from the link above (the "Download" button, no account
   needed).
2. Unzip it, and copy the **GLB** files (not the OBJ or FBX folders) into
   `assets/kenney_furniture/` so this folder contains `sofa.glb`,
   `kitchenSink.glb` and so on.
3. Open the project in Godot. It imports them on first open — this takes a
   minute and is normal.
4. Check what arrived, and at what scale:

   ```
   python3 tools/inspect_models.py assets/kenney_furniture
   ```

The scenes never rely on a model's own size: `ModelProp` measures each model and
fits it to the real-world `box_size` in the scene file, so a sofa stays 2.0 m
long whatever the pack thinks. Collision stays a simple box for the same reason
— the teleport arc, the pointer and the hazard volumes are all measured in
metres and must not change because a model has a different silhouette.
