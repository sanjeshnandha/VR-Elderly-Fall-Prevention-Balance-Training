# VR Fall-Prevention Training Simulator

A Godot 4 / OpenXR training application for **elderly users**: hazard recognition, safe-movement
habits, and a light balance exercise modelled on physiotherapy reach testing. Every session writes
a JSON record to `user://session_log.json` so a caregiver or researcher can compare runs over time.

Built accessibility-first. Where a design decision could go either way, it goes the way that is
safest and lowest-friction for a non-gamer in their seventies wearing a headset for the first time.

---

## Quick start

1. Open Godot **4.3 or newer** → *Import* → select this folder's `project.godot`.
2. Press **F5**. It runs on a plain desktop with keyboard and mouse — no headset needed.

No addons are required. See [Optional: godot-xr-tools](#optional-godot-xr-tools) below.

**OpenXR ships disabled** (`xr/openxr/enabled=false`). Desktop development is the default because
the engine tries to bring up an XR runtime *before the main scene loads*, and on a machine with no
runtime installed that can stall start-up with no error message. Turning it on is one tick box —
see [Building for a headset](#building-for-a-headset).

If it boots correctly, the **Output** panel prints:

```
[Settings] Autoloads booting on macOS, Godot 4.7...
[XRPlayer] Booting on macOS. Looking for an OpenXR runtime...
[XRPlayer] No OpenXR runtime. Desktop debug rig active (WASD + mouse).
[FlatDebugRig] Desktop controls active.
[SessionDirector] Scene loaded. 10 hazards registered across the house.
```

That is the health check. Each line rules out a layer: autoloads registered, the player rig
initialised, the scene tree built.

### If it still will not start

Open `scenes/smoke_test.tscn` and press **F6** (*Run Current Scene*). That scene depends on nothing
in this project — no autoloads, no custom classes, no XR, no shaders.

- **Spinning green box and white text appear** → the engine and your run settings are fine, so the
  fault is inside `main.tscn`. Check **Debugger → Errors** in the bottom panel.
- **Nothing at all** → the fault is in the editor's run configuration, not the project. Check
  *Editor Settings → Run → Window Placement → Game Embed Mode* is `Disabled`.

The smoke test also prints your Godot version, platform, renderer and `user://` path, which is what
you need to hand over when asking anyone else about a problem.

### Building for a headset

Requires **Windows or Linux** with SteamVR (or another OpenXR runtime) already running.

1. *Project Settings → XR → OpenXR → **Enabled*** (or set `openxr/enabled=true` in `project.godot`).
2. *Project Settings → **OpenXR → Action Map***. Confirm the four actions are listed — `default`,
   `aim`, `trigger_click`, `grip_click` — and press **Save**. This rewrites
   `openxr_action_map.tres` in your exact Godot version's format.

Step 2 matters. The binding format changed in Godot 4.4 (one `binding_path` per binding, replacing
the old `paths` array), so a checked-in action map can silently fail to load on a different version
— and a failed load takes the `default_action_map` project setting with it, leaving OpenXR enabled
with no bindings at all. Re-saving from the editor is the reliable move whenever you change Godot
version.

### On macOS

Two macOS-specific things, neither of them a bug in the project:

- **Godot has no working OpenXR runtime on macOS.** The VR path cannot be tested here at all — the
  rig detects this and falls back to the keyboard/mouse controls below. The architectural fixes that
  are specifically about headset behaviour (5.1 gated teleport, 5.2 seated calibration, 5.4 the
  reduced input map) need a Windows or Linux machine to verify properly.
- **Godot's embedded game window does not work on macOS.** If you see a window stuck on
  "Game starting…" with a small toolbar (`Input` / `2D` / `3D`) along the top, that window is the
  editor's *Game* panel waiting to embed something — it is not your game, and it will wait forever.
  Fix it once:

  **Editor Settings → Run → Window Placement → Game Embed Mode → `Disabled`**

  (The same toggle lives in the ⋮ menu at the right-hand end of that panel's toolbar, as
  *Embed Game on Next Play*.)

### Desktop controls (no headset)

| Input | Action |
|---|---|
| `W A S D` | walk |
| Mouse | look (`Esc` releases the cursor) |
| Left click | flag the hazard under the pointer |
| Right click (hold) | grip — also aims and fires the teleport arc |
| `Q` / `E` | lower / raise the simulated head height |

### VR controls — the entire input map

| Input | Action |
|---|---|
| **Left trigger** | show the teleport arc; release to travel |
| **Right trigger** | flag the hazard you are pointing at |
| **Either grip** | take hold of a handrail or the balance orb |

That is all of it. A/B/X/Y, menu, thumbsticks and trackpads are **not declared in the action map**,
so the runtime never delivers them. Menus are physical buttons on the wall. See
[Architectural fix 5.4](#54--controller-input-simplification).

---

## What a session looks like

1. **Welcome.** You start at the west end of the hallway facing a panel and three large buttons:
   `START`, `Seated mode`, `Say that again`. Instructions are shown *and* spoken.
2. **Explore.** Four connected rooms. Point at anything that could cause a fall and pull the
   trigger. Correct finds glow green and are named aloud; safe objects are logged as false
   positives but not penalised.
3. **Stairs.** Free teleport is disabled in the stairwell. The next step only unlocks while you are
   holding the rail.
4. **Balance.** Three reach-and-touch trials (forward, right, left), each preceded by a 3-second
   countdown that captures a postural baseline.
5. **Debrief.** A world-space panel 1.75 m in front of you: hazards found, rail compliance, balance
   score, change since your last session, and specific tips. Written to `user://session_log.json`.

---

## The house

Four connected rooms, everything at **1 unit = 1 metre**. Scale accuracy matters far more than
visual polish here — a doorway 20 % too wide makes the participant misjudge every distance, in a
training application whose entire point is spatial judgement.

```
        -Z (north)
     +----------------+        +--------------------+
     |   BATHROOM     |        |      BEDROOM       |
     |   3.0 x 3.0    |        |     4.0 x 3.6      |
     +------+  +------+        +--------+  +--------+
            |  |                        |  |            doorways 0.9 x 2.03 m
  +---------+  +------------------------+  +----------------+
  |                     HALLWAY  8.0 x 2.6                   |
  |  ^ start here                                            |
  +--------------------------+  +----------------------------+
                             |  |
                    +--------+  +--------+
                    |     STAIRCASE      |
                    |     2.6 x 5.2      |
                    +--------------------+
        +Z (south)
```

| Room | Hazards | Decoy (safe) |
|---|---|---|
| Bathroom | wet tile floor (sheen + slip trigger), no grab bar where you step in | towel rail |
| Staircase | handrail missing on one side, poor lighting, one uneven tread (+25 mm) | — |
| Hallway | curled rug edge, extension cord across the walkway | hall table |
| Bedroom | dim bedside light, chair with no armrests, clutter on the bed-to-door path | wardrobe |

**10 hazards, 3 decoys.** The denominator is derived from the scene at runtime — drop a new
`Hazard` node into a room and the scoring adapts with no other edit.

Real domestic dimensions throughout: 2.4 m ceilings, 0.9 × 2.03 m doorways, 190 mm stair rise,
250 mm going, 900 mm handrail height. The staircase is deliberately the participant's own
staircase, dimensionally.

---

## Core systems

| | System | Where |
|---|---|---|
| **A** | Hazard flagging | `scripts/world/hazard.gd`, `scripts/player/hazard_pointer.gd` |
| **B** | Handrail / grab-bar compliance | `scripts/world/handrail_zone.gd`, `grab_rail.gd`, `scripts/player/grab_controller.gd` |
| **C** | Balance mini-exercise | `scripts/balance/balance_exercise.gd`, `balance_orb.gd` |
| **D** | Comfort / locomotion | `scripts/player/teleporter.gd`, `comfort_vignette.gd`, `seated_mode.gd` |
| **E** | Debrief + scoring + JSON | `scripts/autoload/session_manager.gd`, `scripts/ui/debrief_panel.gd` |

Scoring is weighted **50 % hazards / 30 % handrail / 20 % balance**, and re-normalised over whichever
components actually ran — a session that skipped the balance task is not scored as if it failed it.

---

## Architectural fixes

These are the parts most likely to be looked at closely, so each one is documented at the top of the
file that implements it.

### 5.1 — The teleport loophole

**Problem.** Free-aim teleport lets you stand at the top of the stairs, point at the hallway floor
below, and arrive without touching a tread. The handrail zone never fires and the log records a
clean run — the failure is invisible.

**Fix.** Three cooperating pieces in `scripts/world/`:

- `gated_region.gd` wraps the stairwell. Inside it, free-aim destinations are refused.
- `gated_teleport_point.gd` is the only legal destination there — one per landing.
- A point is active **only while the rail is actually held**, and `requires_previous` chains them so
  the flight must be taken one landing at a time.

Plus one thing the brief did not ask for but the loophole needs: gating applies to the
**destination** as well as the origin (`GatedRegion.is_point_gated`). Otherwise a participant
standing in the ungated hallway could aim through the doorway and land halfway up.

Net effect: the habit is *enforced by the locomotion system*, not merely logged afterwards.

### 5.2 — Seated-mode camera height calibration

**Problem.** Sitting down drops the headset 0.4–0.6 m. The world does not move with it, so counters,
the bath rim and the stair rail end up at chin height. Reaching up and out is the exact shoulder
posture that causes impingement pain in older adults.

**Fix** (`scripts/player/seated_mode.gd`). Raise the `XROrigin3D` by
`standing_eye_height − measured_seated_head_height`. The virtual body keeps standing; only the real
person sits.

Calibration is **measured, not assumed**: a 3-second settle, then a second of samples, then the
**median** (one frame of tracking loss reports y = 0 and would drag a mean down by tens of
centimetres). Seated head height varies ~25 cm across a realistic cohort — wheelchair vs. dining
chair vs. high stool — so a hard-coded offset is not good enough.

If `XRToolsPlayerBody` is present, the same offset is pushed into its `player_calibrate_height` so
the addon's collision capsule stays aligned. Detection is by duck-typing, so there is no hard
dependency.

### 5.3 — Sensory accessibility

**Audio** (`scripts/autoload/audio_cues.gd`). Every instruction, confirmation, warning and debrief
line goes through a plain head-locked `AudioStreamPlayer`. Never `AudioStreamPlayer3D` — positional
audio fades when you look away from the hazard, which is *by definition* what happens when you miss
one. Combined with presbycusis the cue is simply gone. Ambience may still be positional; it is never
load-bearing.

Cue tones are **synthesised at startup**, so the project has zero binary audio dependencies. Spoken
lines use the OS text-to-speech engine at 0.85× rate (comprehension in older adults improves
markedly with a reduced speech rate). Everything spoken is also displayed.

**UI** (`scripts/ui/viewport_panel_3d.gd`, `debrief_panel.gd`). A world-space panel — a
dependency-free stand-in for `XRToolsViewport2Din3D` — at **1.75 m**, inside the 1.5–2.0 m band VR
lenses are ground for. Text nearer than that demands an accommodation a presbyopic eye cannot make.
The panel sits slightly *below* eye level: sustained upward gaze is uncomfortable and, for bifocal
wearers, the wrong part of the lens.

The colour contract:

- background dark grey `#1e1e22`, **not** black — pure black next to bright text halates through VR
  lenses and smears glyph edges
- text warm white and amber-yellow, **not** pure white — same reason, and yellow-on-dark survives the
  blue-light loss of an ageing crystalline lens
- body text 46 px in a 1600 px viewport on a 1.2 m quad at 1.75 m ≈ 1.2° cap height, comfortably
  above the ~0.8° floor where VR text breaks up
- **no colour is load-bearing on its own** — every green/amber state also carries a word or an arrow

### 5.4 — Controller input simplification

**Problem.** Ten inputs is overwhelming for a non-gamer, and an accidental face-button press can
interrupt a timed balance trial.

**Fix.** `openxr_action_map.tres` declares four actions total: two poses, `trigger_click`,
`grip_click`. Undeclared actions are never delivered by the runtime, so the face buttons are dead at
the OpenXR level rather than merely ignored in script. Each hand's trigger does exactly one thing,
and grip means "take hold of this" everywhere, with no modal contexts.

Menus are `WallButton` objects — 22 cm across, pressable by touch *or* by pointer, mounted at chest
height. There is no controller shortcut anywhere in the application, because a shortcut is hidden
state a first-time user has no way to discover and every way to trigger by accident.

Left-handers: set `left_handed = true` on the `XRPlayer` node. Both hands carry both tools and the
rig enables one of each, so the spoken instructions never change.

### 5.5 — Baseline calibration for the balance exercise

**Problem.** Scoring sway from the absolute `XRCamera3D` position is wrong in a way that silently
destroys the data. Start slouched, then straighten up, and you score a huge "sway" for doing exactly
the right thing. Start leaning and stay leaning, and you score perfectly. World coordinates also
encode *where in the room you are standing*, which is not a balance measurement at all.

**Fix** (`scripts/balance/balance_exercise.gd`). Each trial:

1. a 3-second spoken countdown — which also tells the participant when measurement starts, so they
   are never scored without knowing it;
2. on "Go!", capture `XRCamera3D.global_position` as the `Vector3` baseline;
3. score every frame as a **delta from that captured baseline**.

Sway is measured **horizontally only**. Vertical head movement is the reach itself — leaning down
toward a low target is correct technique, and penalising it would teach the wrong thing.

The orb is also placed relative to the baseline, so the reach distance is identical for a tall
standing participant and a short seated one.

Stability score: `100 × (1 − clamp((0.65·mean_sway + 0.35·max_sway) / 0.20 m, 0, 1))`. Mean is
weighted above peak because one momentary wobble matters less than being unsteady throughout.

---

## Two decisions the brief did not specify

**No fall animation.** The obvious way to make a slip land is to lurch the camera. Do not. Moving a
VR camera in a way the user did not initiate is the most reliable way to induce simulator sickness,
and this cohort is both more susceptible and less able to recover from a genuine startle while
wearing a headset. `SlipZone` is entirely non-vestibular: a head-locked warning, a peripheral red
vignette with no motion, and a `near_miss` entry in the log. The learning signal is informational,
not visceral.

**False positives are reported, not punished.** Flagging the towel rail costs nothing. Over-caution
is a desirable behaviour in this population; training it out would be actively harmful. The count
goes to the researcher, not into the score.

---

## Session data

`user://session_log.json` — on Windows,
`%APPDATA%\Godot\app_userdata\VR Fall-Prevention Trainer\`. The path is printed to the console at
session end, and `OS.get_user_data_dir()` will tell you at any time.

The file holds an **array of sessions**, oldest first, because the goal is measuring improvement
*across* runs:

```json
{
  "schema_version": 1,
  "participant_id": "P01",
  "sessions": [
    {
      "session_id": "20260806T101203-4417",
      "participant_id": "P01",
      "started_utc": "2026-08-06T10:12:03",
      "duration_seconds": 512.34,
      "settings": { "seated_mode": false, "comfort_vignette": true, "...": "..." },
      "hazards": {
        "total": 10, "found": 8, "accuracy_pct": 80.0, "false_positives": 2,
        "detail": [
          { "id": "bathroom_wet_floor", "name": "Wet tile floor", "room": "bathroom",
            "found": true, "time_to_flag_s": 14.22 }
        ]
      },
      "handrail": {
        "opportunities": 2, "complied": 1, "compliance_pct": 50.0,
        "detail": [
          { "id": "staircase_flight", "room": "staircase", "attempted": true,
            "complied": true, "grip_time_s": 9.4, "transit_time_s": 12.1 }
        ]
      },
      "balance": {
        "trials": 3, "mean_completion_s": 4.21, "mean_stability": 82.5, "max_sway_cm": 11.3,
        "detail": [
          { "index": 0, "yaw_offset_deg": 0.0, "completed": true, "completion_time_s": 3.9,
            "max_sway_cm": 9.1, "mean_sway_cm": 4.4, "stability_score": 86.2,
            "baseline": [1.02, 1.61, -0.44], "seated_mode": false }
        ]
      },
      "score": { "hazard": 80.0, "handrail": 50.0, "balance": 82.5, "overall": 71.5 },
      "delta": { "has_previous": true, "hazard": 10.0, "handrail": 0.0,
                 "balance": 3.1, "overall": 5.6 },
      "tips": ["Bathroom: you missed the wet tile floor. ..."],
      "events": [ { "t": 0.0, "type": "session_started" } ]
    }
  ]
}
```

`events` is the chronological audit trail behind the aggregates — teleports, grabs, near misses,
handrail reminders, calibration results. If a number in the summary looks wrong, the answer is in
there.

### Analysing it

```bash
python3 tools/report_sessions.py "~/.local/share/godot/app_userdata/VR Fall-Prevention Trainer/session_log.json"
```

Prints a per-session table and session-over-session deltas. `--csv out.csv` exports a tidy table for
R or pandas.

---

## Project layout

```
project.godot                   physics layers, desktop-fallback input map, OpenXR (off by default)
openxr_action_map.tres          the reduced VR input map (fix 5.4)
scenes/
  main.tscn                     the whole session: house, player, panels, buttons, director
  smoke_test.tscn               dependency-free diagnostic scene (F6)
  player/xr_player.tscn         XROrigin3D rig
  rooms/{bathroom,staircase,hallway,bedroom}.tscn
  ui/{instruction,debrief}_panel.tscn
scripts/
  autoload/{settings,session_manager,audio_cues}.gd
  player/{xr_player,seated_mode,teleporter,hazard_pointer,grab_controller,
          comfort_vignette,flat_debug_rig}.gd
  world/{hazard,grab_rail,handrail_zone,gated_region,gated_teleport_point,
         slip_zone,room_builder,staircase,prop}.gd
  balance/{balance_exercise,balance_orb}.gd
  ui/{viewport_panel_3d,debrief_panel,instruction_panel,wall_button}.gd
  util/{auto_shape,xr_tools_bridge}.gd
  session_director.gd           the script of the session, end to end
tools/report_sessions.py        cross-session analysis
```

### Physics layers

| # | Name | Used by |
|---|---|---|
| 1 | world | walls, floors, solid props — stops the teleport arc and the pointer beam |
| 2 | player | the player probe that world triggers detect |
| 3 | hazard | `Hazard` areas — the pointer's target layer |
| 4 | grabbable | `GrabRail`, `BalanceOrb` — the grip detector's only mask |
| 5 | teleport_target | `GatedTeleportPoint` |
| 6 | ui | `WallButton` |
| 7 | hand | the grab volume on each hand |

Keeping these separate is what lets grip never latch onto scenery and the pointer never snag on a
wall, without a single special case in the interaction code.

---

## Extending it

**Add a hazard.** Drop an `Area3D` into a room scene, attach `scripts/world/hazard.gd`, set
`hazard_id`, `hazard_name`, `room`, `extents` and an `explanation`. It registers itself; the
denominator updates. Add a matching line to `_advice_for()` in `session_manager.gd` for coaching
text. Set `is_hazard = false` to make it a decoy.

**Add a room.** New scene, a `RoomBuilder` node, set `size` / `height` / `openings`, instance it in
`main.tscn` at the right offset. Openings are `Vector4(wall_index, centre_offset, width, height)`
with wall 0 = +Z, 1 = −Z, 2 = +X, 3 = −X.

**Add a compliance zone.** A `GrabRail` plus a `HandrailZone` pointing at it via `rail_path`.

Every trigger volume builds its own collision box from an `extents` export, so a hazard is two
numbers rather than a hand-authored `CollisionShape3D` (`scripts/util/auto_shape.gd`). Supply a
`CollisionShape3D` child and it is respected instead.

---

## Optional: godot-xr-tools

The project ships working implementations of pointing, grabbing, teleporting and comfort so it opens
and runs in a clean Godot install — a marker should be able to clone, open and press Play. For a
final build, the addon's pickup, climbing and player-body code is more mature than anything worth
writing from scratch.

1. *AssetLib* → **Godot XR Tools** → install into `res://addons/`
2. *Project Settings* → *Plugins* → enable it
3. *AssetLib* → **Godot OpenXR Vendors** if you later target a standalone headset
4. The `XRToolsBridge` node already under `XRPlayer` in `main.tscn` wires it up

The bridge forwards `XRToolsPickable` grab/drop into the `GrabRail` interface (so compliance
measurement is unchanged), disables `XRToolsFunctionTeleport` inside a `GatedRegion` (so fix 5.1
still holds), and hands `XRToolsPlayerBody` to `SeatedMode` for fix 5.2. Every lookup is duck-typed,
so the file parses fine with or without the addon.

For headset-free iteration with more fidelity than the built-in flat rig, see
[`Cafezinhu/godot-vr-simulator`](https://github.com/Cafezinhu/godot-vr-simulator).

---

## Known limitations

- The balance measure is a **proxy**, not clinical-grade. A headset is not a force plate, it tracks
  the head rather than the centre of pressure, and there is no normative data behind the 0–100
  score. The debrief panel says so on screen.
- Haptics are not used. Add a `haptic` action via *Project Settings → OpenXR → Action Map* if you
  want them.
- Furniture is primitive blockout. Correct scale and correct affordances were the priority.
- Single participant per log file. For a study, set `Settings.participant_id` before the session and
  keep one `user://` directory per participant, or point `LOG_PATH` at a per-participant file.
- Not validated with actual older adults. Every accessibility decision here is reasoned from the
  literature and from VR ergonomics, but reasoning is not evidence — pilot it before drawing
  conclusions from the scores.
