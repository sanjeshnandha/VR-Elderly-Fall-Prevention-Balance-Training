# VR Fall-Prevention Training Simulator

A Godot 4 / OpenXR training application for **elderly users**: hazard recognition, safe-movement
habits indoors and out, and a light balance exercise modelled on physiotherapy reach testing. Every session writes
a JSON record to `user://session_log.json` so a caregiver or researcher can compare runs over time.

Each room and the balance exercise is scored separately, shown on a **performance board** on the
hallway wall, and the app **focuses the next session on whichever one is weakest** -- see
[Per-test scores and the adaptive focus](#per-test-scores-and-the-adaptive-focus).

Built accessibility-first. Where a design decision could go either way, it goes the way that is
safest and lowest-friction for a non-gamer in their seventies wearing a headset for the first time.

---

## Quick start

1. Open Godot **4.6 or newer** → *Import* → select this folder's `project.godot`.
   (`project.godot` declares feature `4.7`, and `main.tscn` uses 4.6+ scene syntax.)
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
[SessionDirector] Focus for this session: bathroom (lowest_average).
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
| `W A S D` | walk — follows the ground: up the stair treads, down the kerb, out of the front door |
| Mouse | look (`Esc` releases the cursor) |
| Left click | flag the hazard under the pointer |
| `Space` (hold) | grip — the hand reaches for the nearest rail or the balance ball |
| Right click (hold) | aim the teleport arc; release to travel |
| `Q` / `E` | lower / raise the simulated head height |
| `F9` | skip the spoken instructions — same as the `Skip talking` wall button (works in VR too) |
| `F10` | researcher: end the session now and show the results (works in VR too) |

A crosshair marks what the pointer will flag. Holding `Space` makes the hand **reach** for the
nearest rail or ball within `desktop_reach` (1.3 m on the `FlatDebugRig` node) and hold it there
until you let go or walk away. A desktop player cannot move a hand sideways the way someone in a
headset simply does, so without this you would have to step off the tread you are standing on to
touch the rail beside it. **WASD collides with the world**: walls, furniture and the
wheelie bin stop you, and anything shorter than 260 mm — a kerb, a stair tread, a threshold, a rug —
is stepped over. Hold `Shift` to walk through things anyway, which is what you want when setting a
scene up. WASD still ignores the stair gating, so use the teleport (right click) when testing
Fix 5.1.

### VR controls — the entire input map

| Input | Action |
|---|---|
| **Left trigger** | show the teleport arc; release to travel |
| **Right trigger** | flag the hazard you are pointing at |
| **Either grip** | take hold of a handrail or the balance orb |

Everything else is a physical button you walk up to and press, including `Skip talking`, which
stops the voice mid-sentence at any stage. The written instructions stay on the panel, so nothing
is lost; `Say that again` starts the voice up again from the top of the current stage.

That is all of it. A/B/X/Y, menu, thumbsticks and trackpads are **not declared in the action map**,
so the runtime never delivers them. Menus are physical buttons on the wall. See
[Architectural fix 5.4](#54--controller-input-simplification).

---

> **Running a participant through it?** `ROOM_GUIDE.md` is the companion to this
> file: what each room is testing, what there is to find in it, which object is
> the deliberate decoy, and what the participant is actually asked to do. This
> file is the engineering view; that one is the room-by-room view.

## What a session looks like

1. **Welcome.** You start at the west end of the hallway facing a panel and four large buttons:
   `START`, `Seated mode`, `Say that again` and `Skip talking`. The last one is live at every
   stage and cuts the narration short for anyone who has heard it before. The rig is turned to face them for you, because your
   physical facing in a headset is arbitrary. Instructions are shown *and* spoken. The
   **performance board** is on the wall to your left, and from your second session onwards it names
   **today's focus** -- the room (or the balance task) you scored lowest on recently. A soft yellow
   beacon stands at that room's doorway.
2. **Explore.** Four connected rooms. Point at anything that could cause a fall and pull the
   trigger. Correct finds glow green and are named aloud; safe objects are logged as false
   positives but not penalised. Walking into your focus room brings a short spoken hint about what
   you missed there last time -- where to look, never the answer.
3. **Stairs.** Free teleport is disabled on the flight. The next step only unlocks while you are
   holding the rail, one step at a time, going down as well as up.
4. **Balance.** Three reach-and-touch trials (forward, right, left), each preceded by a 3-second
   countdown that captures a postural baseline. Keep your feet still; a target you cannot reach
   simply times out.
5. **Debrief.** A world-space panel 1.75 m in front of you: your score out of 100, the same
   room-by-room scores as the board, rail use, balance, the change since your last session,
   specific tips, and which test will be the focus next time. Written to
   `user://session_log.json`. Then `GO AGAIN` for another run (the focus is recalculated to include
   the session you just did) or `FINISH` to quit.

---

## The house and the street

Six connected rooms plus the street outside, everything at **1 unit = 1 metre**. The house is a
12.5 × 12.5 m single-storey home: a 12 m hall with a living room and kitchen at one end, bathroom,
bedroom and the stairs off it, and the front door onto the street. Scale accuracy matters far more than
visual polish here — a doorway 20 % too wide makes the participant misjudge every distance, in a
training application whose entire point is spatial judgement.

```
        -Z (north)
  +-----------------+    +--------------+    +-------------------+
  |   LIVING ROOM   |    |   BATHROOM   |    |      BEDROOM      |
  |    3.8 x 4.7    |    |  3.0 x 3.0   |    |     4.0 x 3.6     |
  +--------+  +-----+    +-----+  +-----+    +------+  +---------+
           |  |                |  |                 |  |    doorways 0.9 x 2.03
  +--------+  +----------------+  +-----------------+  +---------------------+
  |                         HALLWAY   12.0 x 2.6                             |
  |  ^ start here (panel, board, buttons)                                    |
  +--------+  +-------------------+  +--------+  +------------------------+--+
           |  |                   |  |        |  |
  +--------+  +-----+      +------+  +--+  +--------+
  |    KITCHEN      |      | FRONT DOOR  |  | STAIRS |
  |    3.8 x 3.7    |      |  to the     |  |1.5 x5.2|
  +-----------------+      |  street     |  +--------+
                           +-------------+
        +Z (south)
```

| Room | Hazards | Decoy (safe) |
|---|---|---|
| Bathroom | wet tile floor (sheen + slip trigger), no grab bar where you step in | towel rail |
| Staircase | handrail missing on one side, poor lighting, one uneven tread (+25 mm) | — |
| Hallway | curled rug edge, extension cord across the walkway | hall table |
| Bedroom | dim bedside light, chair with no armrests, clutter on the bed-to-door path | wardrobe |
| Living room | sofa too low and deep to stand up from, low glass coffee table on the walking route, television lead across the floor, footstool left in the way | armchair with firm arms |
| Kitchen | everyday things stored too high, wobbly step stool, spill by the sink, cupboard door left open across the walkway | kettle |
| Street | step down at the front door, lifted paving slab, wet leaves, high kerb with no dropped edge, bin blocking the pavement, open drain with its grating leaning against the wall, A-board across the pavement, low limb of the street tree at head height | postbox, litter bin |

**27 hazards, 7 decoys.**

The two rooms added last are the two where the research says the falls actually happen. In the
**living room** it is getting out of a seat — a 0.40 m sofa with no arms has to be stood up from
with the legs alone — and catching a foot on something low and dark: a glass coffee table, a lead,
a footstool left where it was used. The armchair beside it is the decoy *and* the lesson: firm,
0.48 m, proper arms. In the **kitchen** the fall is caused by reaching rather than walking, so the
hazards are a high shelf holding everyday things, the wobbly stool that reach invites, a spill on
hard tile, and a low cupboard door standing open below the line of sight. The denominator is derived from the scene at runtime — drop a new
`Hazard` node into a room and the scoring adapts with no other edit.

Out of the front door (in the hallway's south wall, west of the stairs) is a garden path, a
pavement, a road with a marked crossing, and the far pavement with a postbox to walk to — about
15 m end to end. The outside is one 140 mm step below the house floor and the kerb is 130 mm, with
a dropped kerb at the crossing. See [The street walk](#the-street-walk).

Real domestic dimensions throughout: 2.4 m ceilings, 0.9 × 2.03 m doorways, 190 mm stair rise,
250 mm going, 900 mm handrail height. The staircase is deliberately the participant's own
staircase, dimensionally.

The stairwell is a **narrow shaft**, 1.5 m wide, with the 0.9 m flight down the middle of it — not
a flight standing in a wide room. That is what puts the handrail within reach of the middle of a
tread without leaning, makes the walls useful for balance, and matches the staircase the
participant actually has at home. The teleport discs sit 0.25 m west of the middle of the treads — on the rail side, where a person
actually walks up stairs — so the rail is about 0.35 m from your shoulder rather than 0.6 m across
the tread. The good rail is mounted on the west wall on brackets, over the tread edge, and extends
past both ends of the flight as a real one does; the east wall has the
brackets and no rail, which is `stairs_missing_rail`.

The top is a **half-landing**, 1.9 m deep, with a window ahead of you and a door off to one side —
not a ledge with a wall in your face. There are two standing positions on it: the top of the flight
(where the rail is still in reach, because going back down needs it) and the far end by the window.
Standing up there puts the eyes at about 3.2 m, above the 2.4 m hallway wall this room borrows for
its north side, so `NorthGable` fills that wall up to the top of the shaft — without it you look
straight over it at the underside of the roof.

---

## Core systems

| | System | Where |
|---|---|---|
| **A** | Hazard flagging | `scripts/world/hazard.gd`, `scripts/player/hazard_pointer.gd` |
| **B** | Handrail / grab-bar compliance | `scripts/world/handrail_zone.gd`, `grab_rail.gd`, `scripts/player/grab_controller.gd` |
| **C** | Balance mini-exercise | `scripts/balance/balance_exercise.gd`, `balance_orb.gd` |
| **D** | Comfort / locomotion | `scripts/player/teleporter.gd`, `comfort_vignette.gd`, `seated_mode.gd` |
| **E** | Debrief + scoring + JSON | `scripts/autoload/session_manager.gd`, `scripts/ui/debrief_panel.gd` |
| **F** | Per-test scores, board, focus | `scripts/autoload/session_manager.gd`, `scripts/ui/performance_board.gd`, `scripts/world/focus_beacon.gd`, `scripts/world/room_zone.gd` |
| **G** | Virtual body (legs you can see) | `scripts/player/virtual_body.gd` |
| **H** | The street walk and the crossing | `scripts/world/street_crossing.gd`, `scripts/world/street_car.gd` |

Scoring is weighted **50 % hazards / 30 % handrail / 20 % balance**, and re-normalised over whichever
components actually ran — a session that skipped the balance task is not scored as if it failed it.

### The street walk

Most outdoor falls in this age group are not really about the road surface: they are about the
approach. Stepping down an unfamiliar kerb, being pushed off the pavement by a wheelie bin, and
crossing without looking are what put people in front of cars and on the ground. So the street is
built around the walk, and `scripts/world/street_crossing.gd` scores every step into the road out
of 100:

| | | |
|---|---:|---|
| Used the crossing | 40 | stepped into the road at the markings rather than out between parked cars |
| Looked both ways | 40 | turned the head far enough each way, recently enough to count, **before** stepping off the kerb |
| Left enough time | 20 | the car was at least six seconds away, or already past |

The head-turn check is the interesting one: it watches the camera's yaw while the participant is
still on the pavement, and wants a glance more than 55° each way along the road within the last
eight seconds. Looking once and then dithering at the kerb for half a minute does not count — which
is exactly the real failure.

**It measures, it does not block.** The road is walkable and the participant can step out anywhere.
A tool that makes the mistake impossible cannot tell you whether they would have made it; what they
get instead is one spoken correction at the moment it matters ("A car is coming. Step back and wait
for it to pass.") and the number in their debrief.

**The car** (`street_car.gd`) is deliberately gentle: 3.5 m/s, an eleven-second gap between runs so
there are real gaps to find, and it eases to a stop well short of anyone already in the road, waits,
then moves off again. It never collides, never brakes hard, has no horn, and never moves the camera.
The warning is a head-locked spoken line, like every other warning in this project.

### The virtual body

Look down and you see a slim waist, two legs and your feet (`scripts/player/virtual_body.gd`, a
child of the `XRPlayer`). Without a body, judging where the floor is and whether there is room for
the next step is measurably harder — which is the wrong thing to make harder in an application
about looking at the ground. The shadow it casts on the floor is a second depth cue.

**There is nothing above the waist, on purpose.** A chest sits about 30 cm below the eyes, so in a
first-person view it fills the lower half of the screen and hides exactly what the participant
should be looking at. No torso, no shoulders, no arms: looking down gives you feet, legs and an
uninterrupted view of the ground. (`show_arms` exists, but with no chest the arms float, so turn it
on only if you add a torso back.)

It is driven entirely procedurally, per frame: the body stands on the floor found by a ray cast
straight down (so it is right on stair treads too), it faces where the head faces but lags behind
and only catches up past about 45° of twist, and the feet stay planted until one is more than
`step_length` from where it should be, at which point that foot swings forward. Standing still
means standing still — there is no idle animation and no head bob, because motion the participant
did not initiate is a simulator-sickness risk. Knees and elbows come from two-bone IK, so limbs
bend rather than stretch, and a teleport re-plants both feet instead of sprinting them across the
room.

There is no head or neck (it would clip through the camera's near plane) and no collision: the body
is a visual only. Waist size, limb thickness, stance width and step length are all exports on the
node. Seated mode keeps it standing, which is exactly the point of
[Fix 5.2](#52--seated-mode-camera-height-calibration). Uncheck `enabled` on the `VirtualBody` node
to run without it — worth doing if you ever want to compare with and without.

---

## Per-test scores and the adaptive focus

The overall score answers "how did the session go". It does not answer "what should this person
practise next", which is the question a training app actually has to answer. So every **test** —
each room, the road crossing, and the balance exercise — is also scored on its own, 0 to 100:

```
room     = 70 % hazards found in that room
         + 30 % rail use in that room          (renormalised when the room has no rail)
         - 10 per near miss on a hazard you had not yet recognised, capped at -20

street   = 60 % hazards found outdoors
         + 40 % the footpath route             (Core System I, as in any room)
         - the same near-miss penalty

road crossing
         = 65 % the signalled crossing runs    (Core System J, per run)
         + 35 % how the kerb was stepped off   (per entry into the road)
         renormalised when only one of the two happened, and reported as
         "not done this session" when neither did

balance  = mean steadiness of the reaches you COMPLETED
         x the fraction you completed
```

A room you never walked into scores 0, because you cannot spot a hazard you never looked at. A
timed-out reach is not averaged into steadiness — standing still would otherwise score 100 — it
lowers the completion fraction instead.

**The board.** A panel on the hallway wall beside the start shows one row per test: last time,
today (filling in live as you play), and the change, with a bar and an arrow. Today's focus row is
outlined. It is readable before you press START, so the first thing a returning participant sees is
their own progress.

**The focus.** After each session the app averages each test over that participant's last **3**
sessions and takes the lowest one. If it is below **90**, that test is the next session's focus:

* the instruction panel and the spoken welcome name it,
* a pulsing yellow beacon stands at that room's doorway until you walk in,
* walking in brings hints built from what you actually missed there last time ("Look closely at the
  floor surface"), never the answer,
* the debrief tells you what the focus will be next time, and `GO AGAIN` starts that session
  immediately.

When every test averages 90 or above there is no focus and the participant explores freely. Nothing
is ever locked: the focus is a suggestion, and every room still counts towards the session score.

Hints live in `HINTS` in `session_manager.gd`, keyed by hazard id; the thresholds are
`FOCUS_THRESHOLD` and `FOCUS_WINDOW` in the same file.

---

## How the house is made to look real

Everything you see is generated. There is no downloaded asset pack, no imported
model, no photograph: the machine this was built on could not reach kenney.nl or
any other asset host, so the textures are baked from numpy and the geometry is
built from numbers. That turned out to be a better answer than an asset pack
anyway, because a texture generated at the size it represents tiles perfectly and
a prop built from its dimensions is always to scale.

### The texture baker

`tools/make_textures.py` writes 24 PBR texture sets into `assets/textures/` --
albedo, normal and roughness for each -- from nothing but noise functions:

    python3 tools/make_textures.py            # all of them, about three minutes
    python3 tools/make_textures.py oak_floor  # just one, while tweaking it

Oak floorboards with per-board colour variation and a groove at every joint;
porcelain and riven slate tiles with recessed grout; cut-pile carpet; a flat-weave
wool rug; skim plaster with an orange-peel roll; striped wallpaper; glazed subway
tile in a running bond; stock brick with struck mortar; sand-and-cement render;
concrete paving with aggregate and weathering; worn bitmac; mown grass; oak and
walnut with a cathedral figure; satin paint; woven upholstery; washed linen;
pebble-grain leather; speckled quartz; brushed stainless; interlocking roof tiles;
and the surface of still water.

Every map is seamless -- the noise lattice is periodic over the output -- which
matters more than resolution here, because the hallway floor texture is repeated
six times down its length. Contact sheets of all of them, tiled 2x2 so a join
would show, are in `assets/textures/_preview/`.

**The textures only appear once Godot has imported them.** Open the editor and
let the import finish before pressing F5, or the house comes up in the flat
colours it had before. Nothing breaks if you do not: `Surfaces` checks whether
each map exists and falls back to the colour, which is why a missing texture is a
missing texture rather than a room that will not open.

### Water

The bathroom's wet tile and the kitchen's spill were a flat rounded box 10 mm
thick, pale blue, 35% metallic, at 75% opacity. `Puddle`
(`scripts/world/puddle.gd`) replaces both with a film that has an irregular
outline, thins to nothing at the rim, carries the generated ripple normal map,
and sits at roughness 0.04 and metallic 0 so it reflects the ceiling light the
way water does rather than the way painted plastic does. A few droplets are
thrown clear of the main body, which is what stops a spill reading as one
deliberate shape.

**The pale blue tint stayed, and that was the right call.** The first version
was built the physically correct way -- a 3 mm film is nearly colourless and
makes tile *darker*, so it was tinted to darken, with a ring of damp floor round
it. It looked like a stain. Not like water, like something spilled a week ago
and never cleaned up. The old slab's cool tint was a stylisation, but it is the
stylisation that says "water" at a glance and from across the room, which is
what a hazard this cohort has to find and point at actually needs. The damp ring
is still in the node and still off by default (`damp_margin = 0`); it was tried
at 0.26 m and again at 0.10 m and read as a tidemark both times.

The lesson is worth keeping, because it was not a tuning mistake: the physically
accurate answer was the wrong answer for a training tool, and a render that
"looks right" when you reason about it can still look wrong when you put it on
the floor.

Two details that are not cosmetic:

- **The outline is a superellipse, not a circle.** The matching `SlipZone`'s
  scored footprint is a rectangle, and a round blob inside a square footprint
  would mean being penalised on a corner of floor that looks dry. The exponent
  2.4 fills about two thirds of the box, and the two footprints were then
  measured against the real outline and set to the largest rectangle of which
  95% is actually under water -- 1.33 x 1.01 m in the bathroom, 0.94 x 0.86 m in
  the kitchen.
- **The phases of the outline are arithmetic, not drawn from an RNG**, so the
  shape is identical in the engine and in the Python that measures it. That is
  the only reason the 95% figure above can be checked at all.

The ripple map took three attempts and each failure is instructive. Baked at the
normal strength that suits brick, it came out as a single flat lilac square --
a smooth height field has almost no gradient, and the mean deviation was lower
than plaster's. Baked from fbm at a strength that showed, it looked like wet
sandpaper. Water is not noise: it is a handful of smooth wave trains
interfering, so the final recipe is six sine trains at integer wave numbers
(which keeps the tile seamless) running through a low-frequency domain warp
(which stops the interference pattern reading as a diffraction grating).

### The material library

`scripts/util/surfaces.gd` holds one `StandardMaterial3D` per named surface,
built in code rather than as `.tres` files, and shared -- two hundred props
asking for `oak_wood` get one material and one texture upload. A prop or a room
names a surface as a string:

```gdscript
surface = "oak_wood"
floor_surface = "slate_floor"
```

The interesting part is the UV mapping: **world-space triplanar**, for everything
architectural. The house is built from dozens of separate boxes -- a wall is up to
five segments, each room has its own floor slab -- and with ordinary box UVs every
one of them restarts the pattern at its own corner, so the floorboards would jump
at each doorway and the grout would step at the bathroom threshold. World
triplanar takes the texture coordinate from the world position instead, so the
boards run the whole length of the hall and the tiles line up across a join, with
no UV authoring at all. Anything that moves has to opt out (`world_texture =
false`) or its texture stands still while the object slides through it.

### Filleted edges

A sharp arris is the clearest sign of a blockout: nothing in a real room has one.
`scripts/util/mesh_kit.gd` puts a genuine 18 mm fillet on every edge of every
prop, exactly -- the faces stay dead flat, so a table top is still a table top,
and the outer dimensions are unchanged to floating-point precision. It costs about
300 triangles a prop and does more for realism than any amount of texture.

Collision is untouched by it. The shape stays a plain box of the full size, so a
fillet cannot change where the teleport arc stops or what the hand can reach.

### Joinery

`RoomBuilder` now generates the lines where two surfaces meet, which is the one
thing every real room has and no blockout does: skirting with a moulded cap,
two-step coving at the ceiling, architrave and a lining around every doorway, an
oak threshold underfoot. All of it comes from the same numbers that made the
walls, so a room costs no extra lines in the `.tscn` to look finished. Every piece
is a `MeshInstance3D` with no collision body -- trim must not be able to stop a
teleport arc or catch a pointer ray.

The hallway owns every doorway in the house, so it sets
`architrave_both_sides = true` and trims both faces of each one.

### Real windows

`openings` could only cut a hole from the floor up, which is a doorway. Windows
now have their own array, standing on a sill:

```gdscript
window_openings = Array[Vector4]([Vector4(0, -0.2, 1.3, 0.95)])
window_sill_height = 1.075
```

Each one gets a lining, a projecting sill, glazing bars and an actual pane that
stops the teleport arc, and the wall below it stays solid so the skirting runs
straight past. There are five: over the kitchen counter, in the living room, on
the stair landing, obscured glass high over the bath, and one in the bedroom with
the curtains drawn.

Daylight arriving through a hole in a wall, at an angle, landing on the floor is
most of what makes an interior read as a place rather than a diagram -- and with
SDFGI on it lights the room for free.

### Lighting

`main.tscn` runs ACES tonemapping, SDFGI bounce light, SSAO and SSIL, screen-space
reflections, volumetric fog, and a physical sky that takes its sun position from
the directional light, so the sun disc, the horizon and the light through the
windows all agree. The sun has a real angular size (0.6 degrees, against the real
sun's 0.5), so shadows soften the further they get from whatever casts them
instead of staying razor sharp.

Every room light is now a visible fitting -- a pendant on a ceiling rose with the
lamp inside its shade -- rather than a floating point of light.

**If the house comes up too dark or too bright**, three numbers in that order:

| Where | What it does |
|---|---|
| `Env_house.tonemap_exposure` | overall brightness; 0.8 dimmer, 1.4 brighter |
| `SunThroughWindows.light_energy` | how much daylight comes in |
| `Env_house.sdfgi_energy` | how much light bounces around indoors |

### Two lights that are meant to be bad

The bedroom and the stairwell are lit at `light_energy = 0.4` and **must stay that
way**: inadequate lighting is the hazard in both rooms (`bedroom_dim_light`,
`stair_dim_light`). The realism pass worked around them rather than through them
-- the bedroom window has its curtains drawn and its ceiling pendant is modelled
unlit, which is both why the room is dim and what a real bedroom in that state
looks like.

The same logic applies to the wet patches, the wet leaves and the wheelie bin:
they are left as flat colour, because the participant has to be able to SEE a
hazard to flag it, so how visible it is is a training decision and not a look one.

### If it runs slowly

Everything in this section — SDFGI, SSIL, screen-space reflections, volumetric
fog and a shadow-casting light in every room — was chosen for a desktop with a
discrete GPU. On a fanless laptop with integrated graphics it is far too much,
and the honest summary is that the default was wrong for that machine rather
than that the machine is at fault.

`scripts/util/graphics_quality.gd` groups the expensive features into three
levels and picks one at startup from the video adapter: integrated graphics
(Apple, Intel, Radeon Graphics, Adreno, Mali) start on **Smooth**, everything
else on **Balanced**. Nothing starts on Ultra — a first run that stutters is
worse than one that looks slightly flatter.

**Press F8 while running** to cycle levels. It shows the level and the current
frame rate for a few seconds, which is the quickest way to find out what your
machine actually minds, and the choice is saved to `user://settings.cfg`.

| | Smooth | Balanced | Ultra |
|---|---|---|---|
| SDFGI (bounced light) | — | — | yes |
| Volumetric fog (light shafts) | — | — | yes |
| SSIL | — | — | yes |
| Point-light shadows | — | — | yes |
| Spotlight shadows (window shafts) | — | yes | yes |
| Screen-space reflections | — | yes | yes |
| Soft sun shadows (PCSS) | — | yes | yes |
| Sun shadows | 2 splits | 4 splits | 4 splits |
| Ambient occlusion | yes | yes | yes |
| 3D render scale | 75% + FSR | 85% + FSR | 100% |
| Anti-aliasing | FXAA | 2x MSAA | 4x MSAA |

What costs what, roughly in order:

- **SDFGI** is real-time bounced light and is the single most expensive thing
  here. Without it the rooms keep their sky ambient, so they read flatter rather
  than dark — the ambient is lifted slightly to compensate.
- **A point light's shadow is a cube**, so every shadow-casting `OmniLight3D` is
  six renders of the scene, every frame. Five of them was thirty extra passes
  before anything else was drawn.
- **Volumetric fog** is what makes the window shafts visible, and it is not cheap.
- **Render scale** matters more than it looks on a high-DPI display: a
  "1280x720" window on a Retina screen is really 2560x1440 pixels. FSR 1 is used
  rather than FSR 2 on purpose — FSR 2 looks better but is temporal, and temporal
  upscalers ghost behind moving objects, which is not something to inflict on an
  application about judging where things are.
- **Ambient occlusion stays on at every level.** It is comparatively cheap and
  does more than anything else to make an object look like it is standing on the
  floor rather than hovering above it.

Two other things worth knowing. `vsync` is now **on**: rendering flat out on a
fanless laptop just produces heat, and heat produces throttling, so uncapping the
frame rate can make it slower over time rather than faster. And the Godot editor
is itself using the GPU — closing it while the game runs gives a chunk back.

In VR the headset sets its own render scale, so the 3D scaling above is left
alone and only the effects change.

### Checking it without an engine

`tools/check_project.py` is the safety net for a project that is mostly built
without being able to open Godot:

    python3 tools/check_project.py                      # check everything
    python3 tools/check_project.py --json before.json    # snapshot the gameplay inventory

It parses every script, resolves every resource path, NodePath and `load_steps`
count, catches duplicate sibling names, validates every property name in every
scene and sub-resource against the scripts' own `@export` lists, sweeps each
room's wall geometry from its real numbers, and flags the two GDScript typing
traps that compile cleanly and only fail when the line is reached.

That last one matters more than it sounds. **Godot silently discards an assignment
in a `.tscn` whose property does not exist** -- no error, no warning, and the line
is deleted the next time the editor saves the scene. It is the one mistake a test
run would not catch either. It caught a real one during this pass: 35 decor nodes
in the kitchen pointed at an `ExtResource` id that scene had never declared, and
all of them would have loaded as bare `Node3D`s with every property dropped, in
silence.

The `--json` inventory is the other half. Dump it before a visual change, dump it
after, diff the two, and you have proof the work did not disturb anything that
matters. For this pass: **67 gameplay nodes across 14 categories, zero
differences** -- not one hazard, decoy, slip zone, room zone, teleport disc,
handrail, gated region, crossing, car, stair flight, balance node, wall button or
collision setting moved.

## Core System I -- crossing a room without touching anything

Recognising a hazard and getting past one are different skills, and the hazard
pointer only ever tested the first. A participant could point at the coffee
table, name it correctly, and walk their shin straight into it.

Five rooms now carry a **walking route**: a chain of rings on the floor
(`RouteMarker`) owned by a `RoomRoute`. The stretch between two rings is a
**leg**.

**One ring at a time, and none before the session starts.** A ring that is not
the next one is not drawn at all -- not dimmed, not there. The route arms when
the session starts in that room or when the participant walks into it
afterwards; the first ring appears in amber, standing on it turns it green for
`DONE_LINGER_S`, it disappears, and the next appears. Walking out of the room
part-way through hides the ring without losing the place, and it comes back lit
on return. The whole chain goes when the route finishes or the session ends.
A trail of five rings told the participant the answer before they had looked at
the room; one ring asks a question.

Two consequences worth knowing about:

- **A route must be able to start where the participant already is.** `room_changed`
  only fires on an actual change of room, and the participant presses START
  while standing in the hallway, which is already the current room. `RoomRoute`
  therefore also listens to `session_started`. Without that the hallway route
  never began -- the one bug of this kind that a play-test does find, because
  nothing happens at all.
- **A ring must be able to fire on an overlap that already exists.** `area_entered`
  is a crossing, and the participant may already be standing exactly where the
  ring appeared. `RouteMarker` checks its own overlaps one physics frame after
  it arms. That in turn makes overlapping trigger boxes dangerous -- standing on
  ring *N* would complete ring *N+1* for free -- so `tools/check_project.py`
  now refuses any two markers on a route whose boxes intersect.

**A leg is dirty if either half of the skill failed.** It is scored against both:

| | |
|---|---|
| you touched it | a `SlipZone` in the room fired during the leg -- you physically walked into the wet floor, the lead, the footstool |
| your route went through it | the straight line from the last ring to where you arrived passes through a hazard's footprint, which is what catches teleporting over the coffee table rather than round it |

Crossing a hazard counts even if you had already flagged it, which differs from
the near-miss rule on purpose: a near miss is about **recognition**, and walking
knowingly into something you identified is at least honest; this is about
**navigation**, and the lesson is that spotting the obstacle is not the same as
going round it. The log records which case it was, so the distinction survives
into the data.

### The legs are meant to be awkward

A route whose rings sit along a safe path tests nothing -- you would just walk
the line. So some legs are placed so the **direct line is blocked** and the task
is to see that and go round: the rug edge spans the hall, the cupboard door
stands open across the kitchen, the lead runs across the living room.

Every leg was checked to have a clear path before it was placed, with a
breadth-first search on a 5 cm grid over each room's real furniture and hazard
footprints. Of the 17 legs in the house, 8 require a detour and none is
impossible. That search is now `tools/check_routes.py`, which reads the real
scenes -- run it after moving any ring, hazard or piece of furniture:

```
python3 tools/check_routes.py
```

It reports each leg as *direct line clear* (tests nothing), *must go round X*
(what you want), or *NO CLEAR PATH* (a broken room). It found two of the
latter in the living room on its first run: ring 4 stood 150 mm from the
coffee table, close enough that a person of ordinary width could not stand
there at all, let alone get to the next ring.

**One room had to change to make this possible.** The living-room television lead
was 2.3 m long in a 3.8 m room and sealed the south half off entirely -- you
could not reach the sofa or the coffee table on foot at all. It is now 1.95 m,
leaving a 0.4 m gap at the west end. The hazard is unchanged in meaning: a lead
still runs across the floor from the television, and the room is now one you can
cross carefully rather than one you cannot cross.

### Warning volume versus scored footprint

A `SlipZone` has two sizes, and keeping them apart is the single most important
thing about it.

`extents` is the **warning** volume. It is drawn generously -- about half a metre
of approach -- because you want the spoken line a moment *before* the participant
is standing in the wet patch. **Nothing is scored against it.** A warning is a
warning, and being warned early is the point of it.

`route_extents` is the **scored** footprint: the actual object, plus
`contact_margin` (0.10 m, because the probe tracks the body centre and feet are
wider than that). Touching it is the near miss, it marks the walking leg dirty,
and `RoomRoute` judges a chosen route against it.

**They were the same volume until a play-test caught it**, and that was a real
unfairness rather than a cosmetic one. The warning volume around the living-room
coffee table is 1.7 x 1.2 m; the table is 1.1 x 0.6 m. Standing half a metre
clear of it -- behaving exactly as intended -- cost ten points and spoiled the
leg. For the trailing lead it was worse: the warning volume is twenty-five times
the area of the lead, so most of the room scored as having stepped on it. And it
was unlearnable, because no amount of care gets you round a room whose penalty
regions are wider than the gaps between the furniture.

`SlipZone` therefore does not score on `area_entered` at all. Entry starts
watching; a short `_physics_process` loop asks each frame whether the probe's
centre is inside the scored footprint, and only that transition records anything.
`tools/check_project.py` now refuses a zone whose scored footprint is missing,
or as wide as its warning volume, or sticking out past it.

### It never blocks

Unlike the staircase (Architectural Fix 5.1), nothing here is enforced. You can
ignore the rings, walk anywhere, and leave. Gating a living room would teach
compliance with a video game rather than confidence in a house. The staircase
itself has no `RoomRoute`: its gated teleport chain already is one, with stricter
rules.

### What it does to the score

| Test | Before | Now |
|---|---|---|
| Each room | 70 % hazards, 30 % rail | 50 % hazards, 20 % rail, **30 % route** |
| Street | 50 % hazards, 50 % crossing | unchanged here -- later split, see Core System J |
| Overall | 50/30/20 hazard/handrail/balance | unchanged |

A route registers itself as the room loads, so a room whose rings you ignore
scores zero for that 30 % rather than having it quietly redistributed -- without
that, skipping the task would be the easiest way to a good score. Anything a room
genuinely cannot test is still dropped and the rest renormalised.

The session log is schema 3: additive only, so older logs still load and still
feed the adaptive focus.

## Core System J -- the signalled crossing

The street used to be a strip of road 32 m long with **one** slow car on it and
a zebra crossing. It is now 52 m of two-lane carriageway, 7.0 m wide, with
**four** cars, two each way, and a **signalled crossing** with a push button, a
bleeper and a countdown.

### Why a signal and not a zebra

Judging a gap in traffic is the hardest part of crossing a road, and it is the
part that degrades first: it needs distance judgement, speed judgement and the
nerve to commit. A signalled crossing replaces all of that with a *sequence* --
press, wait, watch, cross -- which is learnable, repeatable, and identical at
every crossing in the country. That sequence is the thing worth practising, so
`TrafficSignal` owns it and `StreetCrossing` scores it.

The cycle **rests on green for the traffic** and only changes when somebody asks
for it. That is the whole reason the button is a lesson rather than scenery. A
participant who stands at the kerb and presses nothing is reminded, by voice,
every fourteen seconds -- which is better than cycling the lights on a timer,
because a crossing that changes by itself teaches that the button does not
matter.

| Phase | | |
|---|---|---|
| `TRAFFIC_GREEN` | rests here | a press waits out `minimum_green` (6 s) first: pressing does not stop the traffic instantly, and learning that is part of it |
| `TRAFFIC_AMBER` | 3 s | a car with room to stop stops; a car already committed clears the crossing |
| `ALL_RED` | 2 s | everything stopped before anyone is invited out |
| `WALK` | 10 s | steady green man, bleeper, seconds counting down on the post |
| `WALK_CLEARING` | 6 s | flashing green man: finish, do not start |

Ten and six rather than the usual timings because the road is 7 m and an
unhurried older walker is nearer 0.7 m/s than the 1.2 m/s most signal timings
assume.

### Three nodes, one timer

`TrafficSignal` is a controller with no visuals. `SignalPost` is a pole that
renders either a traffic head (red / amber / green, with hoods) or a pedestrian
head (red man / green man, with a countdown and optionally a button), and asks
the controller what to show. Splitting them is what lets a primary and a
secondary head display the same thing without two timers that can drift apart --
a bug that would be invisible in the editor and alarming in a headset.

The red man and the green man are **generated**, like everything else here:
`tools/make_textures.py` draws them as white-on-black masks, used as both the
albedo and the emission map so the black is the unlit housing and the figure is
what glows. A lamp that is off still shows its figure faintly, because a real
lens does.

The bleeper is an `AudioStreamPlayer3D` on the controller rather than a cue
through `AudioCues`, which is head-locked by design -- right for a spoken
warning, wrong for a crossing you are meant to locate by ear from the other end
of the street.

### What the cars do

Direction comes from `start_x` and `end_x`, so a car in the far lane is the same
node with those two swapped; it turns itself round and its headlights end up at
the right end. Driving on the left, so eastbound traffic uses the near lane and
westbound the far one, which `tools/check_project.py` now checks.

Each car yields to three things and takes whichever is nearest: a person in the
road ahead, the car ahead in its own lane, and a red light at its stop line. It
still never touches anybody and never brakes hard at them.

**Two bugs came out of simulating fifteen minutes of this street in Python**,
and neither would have been obvious from a short look in the engine:

- The car-following buffer counted the body length twice, which left an 80 cm
  window to stop in. At 2.5 m/s² that is not enough, and the cars drove into
  each other.
- A car coming back on at the end of the road appeared 1.9 m *inside* the car
  still crawling away from it -- and because the resulting gap was negative, the
  car-following test skipped it and drove straight through. Cars now hold
  off-screen until the lane entry is clear, and an overlapping car clamps the
  gap to zero rather than being ignored.

After both fixes: fifteen simulated minutes, eighteen button presses, no car
ever crossing a red line it was behind, and a minimum bumper-to-bumper gap of
exactly the 1.5 m standoff it was designed for.

### Street practice 1: walking the footpath

The street had no walking route at all, which meant the one room with real
obstacles lying on the ground was the one room where getting past them was not
measured. It has one now -- an ordinary `RoomRoute`, five rings, out of the gate
along the pavement and back to the crossing, ending where the button is.

Two things had to change for it to be worth anything:

- **The wet leaves were west of the front gate**, so the walk from the gate to
  the crossing never went near them. They have moved east onto that line, and
  been made shallower, because a 1.2 m footprint on a 2 m pavement leaves no
  lane to get round it in.
- **The wheelie bin had no footprint.** It had an aim volume to point at, but
  nothing that noticed you walking into it -- so the only obstacle actually
  standing on the pavement was the only one the route could not test. It has a
  `SlipZone` now.

All four legs need a detour: the leaves, the bin, the lifted slab, then the bin
again from the other side.

### Street practice 2: the crossing itself

`StreetCrossing` scores the *moment* of stepping off the kerb. That is a
different question from how the crossing then went, and the second question is
the one that catches what actually hurts an older pedestrian at a signalled
crossing: hesitating on the kerb until the green man has nearly gone, drifting
out of the marked lane, and still being in the road when the traffic gets its
green back.

`CrossingPractice` watches the whole run. It arms on the button press -- there
is no second control to find, because pressing to cross is already the first
thing to learn -- the rings appear when the green man does, and it ends at the
far pavement or when the lights change back.

**It works in both directions.** There is a button on the far pole too, and
pressing it re-arms the practice and runs it again -- which it always did, but
the rings did not. They are one list laid near kerb to far kerb, and taken in
that order they are right exactly once: having crossed, the participant pressed
the far button and the first ring lit up seven metres away on the side they had
just come from, with the rest walking them backwards across a road. The list is
walked forwards or backwards now, chosen by which end they are standing at when
the green man shows, with its own set of labels for the way back.

Both END rings stand on a **pavement**, which is why there are five of them
rather than four. The first ring used to be at z 10.1, already in the road, so a
return crossing finished with the participant standing in the carriageway being
congratulated. The chain is 8.7, 10.6, 12.8, 15.0, 16.9: footway, road, road,
road, footway. It is a **practice session in its
own right**, with its own score: see *What it does to the score* below.

| | |
|---|---|
| 50 | got across before the traffic's green returned (40 if finished on the flashing man, which is normal) |
| 25 | set off promptly after the green man appeared |
| 25 | kept between the two white edge lines |

The edge lines are new. A signalled crossing is marked by studs rather than by
the zebra's stripes, but two continuous lines read better in a headset and say
the same thing -- and "stay on the crossing" cannot cost points unless the
boundary is something you can see.

**Both of the first two terms are forfeit if the kerb was never left.** The
first weighting did not do that, and handed 25 points for "kept to the markings"
to somebody who pressed the button and stood still -- which is the one outcome
the practice exists to discourage. Checking the scoring arithmetic in Python
rather than reading it is what caught that.

### What it does to the score

An attempt at the crossing was 40 / 40 / 20. With a signal it is:

| | |
|---|---|
| 35 | waited for the steady green man |
| 25 | looked both ways before stepping off the kerb |
| 20 | used the marked crossing |
| 20 | left enough time -- no car close, or already past |

The signal term is the biggest one because the signal is now the instruction.
Looking both ways still carries a quarter of it, because a green man is not a
guarantee. Without a signal on the crossing the weights fall back to the
original 40 / 40 / 20, so the same node still scores a zebra sensibly.

The street's own weighting has changed, because there are two practices out
there now rather than one:

| Test | Before | Now |
|---|---|---|
| Street | 50 % hazards, 50 % crossing | 60 % hazards, **40 % footpath route** |
| **Road crossing** | — | its own test: 65 % runs, 35 % kerb entries |

The crossing is a **separate test**, not a share of the street room. The two
things being trained outdoors are different skills -- reading a set of lights is
not the same as watching the ground three steps ahead -- and keeping them apart
is what lets the board say which of the two is the weak one and lets the
adaptive focus send the participant back to just that one. It appears beside
`street` in `TEST_ORDER`, on the performance board, in the debrief and in
`tools/report_sessions.py`, under the name **Road crossing**.

Like the balance exercise, it reports "not done this session" rather than nought
when it was never attempted, because a participant who went out for a walk and
came home again has not failed a crossing -- they have not taken one. A run
carries the larger share because crossing the whole road on one green man is the
skill; stepping off the kerb correctly is the habit underneath it.

Crossing quality is the mean of both kinds of record. An entry record (stepping
off the kerb) and a run record (the crossing itself) are told apart by a `kind`
key, which the debrief needs: a run record has no `used_crossing` field, and
counting it as a missing one would report crossings away from the markings that
never happened. The result dictionaries gained `obeyed_signal`,
`pressed_button`, `signal_phase`, `completed`, `off_markings_s` and
`set_off_after`. The log schema is additive, so older sessions still load.

### Nothing had ever glowed

The hazard a participant is pointing at is supposed to glow amber on hover and
green once it is correctly flagged. That is the one piece of feedback that says
*that object, the one you are looking at* -- and it had never once appeared
anywhere in the project.

`Hazard.highlight_meshes` was set in zero scenes, and the fallback searched the
hazard's own *children*. But a hazard is an `Area3D` hovering over a prop that
is its **sibling** -- the lifted slab, the trailing lead, the wet patch, the bin
-- so the search always came back empty. Flagging still worked, the tone played,
the name was spoken and the label appeared, which is exactly why it went
unnoticed: everything except the glow was fine.

`_gather_meshes_in_volume()` now takes the sibling meshes that are at least
`INSIDE_FRACTION` (45 %) inside the aim volume by bounding box. The fraction is
doing real work: plain overlap lit the living-room rug for three different
hazards and the kitchen worktop for a spill on the floor. Three cases are named
by hand instead, because inference gets them wrong:

| | |
|---|---|
| Bathroom wet floor | the volume covers only the band of the patch that is *not* under the bath mat, so 43 % of the water is inside it -- just under the bar |
| Kitchen spill | its volume is a metre tall so it can be aimed at from standing, which otherwise lit the sink, two cupboard doors and the fruit bowl above the spill |
| Uneven stair tread | `staircase.gd` models each tread as a solid block from the floor up, so a band around the nosing held an eighth of that block; the volume now runs floor to tread top, which catches step 5 whole and still misses its neighbours 250 mm away |

The puddle and the staircase both build their meshes in `_ready()`, and sibling
`_ready()` order is not something a scene should have to guarantee, so a hazard
with nothing to light up **looks again on its first hover**, by which time the
room is fully built.

`tools/check_highlights.py` reports what each hazard will light up, modelling
the run-time geometry from the same exports its script reads, and fails on any
hazard that would light up nothing or that names a mesh which is not there.

The pointer's reach also had to change: outdoors the postbox decoy is 8.9 m
away and the beam was 6 m, so three street hazards could not be flagged at all.
`beam_length_outdoors` is 16 m while `SessionManager.current_room` is the street.

### Three things that were boxes

A drain, a drift of wet leaves and an overhanging branch were all boxes, and all
three read as what they were. The drain was three flat boxes -- a dark one for the recess, a
thinner one for the rim, and a third for the lifted cover lying 15 mm above the
paving with daylight under it. The leaves were one brown box, 1.5 x 0.75 m, 25 %
metallic.

**A hole has to be a real hole.** A dark box on top of an unbroken slab is a
stain, so the path is now laid in four pieces -- `FrontPath` up to the gully,
`FrontPathWest` and `FrontPathEast` either side of it, `FrontPathBeyond` on to
the gate -- and `scripts/world/drain_gully.gd` lines the gap that leaves with a
shaft, rims it with a cast iron frame 8 mm proud of the paving, and leans the
grating it lifted out against the garden wall. 0.47 m of clear paving each side
is the way past.

Everything that node builds is measured from the paving surface, which is where
the node sits, so local y = 0 is the ground and nothing can float by
construction. The grating is placed by its BOTTOM EDGE rather than its centre,
so changing how far it leans pivots it about the grass instead of sinking it
into the grass -- which is the mistake the version before it made, in reverse.
And it is a grating: a rim and seven bars with gaps twice their width, because
equal bars and gaps read as a solid dark rectangle from three metres away.

**A drift of leaves is a hundred leaves.** `scripts/world/leaf_litter.gd` builds
110 of them into one mesh -- each a flat polygon about its own midrib with the
edges curled up, in eight browns and ochres, randomly sized, turned and tilted,
piled deeper in the middle and thinning to singles at the edge, with a small
light mulch patch underneath so clean paving does not show through the middle.
Nothing about any one leaf matters; what makes it read is that no two are the
same. The sheen comes from one control, `wetness`, which takes the material from
pale and matt to dark and shiny.

**A branch is the lowest limb of something.** The low-branch hazard was a stick
and a green blob at head height with nothing above them, floating in the sky
over the pavement -- so the participant was not being asked to spot an
overhanging branch, they were being asked to work out what they were looking at.
`scripts/world/street_tree.gd` builds the tree it grew from: a tapered trunk out
of the lawn, five limbs, a crown of foliage, and one low limb that reaches out
over the wall to head height above the pavement. `low_limb_to` is the far end of
that limb, so moving it swings the branch rather than detaching it, and the
hazard lights up the limb and its leaves rather than the whole tree.

The ironwork gets a new `cast_iron` surface, and a correction with it: the drain
ironwork had been sharing `steel_dark` with the bathroom taps, at 85 % metallic,
so a gully grating rendered as a mirror lying on the path.

### Nothing may float

Two of those three were *reported by the participant* rather than caught here,
because nothing in `tools/check_project.py` had an opinion about what a prop was
resting on. `check_floating()` does now: two props are joined when their boxes
touch, a prop is grounded when its underside is on the lowest surface in the
scene, and anything not reachable from a grounded prop is floating. Mutual
support does not count -- a stick resting on a leaf cluster resting on the stick
is exactly the shape of the bug.

It runs on the outdoor scenes, where every surface is a prop; indoors the floor
and walls are built by `RoomBuilder` at run time, so half the props would look
unsupported for want of a wall. It found four shrubs hovering 150 mm over the
lawn on its first run.

### Walking through walls

The desktop rig added its movement straight on to the rig's position. No shape, no sweep, no
collision: WASD went through the bathroom wall, through the sofa, out of the house and across the
road. Nothing in this project had ever had to be *walkable* — only to look right.

`flat_debug_rig.gd` now sweeps a capsule. It is 0.44 m wide and stands from 260 mm to 1.70 m above
the feet, so what it hits is what a person's shins and shoulders would hit, and everything below it
is left to the ground-following to step up: the 130 mm kerb, a 190 mm stair tread, a threshold, a
rug. It slides along what it hits rather than stopping dead, in up to three passes so a corner
works, and it pushes itself out of anything it starts inside, so nothing can weld the rig in place.
`Shift` is a deliberate escape hatch back to the old behaviour.

A headset participant teleports, and the teleport arc already stops at the first thing it hits, so
it could never put anybody through a wall. What is left is room-scale walking, which no software can
prevent — the application does not own the participant's legs. It does what every headset does at
the edge of its guardian: `XRPlayer._check_head_inside()` tests a 120 mm sphere at the camera ten
times a second, and the comfort vignette closes while the head is inside geometry. It reopens when
they step back, it is logged, and it overrides the comfort-vignette preference, because that setting
turns off *comfort* and this is a boundary warning.

### Nothing may trap the participant

Solid walls raise a question that did not exist while you could walk through them: can you still get
everywhere? A doorway 100 mm too narrow, a room whose open side does not meet the hallway, or a
console table left across a door, and the participant is stuck somewhere with no way out — none of
which is visible in a screenshot.

`tools/check_doorways.py` composes the house the way `main.tscn` does, each room scene at its own
offset, and checks that every room has a way in, that every doorway clears the body in
`flat_debug_rig.gd` (0.90 m against 0.74 m needed), that each room's open side really does meet the
wall it is supposed to, and that nothing solid stands in a doorway. Props below the step height and
above head height are ignored, or every roof in the house would read as a blocked door.

    python3 tools/check_doorways.py

All five rooms are entered through the hallway's doorways. It is verified by narrowing a doorway to
0.6 m and by walling the bathroom in, both of which it catches.

### The route exercise was unwinnable

A participant who found every hazard in a room and walked round every one of
them scored **81**, and could not do better. The street scored 60.

A leg was judged clean by testing the **straight line between the two rings**
for hazard footprints -- not the path the participant actually took. And every
route in this project is laid out so that those straight lines are blocked:
`tools/check_routes.py` refuses a route whose legs do not need a detour, because
a leg you can walk straight down tests nothing. So the legs that required a
detour were marked dirty whether you took the detour or walked through the
coffee table, and going round scored exactly the same as going through -- on the
one exercise whose entire purpose is going round.

The rule now samples where the participant actually walked, every 120 ms, and
tests each consecutive pair of samples. Walking round is clean. Walking through
still fails, because the samples pass through the footprint. And teleporting
straight over a footstool still fails, which is what the rule was for in the
first place: the two samples either side make one long segment that crosses it.

| A perfect run, every hazard found and nothing touched | Before | Now |
|---|---|---|
| Hallway, living room, kitchen, bathroom | 81 | 100 |
| Bedroom | 75 | 100 |
| Street | 60 | 100 |

### The briefing talked about the street while you stood in the bathroom

Every instruction was in one block of text, `EXPLORING_BODY`: the rings, the
stairs, the front door, the pavement, the crossing sequence. It was read out
once at the start and then left on the panel for the rest of the session. It
never changed and it was never about where you were.

That block is now only what is true everywhere. Each room has its own two or
three sentences in `ROOM_GUIDES`, shown on the panel and spoken when the
participant walks in -- the first time only, because walking back through the
hallway four times should not mean hearing about the hallway four times. The
room the session starts in is introduced at the end of the opening, since
`room_changed` only fires on a change. "Say that again" repeats the brief plus
the guidance for wherever you are now.

The guidance never names a room's hazards. Naming them would answer the question
the room is asking. `check_room_guides()` fails the build if a scored room has
no entry.

### Geometry checks

`check_street()` in `tools/check_project.py` now refuses a street whose parts do
not agree: a pavement that does not meet its kerb, a zebra that does not reach
both kerbs or is a different width from the scored crossing, a car driving on
the centre line or on the wrong side for the direction it travels, a stop line
that is not short of the crossing it approaches, a signal post standing in the
road or in the front path, and two posts close enough for their heads to
overlap. The last two were real: the first draft had the pedestrian pole inside
the front path, and the far traffic head 0.7 m from the far pedestrian head.

### A car stopped with you inside the bonnet

Reported as the cars driving straight through somebody standing in the road.
They were stopping exactly as designed, which was the problem.

`_distance_to_person_ahead()` measured from `global_position` -- the middle of
the car -- and the ramp brought it to rest when that was 1.5 m away. On a 4.2 m
body the nose is 2.1 m further on, so the car halted with its nose 0.6 m PAST
the participant, who was standing inside the bodywork. From in there it looks
exactly like being driven through.

It measures from the nose now, and three things make the promise that no car
ever touches the participant actually hold:

| | |
|---|---|
| `person_buffer` 1.5 m | where the nose comes to rest, measured from the nose |
| `emergency_distance` 2.0 m | inside this the car stops dead. Easing down from 3.5 m/s takes 1.4 s and over two metres, which the participant spends inside the bonnet |
| `_person_alongside()` | anything inside the body plus a margin stops the car and keeps it stopped, for somebody who teleports beside a moving car or is already past the nose |

Verified by porting the speed control to Python and driving a car at somebody
standing in the lane: the old rule drove through them, the new one stops 1.5 m
short, and it still stops short when they step off the kerb with the car two
metres away.

Cars yield to the other pedestrians too, silently -- the spoken warning is for
the participant -- because a car driving through the person who crosses at the
lights would rather undo the point of having somebody cross at the lights.

### People, and more of the street

Four pedestrians: two on the far pavement, one west of the gate on the near one,
and one who waits at the kerb, crosses on the green man inside the markings, and
waits again before crossing back. Watching somebody else do it correctly is
worth more than another spoken instruction, and an empty crossing teaches
nothing about what people normally do at one.

None of them is solid. A moving obstacle that can corner somebody against a wall
is worse than an empty street, and the participant's own collision cannot push
anything out of the way -- so a pedestrian who finds the participant in front of
them stops and waits, which is what a person would do anyway.

Seven more houses: four along the far terrace and three set back behind them,
with lit windows that come on with night mode. They stop the street ending in a
flat line of four houses and a backdrop, which is the thing that reads as a
diagram rather than a place.

## Core System K -- night

Most falls at home happen on the way to the bathroom in the middle of the night:
half asleep, no slippers, no glasses, and whatever light there is. A simulator
that only ever runs at noon trains the easy half of the problem.

**Night mode** is one button on the north wall of the hallway, on its own,
available at any stage. It sits apart from the other buttons deliberately: it is
not part of the session flow the rest of them drive. It switches three things at once:

| | |
|---|---|
| the sun | becomes a moon -- a fortieth of the energy, cold instead of warm -- and the sky, the ambient light and the fog go with it |
| the room lights | come up. Every lamp is in the `room_light` group and keeps its OWN authored energy, multiplied by one gain |
| the daylight | goes off: window beams and sunbeams are in `daylight`. The street lamps, the porch light and the light over the crossing are in `street_light` and do the opposite |

That middle row is the point. The lamps are scaled, not set, so **the two lights
that are deliberately feeble stay deliberately feeble**: the bedroom light that
is too dim to see the floor by goes from 0.4 to 0.76 while the hallway goes from
2.0 to 3.8. In daylight those two hazards barely read, because in daylight they
are not hazards. After dark they are the most obvious things in the house.

Outdoors there were three lamps lighting three pools and leaving the rest of
fifty-two metres black, which is fine at noon and useless at midnight: every
outdoor hazard and both practices have to be findable after dark. There are
eight lamp posts now, plus a light over the crossing, a porch light over the
front step, a soft fill over the far pavement where the crossing practice ends,
another over the front garden where the open gully is, and one wide, weak
moonlight over the whole street. That last one is a light rather than a lift in
the ambient on purpose -- ambient is global, and raising it would lift the
inside of the house too and undo the dark bedroom.

The authored energies are read ONCE, at startup, before anything is changed, so
day is "put it back" rather than a second set of numbers to keep in step with
the first, and pressing the button fifty times leaves the house as it found it.
Nothing fades: a two-second transition means the participant presses the button,
sees nothing happen, and then finds a room that changed while they were looking
away.

`GraphicsQuality` also wants to own the ambient light -- it lifts it when there
is no bounced light to fill the corners -- so it hands its day value to
`DayNight` rather than writing the property itself. Otherwise whichever ran last
would win, and pressing the night button could come out fully lit.

`check_lighting()` fails the build on a light that is in none of the three
groups, or in more than one. Without it a new ceiling light would simply stay
blazing at midnight with nothing reporting it.

### Every wall button was mounted backwards

Reported as the labels being unclear, from a screenshot of the two new buttons
with their text written in mirror writing.

A `WallButton`'s front is its local +Z: that is where `wall_button.gd` puts the
labels, and a `Label3D` reads from its own +Z side. All nine buttons had that
axis pointing INTO their wall. What saved it from being obvious is the thing
that made it hard to see: a `Label3D` is double-sided by default, so the text was
still there -- mirrored, from behind, and half hidden by its own plate. It read
as poor labelling rather than as nine buttons facing the wrong way.

All nine are turned round, and `check_doorways.py` checks the facing: a button
whose front does not point into a room fails the build, verified by turning one
back round.

**The labels billboard now**, which is the part that actually settles this. A
flat `Label3D` on a wall has to be oriented by hand, and getting that wrong
failed twice in opposite directions: first the text was mirrored, then -- with
the buttons turned round and the labels made single-sided -- it vanished
altogether. A billboarded label cannot be wrong. It turns to the reader, from
any approach, at any angle, which is also simply better for somebody walking up
to a wall of controls who should not have to square up to each one to read it.

This is not a new idea in the project: `route_marker.gd` and `hazard.gd` build
their labels exactly this way, and those have never had an orientation problem.
The buttons were the odd ones out. They use a Y-axis billboard rather than a
full one, because wall signage should stay upright, and `no_depth_test` for the
same reason the hazard labels have it -- a billboard turned forty degrees sweeps
its far corner back through the plate it is mounted on, and the word disappears
into the wall.

And the labels are wrapped to the plate, which is the other half of "unclear".
They were laid out as one unbroken line at 58 mm of cap height, so "Press again
to erase" came out roughly 0.6 m wide on a 0.30 m plate, running off both sides
and over its neighbours. At 36 mm, centred, and wrapped to 92 % of the plate
width, every label in the house fits on one or two lines inside its own button.

### Why the screen was blinking

Reported as the screen blinking. It was the comfort vignette, closing on every
movement of the mouse.

It closed above a yaw rate of **45 deg/s**. The desktop rig turns the camera at
0.0022 radians per pixel, so ten pixels in one frame is 76 deg/s and a hundred
is 756: any mouse movement at all crossed it. Closing takes 0.23 s and reopening
0.56 s, so looking around a room was a continuous flicker of the edges.

Two changes. The turn rule now applies **only in a headset** -- on the desktop
rig the camera is turned by the mouse, which is not locomotion and has no
vestibular mismatch to suppress -- and the threshold is **180 deg/s**, which is
a quick glance over the shoulder rather than an ordinary look.

The underlying point is that the trigger was wrong in VR too. Simulator sickness
comes from the eyes and the inner ear disagreeing, which is what artificial
locomotion does and what turning your own head does not. This project moves the
participant by teleport only, and every teleport already blinks for 0.25 s. What
is left for the turn rule to guard is one real case: a whip of the head fast
enough to smear the picture.

The teleport blink and SlipZone's red peripheral flash are unchanged, and so is
the forced close when the head is inside a wall.

## Resetting the scores

A second button beside the night one, in dark red: **Reset scores**. It erases
this participant's saved sessions, which is everything the performance board
shows -- "last time", the change column, the averages -- and everything the
adaptive focus reads.

Three things about it are deliberate.

**It takes two presses.** The first arms it, changes the label to "Press again
to erase", says out loud what is about to happen, and disarms itself after six
seconds. A confirmation dialog would be the obvious alternative and is the wrong
one here: reading a modal through a headset, at this age, with the text scaled
up, is harder than touching a wall twice.

**It is participant-scoped.** Only `Settings.participant_id`'s sessions go. A
researcher's other participants are not the thing being reset, and there is no
undo to fall back on. The log is rewritten through the same atomic write a
finished session uses, rather than deleted, so a half-written file can never be
left behind.

**It does not touch the session in progress.** That has not been written yet,
and stopping it is the Finish button's job. Press Reset mid-session and the
board empties, the focus clears, and the run carries on being scored.

## Architectural fixes

These are the parts most likely to be looked at closely, so each one is documented at the top of the
file that implements it.

### 5.1 — The teleport loophole

**Problem.** Free-aim teleport lets you stand at the top of the stairs, point at the hallway floor
below, and arrive without touching a tread. The handrail zone never fires and the log records a
clean run — the failure is invisible.

**Fix.** Three cooperating pieces in `scripts/world/`:

- `gated_region.gd` wraps the **flight and the landing**. Inside it, free-aim destinations are
  refused.
- `gated_teleport_point.gd` is the only legal destination there — one per group of treads, plus an
  entry point at the foot of the stairs which sits just *outside* the region, so the participant
  can always teleport back into the hallway rather than being trapped.
- A point is active **only while the rail is actually held**, and only when it is the point
  directly above or below the one you are standing on — worked out from where you are, not from
  where you last teleported, so walking up a step works the same as teleporting onto it. The flight
  is therefore taken one step at a time **going down as well as up**. Descending is the more dangerous direction in real life, so the
  entry point at the foot needs the rail too whenever you are coming down it
  (`rail_required_only_when_gated`).

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

**Comfort** (`scripts/player/comfort_vignette.gd`). The vignette quad is 0.20 x 0.18 m at 6 cm from
the eye, which is really an *angle*: its edge sits just past the edge of a typical headset's field
of view, so the tunnel and the red near-miss flash are actually inside what the participant can
see. (Size it in metres without doing that sum and the effect lands at ~80°, outside the lens,
where it does nothing at all.)

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

Only **completed** reaches are averaged into steadiness. A participant who stands still until the
trial times out has near-zero head movement, so averaging timeouts in would score them 100 for not
taking part; the balance test score multiplies steadiness by the fraction completed instead. The
target is also checked against the room before it appears: if a wall or a wardrobe is in the way
the reach is shortened, and if there is no room at all the participant is asked to turn towards
open space, and after two tries that trial is recorded as skipped and counts neither way.

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
*across* runs. It is written to a temporary file and renamed into place, so an interrupted write
cannot destroy the history; an unreadable log is copied to `session_log.corrupt-<time>.json`
before a fresh one is started.

```json
{
  "schema_version": 2,
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
      "near_misses": [
        { "zone": "bathroom_wet_floor_slip", "room": "bathroom", "recognised": false, "t": 41.2 }
      ],
      "rooms": {
        "bathroom": { "hazards_found": 1, "hazards_total": 2, "missed": ["bathroom_wet_floor"],
                      "rail_crossings": 0, "rail_complied": 0, "near_misses": 1,
                      "near_misses_unrecognised": 1, "visited": true, "time_s": 96.4,
                      "score": 25.0 }
      },
      "street": {
        "crossings": 2, "used_crossing": 1, "looked_both_ways": 1, "safe_gap": 2,
        "quality_pct": 70.0,
        "detail": [ { "t": 212.4, "used_crossing": true, "looked_both_ways": false,
                      "safe_gap": true, "gap_seconds": 12.4, "entry_x": 0.3, "score": 60.0 } ]
      },
      "tests": { "hallway": 100.0, "bathroom": 25.0, "staircase": 63.3,
                 "bedroom": 66.7, "street": 62.5, "balance": 55.0 },
      "focus": { "test": "bathroom", "reason": "lowest_average" },
      "next_focus": { "test": "bathroom", "name": "Bathroom", "reason": "lowest_average",
                      "average": 30.0, "hints": ["Look closely at the floor surface."] },
      "score": { "hazard": 80.0, "handrail": 50.0, "balance": 55.0, "overall": 66.5 },
      "delta": { "has_previous": true, "hazard": 10.0, "handrail": null,
                 "balance": 3.1, "overall": 5.6, "tests": { "bathroom": 5.0 } },
      "tips": ["Bathroom: you missed the wet tile floor. ..."],
      "events": [ { "t": 0.0, "type": "session_started" } ]
    }
  ]
}
```

`events` is the chronological audit trail behind the aggregates — teleports, grabs, near misses,
room entries, handrail reminders, focus hints, calibration results. If a number in the summary
looks wrong, the answer is in there. `delta` entries are `null` for a component that did not run in
both sessions, so a skipped balance task never shows up as a huge gain.

Schema 1 logs (before per-room scoring) still load: both the game and the report tool derive the
per-room scores from the hazard detail of those older sessions.

### Analysing it

```bash
python3 tools/report_sessions.py "~/.local/share/godot/app_userdata/VR Fall-Prevention Trainer/session_log.json"
python3 tools/report_sessions.py path/to/session_log.json --participant P01 --csv out.csv
```

Prints a per-session table, the per-test scores the board shows, session-over-session deltas, the
recent average per test with the focus the app will pick next, and the hazards missed in every
session. `--csv out.csv` exports a tidy table (including the per-test columns) for R or pandas.

---

## Project layout

```
project.godot                   physics layers, desktop-fallback input map, OpenXR (off by default)
openxr_action_map.tres          the reduced VR input map (fix 5.4)
scenes/
  main.tscn                     the whole session: house, player, panels, buttons, board,
                                focus beacon + markers, director
  smoke_test.tscn               dependency-free diagnostic scene (F6)
  player/xr_player.tscn         XROrigin3D rig
  rooms/{hallway,living_room,kitchen,bathroom,bedroom,staircase}.tscn
  outdoor/street.tscn           garden, pavement, road, crossing, car, neighbours
  ui/{instruction,debrief}_panel.tscn, ui/performance_board.tscn
scripts/
  autoload/{settings,session_manager,audio_cues}.gd
  player/{xr_player,seated_mode,teleporter,hazard_pointer,grab_controller,
          comfort_vignette,virtual_body,flat_debug_rig}.gd
  world/{hazard,grab_rail,handrail_zone,gated_region,gated_teleport_point,
         slip_zone,room_builder,staircase,prop,room_zone,focus_beacon,
         street_crossing,street_car,room_route,route_marker}.gd
                                room_route + route_marker = Core System I
  balance/{balance_exercise,balance_orb}.gd
  ui/{viewport_panel_3d,debrief_panel,instruction_panel,performance_board,wall_button}.gd
  util/{auto_shape,surfaces,mesh_kit,graphics_quality,xr_tools_bridge}.gd
                                surfaces = the material library, mesh_kit = filleted boxes,
                                graphics_quality = the three rendering levels (F8)
  session_director.gd           the script of the session, end to end
assets/textures/                24 generated PBR texture sets + a manifest,
                                and _preview/ contact sheets of all of them
tools/make_textures.py          bakes those textures from numpy; no downloads
tools/check_project.py          static checks + the gameplay inventory (see above)
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
- Furniture is built from filleted primitives with generated PBR materials, not modelled or
  sculpted assets. It reads as a real room at a glance, but a close look at a chair or a tap
  shows the simplification. Correct scale and correct affordances were always the priority.
- One log file holds every participant, and everything the game compares (previous session, board,
  focus) is filtered by `participant_id`. Set it per run with `godot --path . -- --participant=P01`,
  or keep one `user://` directory per participant.
- The focus rule is deliberately simple — the lowest average of the last three sessions, below a
  fixed threshold of 90. It is a sensible default, not a validated adaptive-training algorithm, and
  it will chase a single bad session. Widen `FOCUS_WINDOW` if that matters for your study.
- Rail compliance is measured on the stairs only. The bathroom grab bar is deliberately in the
  wrong place (that is the hazard), so scoring its use would contradict the scenario; see the note
  in `bathroom.tscn` for how to add a bath-transfer measurement properly.
- Not validated with actual older adults. Every accessibility decision here is reasoned from the
  literature and from VR ergonomics, but reasoning is not evidence — pilot it before drawing
  conclusions from the scores.
