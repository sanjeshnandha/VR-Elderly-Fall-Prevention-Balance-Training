# Changelog

## 2026-10-14 (and again) — the button labels billboard now

Turning the nine buttons round fixed the mirrored text and replaced it with no text at all: with the
labels single-sided, the readable face ended up pointing into the wall instead of out of it.

Orienting a flat `Label3D` by hand has now failed twice in opposite directions, so it is not being
oriented by hand any more. **Both labels billboard**, which is how every label in this project that
has never had an orientation problem is built — `route_marker.gd` and `hazard.gd` both do exactly
this. A billboarded label turns to the reader from any approach and at any angle, which is also
simply better for somebody walking up to a wall of controls who should not have to square up to each
one.

A Y-axis billboard rather than a full one, because wall signage should stay upright. `no_depth_test`
is on, for the same reason the hazard labels have it: a billboard turned forty degrees to face
somebody standing off to one side sweeps its far corner back through its own plate, and the word
disappears into the wall. The cost is a label faintly visible through a wall from the next room,
which is much the smaller problem.

The buttons stay turned round — the plate should face the room whatever the labels do — and
`check_doorways.py` still fails the build on one that does not.

## 2026-10-14 — nine buttons facing the wall

Reported as the labels being unclear, with a screenshot of the two new buttons showing their text in
mirror writing.

A `WallButton`'s front is its local +Z — that is where `wall_button.gd` puts the labels, and a
`Label3D` reads from its own +Z side. Every one of the nine had that axis pointing into its wall.

What kept it from being obvious is exactly what made it hard to see: a `Label3D` is double-sided by
default, so the text was still there, mirrored, from behind, and half hidden by its own plate. It
looked like poor labelling rather than like a button mounted backwards, and it had been that way
since the first four were placed.

All nine are turned round: west wall front +X, east wall front -X, north wall front -Z.

### So it cannot come back quietly

- **Labels are single-sided now.** A button facing the wrong way shows nothing at all.
- **`check_doorways.py` checks the facing**: a button whose front does not point into a room fails
  the build. Verified by turning one back round, which it names.

### And the labels are now readable

The other half of "unclear". They were laid out as one unbroken line at 58 mm of cap height, so
"Press again to erase" came out about 0.6 m wide on a 0.30 m plate — off both sides and across its
neighbours. Now 36 mm, centred vertically and horizontally, wrapped to 92 % of the plate width, with
the sub-label at 27 mm hanging below where there is nothing to overlap. Every label in the house fits
on one or two lines inside its own button.

## 2026-10-14 — the screen was blinking

The comfort vignette, closing on every movement of the mouse.

It closed above a yaw rate of 45 deg/s. The desktop rig turns the camera at 0.0022 radians per
pixel, so ten pixels in one frame is 76 deg/s and a hundred is 756 — any mouse movement crossed it.
Closing takes 0.23 s and reopening 0.56 s, so looking around a room was a continuous flicker of the
edges, and it had been since the rig was written.

The turn rule now applies only while a headset is driving the camera, and the threshold is 180 deg/s
rather than 45.

It was the wrong trigger in VR as well, which is the more useful half of this. Simulator sickness
comes from the eyes and the inner ear disagreeing — which is what artificial locomotion does, and
what turning your own head does not. This project moves the participant by teleport only, and every
teleport already blinks for a quarter of a second. All the turn rule has left to guard is a whip of
the head fast enough to smear the picture, and 180 deg/s is a quick glance over the shoulder.

Unchanged: the teleport blink, SlipZone's red peripheral flash, and the forced close while the head
is inside a wall.

## 2026-10-14 (last) — a reset button

Beside the night button on the north wall of the hallway, in dark red: **Reset scores**. It erases
the saved history — "last time" on the board, the change column, the averages, and everything the
adaptive focus reads.

Three deliberate decisions.

**Two presses.** The first arms it, changes the label to "Press again to erase", says out loud what
is about to happen and how many sessions will go, and disarms itself after six seconds with a token
so a later press cannot be cancelled by an earlier press's timer. A confirmation dialog would be the
obvious alternative and is the wrong one: reading a modal through a headset, at this age, with the
text scaled up, is harder than touching a wall twice.

**Participant-scoped.** Only the current `participant_id`'s sessions are removed. A researcher's
other participants are not the thing being reset, and there is no undo here. Checked by porting it
to Python and running it over a two-participant log: resetting as P01 removes three and leaves P02's
two, pressing again removes nothing, and the schema version survives.

**It leaves the session in progress alone.** That has not been written to the log yet, and ending it
is the Finish button's job. Press Reset mid-session and the board empties while the run carries on
being scored.

The log is rewritten through the same atomic write a finished session uses rather than deleted, so a
half-written file cannot be left behind, and `_last_summary` and the history snapshot are both
recomputed so nothing on screen is left showing what was just erased.

Nine wall buttons now, and `check_button_spacing()` confirms none of them overlap.

## 2026-10-14 (later still) — crossing back

Asked after the crossing practice: what about the return journey?

Half of it already worked. There is a button on the far pole, pressing it emits the same demand, and
`CrossingPractice` re-arms from any stage but CROSSING — so the lights, the scoring, the "in the
road" test and the markings check were all direction-agnostic and all fine.

The **rings** were not. They are one list laid near kerb to far kerb, and taken in that order they
are right exactly once. Having crossed, the participant pressed the far button and the first ring lit
up seven metres away on the side they had just come from, with the rest walking them backwards across
a road. They were stranded, or they followed the rings the wrong way.

The list is walked forwards or backwards now, chosen at the moment the green man shows by which end
the participant is standing at, with its own set of labels for the way back.

### Both ends of the chain are on a pavement now

There were four rings, from z 10.1 — already in the carriageway — to 17.3. Outward that is fine. Coming
back, the last ring of the run was the one at 10.1, so the return crossing finished with the
participant standing in the road being congratulated.

Five rings now: 8.7, 10.6, 12.8, 15.0, 16.9 — footway, road, road, road, footway. The run ends where
it should whichever way it is walked. The first ring is the one you wait on, and it completes the
moment the rings appear, which is correct: it is a "you are here", and the points come from setting
off promptly, keeping to the markings and getting across in time, not from the ring count.

### And the two routes were standing on each other

`check_route_markers()` caught it immediately: the footpath walk's last ring, "back to the crossing"
at x 0, and the crossing practice's new "wait here" ring, also at x 0, were 0.05 m apart — standing on
one would have completed the other. The footpath ring has moved 1.9 m west, which is still the
crossing, and the two routes now meet without overlapping.

Verified by porting the direction choice to Python and starting from each kerb: outward gives
8.7 → 16.9, the return gives 16.9 → 8.7, and both finish on a footway.

## 2026-10-14 (later) — the cars drove through you, and the street got neighbours

### "When I stood in front of the cars, they passed through me"

They were stopping exactly as designed, which was the problem.

`_distance_to_person_ahead()` measured from `global_position` — the MIDDLE of the car — and the
speed ramp brought it to rest when that was 1.5 m from the participant. On a 4.2 m body the nose is
2.1 m further forward, so the car halted with its nose 0.6 m *past* them. They were standing inside
the bodywork, and from in there it looks exactly like being driven through.

It measures from the nose now. Three things together make the promise that no car ever touches the
participant actually hold: `person_buffer` (1.5 m, where the nose comes to rest), `emergency_distance`
(2.0 m, inside which the car stops dead — easing down from 3.5 m/s takes 1.4 seconds and over two
metres, every one of them spent inside the bonnet), and `_person_alongside()`, which stops the car
for anybody inside the bodywork plus a margin and keeps it stopped until they step clear. That last
one covers the case the first two cannot see: somebody who teleports beside a moving car, or who is
already past the nose when it arrives.

Verified by porting the speed control to Python and driving a car at somebody standing in the lane.
The old rule drove through them. The new one stops 1.50 m short, and still stops short when they step
off the kerb with the car two metres away.

Cars now yield to the other pedestrians as well, silently — the spoken warning is for the
participant.

### Four people on the street

Two walk the far pavement, one walks west of the gate on the near one, and one waits at the kerb,
crosses on the green man inside the markings, and waits again before crossing back. An empty crossing
teaches nothing about what people normally do at one, and watching somebody else do it correctly is
worth more than another spoken instruction.

Both directions of that crossing wait for a green man. With only the outward leg listed they would
have crossed properly, turned round on the far pavement and walked straight back across on a red —
which is worse than not modelling the behaviour at all, because the participant is being shown it.

None of them is solid, deliberately: a moving obstacle that can corner somebody against a wall is
worse than an empty street, and the participant's own collision cannot push anything out of the way.
A pedestrian who finds the participant in front of them stops and waits.

### Seven more houses

Four along the far terrace and three set back behind them, with lit windows that come on with night
mode — emissive panels rather than lights, because forty more omnis would cost a great deal and light
nothing anybody can reach.

### Also

- `check_floating()` caught three of those lit windows hanging in mid-air between the two rows of
  houses, where I had put them on the wrong z. It then turned out the check had a flaw of its own:
  `FLOATING_OK` removed the ground plane from the graph entirely, so a house standing on nothing but
  the ground read as unsupported. Those entries stay in the graph now and are simply never reported.
  Re-verified with a genuinely floating prop, which it still catches.
- `pedestrian.gd` nearly shipped the same broken-setter bug as `street_tree.gd` did: one shared
  setter for four properties of three different types, which can only assign one of them. The build
  properties have no setters.

## 2026-10-14 (night, second pass) — more light outside, and the button moved

Two things from a screenshot of the crossing at night: the street was still mostly black beyond the
lamp, and the night button was sitting on top of another one.

### The button was in the same place as ButtonAgain

It went on the east wall at z 0.15. `ButtonAgain` is at z 0. Two 0.30 m plates, 0.15 m apart — they
overlapped, and the only thing that reported it was a participant looking at it.

That wall carries Balance, Again and Finish at z -0.75, 0 and 0.75 and has no room for a fourth. The
night button is on the long north wall now, between the stair doorway and the corner, on its own —
which is where it belongs anyway, since it is not part of the session flow the other buttons drive.

`check_button_spacing()` fails the build when two button plates are closer than half their combined
width plus a finger. Verified by putting the night button back where it was, which it catches.

### Eight lamps instead of three

Three lamps lit three pools and left the rest of fifty-two metres black. Added five more posts —
two on the near pavement, three on the far one — each with a head and a light, standing on the
paving rather than hovering over it, and all clear of the route rings and the hazard footprints
(`check_routes.py` still finds all five legs need a detour).

Three fills on top of that: one over the far pavement, where the crossing practice ends and walking
to something you cannot see is not a practice; one over the front garden, where the open gully is;
and one wide, weak moonlight over the whole street.

The moonlight is a light rather than a lift in the ambient, deliberately. Ambient is global: raising
it would lift the inside of the house as well and undo the dark bedroom, which is the one thing
night mode exists to show. The moon itself went from a fortieth of the sun's energy to a twentieth,
which brightens outdoors much more than indoors because indoors is shadowed.

Fourteen street lights now, all in `street_light`, all off during the day.

## 2026-10-14 (later still) — night

One button on the east wall of the hallway, beside the balance button, available at any stage.

Most falls at home happen on the way to the bathroom in the middle of the night, so a simulator that
only ever runs at noon trains the easy half of the problem. `scripts/world/day_night.gd` switches
three things at once: the sun becomes a moon at a fortieth of its energy, cold instead of warm, with
the sky, the ambient light and the fog going with it; the lamps come up; and the window beams go off.

Lights are switched by group — `room_light`, `daylight`, `street_light` — and the lamps are
**scaled, not set**. That is the part that matters. Every lamp keeps its own authored energy times
one gain, so the hallway goes from 2.0 to 3.8 and the bedroom's deliberately feeble light goes from
0.4 to 0.76. The two hazards that are *lights* — the bedroom light you cannot see the floor by, and
the unlit stairwell — barely read in daylight, because in daylight they are not hazards. After dark
they are the most obvious things in the house.

Outdoors there was one street lamp lighting one pool of pavement and leaving forty metres of street
black. There are four now, plus a light over the crossing and a porch light over the front step —
the crossing practice is unusable in the dark otherwise.

Every authored energy is read once, at startup, before anything is changed, so day is "put it back"
rather than a second set of numbers to keep in step with the first. Nothing fades: a two-second
transition means pressing the button, seeing nothing happen, and then finding a room that changed
while you were looking away.

### Two scripts wanted the same property

`GraphicsQuality` lifts the ambient light when there is no bounced light to fill the corners, and
night mode drops it. Both listen to the same settings signal, so whichever ran last would have won:
pressing the night button could have come out fully lit, or changing the graphics level after dark
could have turned the sun back on. `GraphicsQuality` now hands its day value to `DayNight` and lets
it decide, rather than writing the property itself.

### Also

- `check_lighting()` fails the build on a light in none of the three lighting groups, or in more
  than one. Without it a new ceiling light would stay blazing at midnight with nothing anywhere
  reporting it. Verified with an ungrouped light, which it names.
- `night_mode` is saved with the other comfort settings and recorded in each session's summary, so a
  run in the dark can be told from a run at noon in the data.

## 2026-10-14 (later) — the walls were not walls

Reported plainly: "the physics is very weak, I am able to move through walls."

The desktop rig added its movement straight on to the rig's position — no shape, no sweep, no
collision of any kind. WASD went through the bathroom wall, through the sofa, out of the house and
across the road. It had been that way since the rig was written, and it was even documented in the
README as a caveat rather than treated as a bug. Nothing in this project had ever had to be
*walkable*; it only had to look right.

### The desktop rig walks into things now

`flat_debug_rig.gd` sweeps a capsule. 0.44 m wide, standing from 260 mm to 1.70 m above the feet, so
what it hits is what a person's shins and shoulders would hit — and everything below it is left to
the ground-following to step up: the 130 mm kerb, a 190 mm stair tread, a threshold strip, a rug.
Stairs still work, because standing on tread 4 puts the bottom of the capsule above the top of
tread 5.

It slides along what it hits rather than stopping dead, in up to three passes so that corners work,
and it pushes itself out of anything it starts inside, so a bad spawn or a step cannot weld the rig
in place. Holding `Shift` gives the old behaviour back, deliberately: a researcher setting a scene
up needs it, and if anything ever does trap somebody it is the way out.

Solid furniture does not break the scoring, which was the thing to check before doing any of this.
The hazards that are *scored* by being stepped on — the rug, the cord, the spill, the leaves, the
clutter, the drain — are all flat or non-colliding, so their SlipZones still fire. The tall ones
stop you instead, which is what would happen in a house.

### Room-scale walking, which cannot be stopped

Teleporting could never put anybody through a wall: the arc raycasts each step and stops at the
first thing it hits. Room-scale walking in a headset is the case that is left, and no software can
prevent it — the application does not own the participant's legs.

So it does what every headset does at the edge of its guardian. `XRPlayer._check_head_inside()`
tests a 120 mm sphere at the camera ten times a second and closes the comfort vignette while the
head is inside geometry. It reopens the moment they step back, and it is logged as
`head_in_geometry` with the room and the position.

That forced close now overrides the comfort-vignette *preference*. Turning that setting off turns
off comfort; this is a boundary warning, and it has to show either way.

### Nothing may trap the participant

Solid walls raise a question that did not exist while you could walk through them: can you still get
everywhere? `tools/check_doorways.py` composes the house the way `main.tscn` does — each room scene
at its own offset — and checks that every room has a way in, that every doorway clears the body
(0.90 m against the 0.74 m needed), that each room's open side really meets the wall it is supposed
to, and that nothing solid stands in a doorway.

All five rooms are entered through the hallway's doorways, and nothing blocks them. Verified by
narrowing a doorway to 0.6 m and by walling the bathroom in, both of which it catches. Props below
the step height and above head height are ignored — the first run reported every roof in the house
as a blocked doorway.

## 2026-10-14 — the route exercise could not be won, and the briefing never changed

Two things reported from a real session: a room scored 81 with every hazard found and nothing
stepped on, and the spoken guidance talked about the street while the participant stood in the
bathroom.

### 81 was the ceiling, not a near miss

A leg was judged clean by testing the **straight line between the two rings** for hazard footprints
— not the path the participant actually walked. And every route here is deliberately laid out so
that those straight lines are blocked: `check_routes.py` refuses a route whose legs do not need a
detour, because a leg you can walk straight down tests nothing.

So on exactly the legs the design requires a detour on, the detour was marked dirty. Going round
scored the same as walking through the coffee table — on the one exercise whose whole purpose is
going round.

The arithmetic lands exactly where the report did. Four legs, two needing a detour, every hazard
found: `(0.5 × 100 + 0.3 × 50) / 0.8` = **81.2**. The bedroom's three legs with two detours gave 75,
and the street, whose five legs all need a detour, gave 60 — a participant who did everything right
outdoors scored 60 and had no way to improve it.

`RoomRoute` now samples the participant's position every 120 ms during a leg and tests each
consecutive pair of samples against the hazard footprints. Walking round is clean. Walking through
still fails. And teleporting straight over a footstool still fails, which is what the straight-line
test was *for*: the two samples either side of it make one long segment that crosses it. Verified by
porting both rules to Python and running four journeys between the same two rings — walked through,
walked round, teleported over, teleported round — where the old rule called all four dirty.

A perfect run now scores 100 in every room, and 100 on the street.

### The briefing was one block of text for the whole house

`EXPLORING_BODY` carried everything: the rings, the stairs, the front door, the pavement and the
full crossing sequence. It was read out once at the start and left on the panel for the rest of the
session, so the bathroom was briefed about pedestrian signals and the panel said the same thing on
the kerb as it did upstairs.

That block is now only what is true everywhere. Each room has its own two or three sentences in
`ROOM_GUIDES`, shown and spoken when the participant walks in — the first time only, because walking
back through the hallway four times should not mean hearing about the hallway four times. The
starting room is introduced at the end of the opening, since `room_changed` only fires on a change.
"Say that again" now repeats the brief plus the guidance for wherever you are standing. Today's
focus hints go on top of the room's own guidance rather than replacing it.

The guidance deliberately never names a room's hazards: naming them would answer the question the
room is asking.

`check_room_guides()` fails the build when a scored room has no entry in that table, when the table
names a room that is not scored, or when an entry has no usable body text — verified by removing the
bathroom's entry, which it catches both ways.

## 2026-10-12 (later still) — the branch had no tree

Reported from a screenshot of a yellow-glowing bar hanging in the sky over the pavement: "what is
this? why is it flying?"

It was the low-branch hazard — a 1.9 m stick and a green blob at head height with **nothing above
them**. It had been that way since the branch was added, and it only became obvious now because the
glow fix earlier today means a hovered hazard lights up, so the thing was suddenly bright amber
against the sky.

A branch is the lowest limb of something. Without the something, the participant is not being asked
to spot an overhanging branch; they are being asked to work out what they are looking at.
`scripts/world/street_tree.gd` builds the tree: a tapered trunk out of the lawn in four lengths
(one cylinder reads as a drainpipe), five limbs into a crown of nine foliage blobs, and one low limb
that leaves the trunk, bends on the way out over the garden wall, and ends in three leaf clusters at
head height above the pavement.

The node stands at the base of the trunk, on the ground, so every part is measured up from there.
`low_limb_to` is the far END of the low limb rather than its centre, so moving it swings the branch
instead of detaching it from the trunk. The hazard lights up the limb and its leaves, not the whole
tree: lighting the tree would say "that tree", and what is being pointed out is the branch.

### Nothing may float

Two of the last three "that doesn't look right" reports — the drain cover hovering 15 mm over the
paving, and now this — were caught by the participant rather than by any check here, because nothing
in `check_project.py` had an opinion about what a prop was **resting on**.

`check_floating()` does now. Two props are joined when their boxes touch within 30 mm; a prop is
grounded when its underside is on the lowest surface in the scene; anything not reachable from a
grounded prop is floating. Mutual support does not count — a stick resting on a leaf cluster resting
on the stick is exactly the shape of the bug. It is verified by putting the branch back, which it
catches.

It runs on the outdoor scenes only: indoors the floor and walls are built by `RoomBuilder` at run
time, so half the props would look unsupported for want of a wall. `FLOATING_OK` names the handful
of street props whose support genuinely is not in that scene — the roofs and the door furniture,
which are fixed to a house whose walls are built inside the room scenes.

On its first run it found **four shrubs hovering 150 mm over the lawn**, beside the front path, which
nobody had noticed. They are planted now.

### Also

- `street_tree.gd`'s first draft had one shared setter for eleven exported properties, and that
  setter did not assign any of them. A Godot setter that does not assign its own property silently
  throws the scene's value away, so every export would have stayed at its default no matter what the
  scene file said. The shape properties have no setters now, and the `rebuild` button covers editing.

## 2026-10-12 (later) — the drain and the leaves were boxes

Reported from a screenshot of the front path: "the drainage is not stable", and the leaves want to
look real.

### The drain

Three flat boxes, and all three wrong. The lifted cover's underside was at -0.125 against a paving
top of -0.140, so it **hung 15 mm in the air** with daylight under it — which is what the screenshot
showed. The rim was *below* the paving, so no rim read at all. And the recess could never have read
as a hole, because the path was one solid slab and a dark box on a solid slab is a stain.

A hole has to be a real gap, so the path is laid in four pieces now — up to the gully, either side
of it, and on to the gate — and `scripts/world/drain_gully.gd` lines what is left with a shaft
420 mm deep, rims it with cast iron 8 mm proud of the paving, and leans the grating it lifted out
against the garden wall, which is where a crew actually puts it. 0.47 m of clear paving each side is
the way past.

Two rules keep it honest. The node sits ON the paving surface, so local y = 0 is the ground and
nothing it builds can float. And the grating is placed by its **bottom edge**, not its centre, so
leaning it further pivots it about the grass rather than sinking it into the grass — a part placed
by its centre floats the moment anything about its size changes, which is exactly how the old one
came to hover.

The grating is also a grating: a rim and seven bars with the gaps twice the bar width. Equal bars
and gaps read as a solid dark rectangle from three metres away, which is a large part of why the old
cover looked like a floor tile.

### The leaves

One brown box, 1.5 × 0.75 m, 25 % metallic. At that size a single colour has nothing for the eye to
catch, so it read as a stain painted on the paving — and a stain is not a hazard anybody recognises.

`scripts/world/leaf_litter.gd` builds 110 individual leaves into one mesh: each a flat polygon about
its own midrib with the edges curled up, in eight browns and ochres, randomly sized, turned and
tilted, piled deeper in the middle and thinning to singles at the edge. A small, light mulch patch
sits underneath so clean paving does not show through the thickest part — small and light
deliberately, because at full size in the drift's own browns it is just the brown box again with
leaves sprinkled on it. One control, `wetness`, takes the whole thing from pale and matt to dark and
shiny.

### Also

- New `cast_iron` surface, baked by `tools/make_textures.py`. The drain ironwork had been sharing
  `steel_dark` with the bathroom taps — bright and 85 % metallic — so a gully grating rendered as a
  mirror lying on the path.
- **The split path lost `walkable = true`.** It had been written after `color` on the original single
  slab, so three of the four new pieces came out as scenery rather than ground: the teleporter would
  have refused the whole front path. `check_routes.py` caught it as a ring standing in mid-air.
- **`check_routes.py` took the first `size = Vector2(...)` in the file** as the room's size, which
  worked for exactly as long as `RoomBuilder` was the only node with a property by that name. The
  leaf drift has one too, and the street promptly became a 1.5 × 0.8 m room with no ground in it. It
  now reads that property only from a `RoomBuilder` node.
- The drain's scored footprint was a metre square on a 1.4 m path, so there was no way to get past
  the gully without being marked for standing in it. It is now the opening plus a hand's width.
- `check_highlights.py` knows what `drain_gully.gd` and `leaf_litter.gd` build, so the hazards that
  name those meshes are checked like any other.

## 2026-10-12 — the crossing is its own practice, and the glow finally works

Four things were reported together: street hazards could not be flagged, there were too few of them
out there, the front path wanted a drain, and the crossing was supposed to be a separate practice
rather than a share of the street's score.

### No hazard in the project had ever glowed

A hazard is meant to light amber on hover and green when it is correctly flagged. That had never
happened anywhere, in any room, since the hazards were first built.

`highlight_meshes` was set in zero scenes, and the fallback searched the hazard's own **children** —
but every hazard is an `Area3D` hovering over a prop that is its **sibling**, so the search always
came back empty. Flagging still played the tone, spoke the name and showed the label, which is
exactly why nobody noticed: everything except the glow worked.

`Hazard._gather_meshes_in_volume()` now takes the sibling meshes whose bounding box is at least
45 % inside the aim volume. The fraction is load-bearing: plain overlap lit the living-room rug for
three separate hazards and the kitchen worktop for a spill on the floor. Three cases are named by
hand instead, because inference gets them wrong — the bathroom wet floor (only 43 % of the water is
inside a volume that deliberately stops at the bath mat), the kitchen spill (a metre-tall volume so
it can be aimed at from standing, which otherwise lit the sink and the fruit bowl above it), and the
uneven stair tread, whose volume now runs floor to tread top because `staircase.gd` models a tread
as a solid block from the floor up.

The puddle and the staircase both build their meshes in `_ready()` and sibling `_ready()` order is
not something a scene should have to guarantee, so a hazard with nothing to light up looks again on
its first hover.

`tools/check_highlights.py` reports what every hazard will light up — modelling the run-time puddle
and stair geometry from the same exports the scripts read — and fails on a hazard that would light
up nothing or that names a mesh which is not there. It now passes with nothing outstanding.

### The beam was too short outdoors

Three street hazards could not be flagged at all: the pointer reached 6 m and the postbox decoy is
8.9 m away across the road. `hazard_pointer.gd` reaches 16 m while the current room is the street.

### Three more street hazards, and two props that were only ever words

`HazardOpenDrain` is the requested drainage hole: a recess in the front path with the grate lifted
out and propped beside it. The path was widened 1.0 → 1.4 m so there is still a way round it.
`HazardABoard` is a shop sign stood across the pavement, and `HazardLowBranch` is a branch down at
head height — the one hazard out there you have to look up to find. `DecoyLitterBin` is a second
safe object, since the street now has enough real ones to need it.

`FrontStep` and `HighKerbSection` were scored and named but had never been modelled; they exist now,
along with `LawnEastOfPath`, which fills a genuine hole in the lawn between the path and the gate.

**27 real hazards and 7 decoys**, up from 24 and 6. The footpath route was re-laid to six rings and
all five legs need a detour.

### The crossing is a separate test

It was 35 % of the street room's score. It is now its own test, `street_crossing`, shown as **Road
crossing** beside Street on the performance board, in the debrief, in the adaptive focus rotation
and in `tools/report_sessions.py`.

| Test | Before | Now |
|---|---|---|
| Street | 40 % hazards, 25 % footpath route, 35 % crossing | 60 % hazards, 40 % footpath route |
| Road crossing | — | 65 % the crossing runs, 35 % how the kerb was stepped off |

Either share is dropped and the other renormalised when only one of the two happened, so pressing
the button and crossing properly is not marked down for never having stepped into the road anywhere
else. Like the balance exercise it reports "not done this session" rather than nought when it was
never attempted: a participant who went out for a walk and came home again has not failed a
crossing.

The arithmetic was checked by porting both formulas to Python and running the cases that actually
happen, rather than by reading them.

### Also

- `puddle.gd` set `StandardMaterial3D.specular`, which does not exist in Godot 4 — the engine log
  had been reporting it as a remapped Godot 3 parameter at every load. It is `metallic_specular`.
  Found by turning on file logging and reading `logs/godot.log` instead of guessing.
- The signal countdown `Label3D`s are single-sided now; they were drawing mirrored digits to anyone
  standing behind the post, which on a back-to-back pedestrian head is the person on the far kerb.
- The rewrite above left a call to `_gather_meshes_recursive()` in `hazard.gd` after the function it
  named had been replaced. A call to a method that is not there is a *parser* error, so the script
  did not load at all and every hazard in the house was dead -- and `gdparse` checks syntax only, so
  it reported the file as fine. `check_project.py` gained `check_private_calls()`, which reproduces
  it exactly: every underscore-prefixed call must be defined in the same file or be an engine
  virtual.

## 2026-10-11 (later still) — the road was under the grass

Reported as "where is the zebra crossing", with a screenshot of a lawn where the street should be.

The zebra was never missing. **The ground plane's surface was at y -0.200 and the carriageway's is
at -0.270**, so the flat box that backs the whole scene sat 70 mm *above* the road. The tarmac, all
seven zebra bars, the centre lines, the stop lines, the new crossing edge lines and the drain cover
were every one of them underneath the grass. The pavements and kerbs are higher, so they showed —
which is why it read as a lawn with a pavement round it rather than as anything obviously broken.

This is not new. The road has been at -0.270 and the ground plane at -0.200 since the street was
first built; nothing before this week had needed to look at the road surface. Every check written
so far has been about X and Z — where things are in plan — and none of them had an opinion about
height.

The ground plane is now at -0.340, under everything it backs. A `VergeFar` strip fills the 150 mm
step that leaves between the far pavement and the neighbour houses.

`check_street()` gained three height checks, and the first of them reproduces the bug exactly when
the old value is put back:

- nothing at ground level may have its surface at or under the ground plane;
- the kerb must be 100-150 mm (it is 130);
- a road marking must sit just proud of the road surface, not under it or floating above it.

A cross-section of the result is in `assets/textures/_preview/street_section.png`.

## 2026-10-11 (later) — two street practices

The street now has two practices in order, the way the rooms indoors do.

### Practice 1: walking the footpath

An ordinary `RoomRoute`, five rings, out of the gate along the pavement and back
to the crossing, finishing next to the button. The street was the one room with
real obstacles lying on the ground and no route to test getting past them.

Two things had to move for it to be worth anything. **The wet leaves were west of
the front gate**, so the walk from the gate to the crossing never went near them;
they are east of it now, on that line, and shallower, because a 1.2 m footprint
on a 2 m pavement leaves no lane to get round it in. And **the wheelie bin had no
footprint at all** — an aim volume to point at, but nothing that noticed you
walking into it, which made the only obstacle actually standing on the pavement
the only one a route could not test. It has a `SlipZone` now.

All four legs need a detour: the leaves, the bin, the lifted slab, then the bin
again from the other side.

### Practice 2: the crossing, started by the button

`scripts/world/crossing_practice.gd`. `StreetCrossing` scores the *moment* of
stepping off the kerb; this scores the run from kerb to kerb, which catches
different mistakes — hesitating until the green man has nearly gone, drifting out
of the marked lane, and still being in the road when the traffic gets its green
back.

It arms on `TrafficSignal.demand_registered`, so the button that was already the
first thing to learn is also the start control. Four rings appear across the
crossing when the green man does. Out of 100: **50 for getting across before the
traffic's green returned** (40 if finished on the flashing man, which is normal
and correct), **25 for setting off promptly**, **25 for keeping between the
lines**.

Two white edge lines have been added down each side of the crossing. A signalled
crossing is marked by studs rather than the zebra's stripes, but two continuous
lines read better in a headset and say the same thing — and "stay on the
crossing" cannot fairly cost points unless the boundary is visible.

**A weighting bug, caught by checking the arithmetic rather than reading it.**
The first version scored 30 / 30 / 40 and gave someone who pressed the button
and never moved a flat 30, because standing still technically never leaves the
markings. Promptness and markings are now both forfeit unless the kerb was
actually left, and the weights are 25 / 25 / 50. A run that never starts scores
zero; one that sets off promptly and stays on the lines but does not finish
scores 50.

### Scoring and the checkers

The street is now **40 % hazards / 25 % footpath route / 35 % crossing**, from
50 / 50. `room_score()` no longer excludes the street from the route term.

Crossing records carry a `kind`: `entry` for a step off the kerb, `run` for a
whole crossing. The debrief tips count entries only — a run record has no
`used_crossing` key, and counting it as a missing one would have reported
crossings away from the markings that never happened. `crossing_run_pct()` and
per-kind counts are in the summary.

`tools/check_routes.py` now groups rings by the route node that owns them rather
than by scene, or the street's two routes read as one and it invents a leg from
the end of the footpath walk straight across the road. It also understands a
scene with no `RoomBuilder`: outdoors the ground is the union of the surfaces
marked walkable — path, pavements, dropped kerbs, carriageway — instead of a
room box. Both street routes verify: four of four footpath legs need a detour,
and no ring stands on anything.

## 2026-10-11 — Core System J: a bigger street, four cars, and a signalled crossing

The street was a 32 m strip with one slow car and a zebra. It is now 52 m of two-lane carriageway,
7.0 m wide, with four cars and a crossing that works the way a real one does.

### The signal

`scripts/world/traffic_signal.gd` owns the cycle; `scripts/world/signal_post.gd` is a pole that
renders either a traffic head or a pedestrian head and asks the controller what to show. One timer,
several posts — a primary and a secondary head cannot drift apart, which is the bug that would be
invisible in the editor and alarming in a headset.

It **rests on green for the traffic** and changes only when somebody presses. A press waits out the
6 s minimum green first, then 3 s amber, 2 s all-red, 10 s of steady green man with a bleeper and a
countdown, then 6 s of flashing green man. Ten and six rather than the usual timings because the
road is 7 m and an unhurried older walker is nearer 0.7 m/s than the 1.2 m/s signal timings assume.

Somebody who stands at the kerb and presses nothing is reminded by voice every fourteen seconds.
That is deliberately not "cycle the lights anyway after a while": a crossing that changes by itself
teaches that the button does not matter.

The red man and the green man are generated with everything else — white-on-black masks from
`tools/make_textures.py`, used as both albedo and emission so the black is the housing and the
figure is what glows. The bleeper is an `AudioStreamPlayer3D` on the controller rather than an
`AudioCues` tone, because `AudioCues` is head-locked by design: right for a spoken warning, wrong
for a crossing you are meant to locate by ear.

### Four cars

Direction comes from `start_x`/`end_x`, so a far-lane car is the same node with those swapped; it
turns itself round and its lights end up at the right end. Driving on the left, which
`check_project.py` now verifies. Each car yields to a person in the road, the car ahead in its lane,
and a red light at its stop line, taking whichever is nearest. It still never touches anybody.

**Two bugs found by simulating fifteen minutes of the street in Python**, neither of which a short
look in the engine would have shown:

- The car-following buffer counted the body length twice, leaving an 80 cm window to stop in. At
  2.5 m/s² that is not enough, and the cars drove into each other.
- A car coming back on at the end of the road appeared 1.9 m *inside* the car still crawling away
  from it, and because the gap was then negative the car-following test ignored it entirely and
  drove through. Cars now hold off-screen until the lane entry is clear, and an overlapping car
  clamps the gap to zero rather than being skipped.

After the fixes: eighteen presses, no car ever crossing a red line it was behind, minimum
bumper-to-bumper gap exactly the designed 1.5 m, zero overlaps.

### Scoring

A crossing attempt was 40 used-the-crossing / 40 looked-both-ways / 20 gap. With a signal it is
**35 waited for the green man / 25 looked both ways / 20 used the crossing / 20 gap**. The signal is
the instruction now, so it carries the most; looking both ways still carries a quarter, because a
green man is not a guarantee. With no signal the weights fall back to the original three, so the
node still scores a zebra. `obeyed_signal`, `pressed_button` and `signal_phase` are new keys on the
result; the log schema is additive and older sessions still load.

### Geometry, and two placement bugs it caught

`check_street()` refuses a street whose parts disagree: a pavement that does not meet its kerb, a
zebra that does not reach both kerbs or differs in width from the scored crossing, a car on the
centre line or on the wrong side for its direction, a stop line that is not short of the crossing it
approaches, a signal post in the road or in the front path, and two posts whose heads overlap.

The last two were real, and came out of drawing the plan to scale and looking at it: the pedestrian
pole was standing **inside the front path** — a pole to walk into on the way out of your own gate —
and the far traffic head was 0.7 m from the far pedestrian head, close enough that the housings
intersected. Also fixed: the kerbs stop either side of the crossing, which left a 100 mm slot of
bare ground between pavement and carriageway exactly where you step off. There are dropped kerbs in
it now.

Plans of the result are in `assets/textures/_preview/street_plan.png` and
`street_crossing_plan.png`.

## 2026-10-05 — the water

The bathroom's wet tile and the kitchen's spill were the same thing: a flat rounded box 10 mm
thick, pale blue, 35% metallic, 75% opaque. Four wrong answers about water in one node. Water is a
dielectric, so metallic belongs at zero -- a 35% metallic dielectric is the look of painted
plastic. At three millimetres it has almost no colour of its own, so a blue tint reads as a
swimming pool rather than a spill. And a rectangle is the one shape a spill cannot make.

**New: `scripts/world/puddle.gd`.** A film with an irregular outline that thins to nothing at the
rim, roughness 0.04 and metallic 0 so it reflects the ceiling light the way water does, carrying a
generated ripple normal map, with a few droplets thrown clear of the main body.

**The pale blue tint stayed.** The first version was built the physically correct way: a 3 mm film
is nearly colourless and makes tile *darker*, so it was tinted to darken and given a ring of damp
floor around it. On a play-test it was called out immediately, and rightly -- it looked like a
stain, not like water. The old slab's cool tint was a stylisation but it is the one that says
"water" at a glance and from across the room, which is what a hazard this cohort has to find and
point at actually needs. The damp ring is still in the node, off by default; it was tried at 0.26 m
and again at 0.10 m and read as a tidemark both times. Worth recording as a lesson rather than a
tuning error: the physically accurate answer was the wrong answer for a training tool.

**New texture set: `water`.** It took three goes.

1. Baked at the normal strength that suits brick, it came out as one flat lilac square. A smooth
   height field has almost no gradient, and the mean deviation measured lower than plaster's --
   the flattest map in the library. This is the kind of thing that is invisible until you look at
   the PNG.
2. Baked from fbm at a strength that showed, it looked like wet sandpaper.
3. Water is not noise. It is a handful of smooth wave trains interfering. The final recipe is six
   sine trains at integer wave numbers, which keeps the tile seamless, run through a
   low-frequency domain warp, which stops the interference reading as a diffraction grating.

**The scored footprints shrank to match the water.** The outline is a superellipse (exponent 2.4)
so the blob fills most of its rectangle rather than rattling around inside it, and its phases are
derived arithmetically rather than from Godot's RNG — which is what makes the shape reproducible
outside the engine. The two `route_extents` were then set to the largest rectangle of which 95% is
genuinely under water: 1.7 x 1.3 -> 1.33 x 1.01 m in the bathroom, 1.2 x 1.1 -> 0.94 x 0.86 m in
the kitchen. Same principle as yesterday's near-miss fix: nothing is penalised on floor that looks
dry. Every leg in both rooms still needs the same detour it did before.

A preview render of the result is in `assets/textures/_preview/puddle_preview.png`.

## 2026-10-05 — standing near a hazard is not standing on one

Reported from a play-test: "I make sure the user doesn't step on any hazards, I even change the
angle to go round, but the system marks it as stepped on when the user stands near it."

That was right, and it was the worst bug in the build so far, because it made the task
unwinnable rather than merely wrong.

**One volume was doing two jobs.** A `SlipZone` has always had a generous `extents` -- the volume
that speaks "Mind your feet, there is a lead across the floor here" -- and a tight `route_extents`,
the real object, which `RoomRoute` judges a chosen route against. But the near miss itself fired on
`area_entered` of the **warning** volume. So the thing that was supposed to warn you early was also
the thing that took ten points off you and spoiled the walking leg.

The numbers: the living-room coffee table's warning volume is 1.7 x 1.2 m around a table 1.1 x
0.6 m, so standing half a metre clear of it was penalised. The trailing lead's was twenty-five
times the area of the lead. The kitchen's open cupboard door, seven times. No amount of care gets
you round a room whose penalty regions are wider than the gaps between the furniture.

**The fix is to score the object, not the space around it.** `SlipZone` no longer scores on
`area_entered`; entry only starts watching, and a short `_physics_process` loop checks whether the
probe's centre has crossed the scored footprint plus a new `contact_margin` (0.10 m, since the probe
tracks the body centre and feet are wider than that). The spoken warning stays on the wide volume
and now costs nothing at all.

Scored footprints, before and after: coffee table 2.04 -> 1.15 m2, footstool 1.21 -> 0.58,
trailing lead 2.61 -> 0.85, cupboard door 0.70 -> 0.30, bath mat 1.30 -> 0.92. The five area
hazards -- the two wet floors, the clutter, the paving, the leaves -- are hazards over their whole
area, so their footprints are unchanged and their *warning* volumes were widened instead, which
they never had.

`check_project.py` gained `check_slip_zones()`: a zone with no scored footprint, or one as wide as
its warning volume, or one sticking out past it, is now an error.

### Fixed: a ring standing on a shoe box

Bedroom ring 2 sat on top of `ClutterShoes`. `check_routes.py` had not caught it because it only
treats a prop as an obstacle above 150 mm -- correct for "can you walk here", wrong for "can you
stand here": a 100 mm box is something you step over, not something you stand on. The ring test now
rejects anything over 40 mm underfoot, and the bedroom route has been re-laid.

### Changed: the bedroom is a metre deeper

4.0 x 3.6 m -> 4.0 x 4.6 m. It grows north only: the +Z wall is the hallway's and cannot move, and
the north wall's length is unchanged so the window opening stays where it was. The bed, bedside
table, wardrobe and curtains move with the north wall; the radiator, chair, switch and pictures keep
their place in the world; the pendant re-centres. Nothing else in the house moves -- the nearest
neighbour, the living room, ends 4.2 m to the west.

The clutter moved 0.6 m further in, so there is now somewhere to stand inside the doorway, and the
route is re-laid for the new floor. The bedroom has one obstacle, so it gets one awkward leg
(it had two, but one of those came from the ring that was standing on the shoes). 8 of the 17 legs
in the house now require a detour.

## 2026-10-05 — aiming at a hazard, and a ring standing on the rug

Reported from a play-test, with a screenshot: a ring sat in the middle of the hall rug, and pointing
at the rug flagged nothing.

**The ring was on the rug.** Hallway ring 3 was labelled "before the rug" and placed at x = 1.60 --
the rug runs from 0.30 to 2.50, so it was a metre *onto* it. Ring 2 was on a corner of it too. Both
have moved onto bare floor: ring 2 to (-1.40, 0.45), ring 3 to (-0.20, 0.00) which is genuinely
before the rug, and ring 4 to (3.10, 0.45) which is past it. The leg between 3 and 4 still has to
go round the curled edge, which is the point of it.

**Pointing at the rug did nothing** because the rug's aim volume was only the far 0.8 m of a 2.2 m
rug -- the curled lip itself. Nobody aims at a lip; they aim at the rug. The volume now covers the
whole rug, and `Hazard` gained `label_offset` so the name still floats over the lifted edge rather
than over the middle. The hazard is still called "Curled rug edge" and still explains that the
lifted edge is what catches a toe.

**Five more of the same kind, found by a new check.** `tools/check_project.py` gained
`check_hazard_volumes()`, which refuses two hazards in a room whose aim volumes intersect: the ray
returns the nearest collider, so which one lights up would depend on where the participant happens
to stand, and one of them can become effectively unreachable. It found the bathroom stacking three
volumes on the same corner of floor (wet tile, bath mat, missing grab bar), the kitchen's spill
overlapping the open cupboard door by 100 mm, and the living room's television lead touching the
sofa. The bathroom three are now separated by what they actually are -- the mat low and tight to
the mat, the wet tile in the band beside it, and the missing grab bar raised to where a bar would
be fitted, above the tub rim.

### New: tools/check_routes.py

The breadth-first walkability search that was used once by hand when the routes were placed is now
a script in the repository that reads the real scenes. It reports each leg as *direct line clear*
(tests nothing), *must go round X* (what a leg should be) or *NO CLEAR PATH*.

Its first run found a broken room. **Living-room ring 4 stood 150 mm from the coffee table** -- a
person of ordinary width could not have stood there, and legs 3 and 4 had no clear path at all. It
has moved to (-0.60, -1.05), in the open floor south of the table. All five routes now pass: 9 of
the 17 legs require a detour (the README said 10; it was counting the leg that turned out to be
impossible).

## 2026-10-05 — one ring at a time, and the route that never started

Reported from a play-test: pressing START did nothing to the rings. They were all visible from the
moment the house loaded, all grey, and none of them ever lit.

**The route never started.** `RoomRoute` waited on `SessionManager.room_changed`, which only fires
when the current room actually *changes*. The participant presses START while standing in the
hallway — already the current room — so the signal never arrived and the hallway route sat dormant
for the whole session. `RoomRoute` now also listens to `session_started` and begins if the
participant is already standing in its room. This is worth noting as a class of bug: an
"on entering X" trigger is not the same as "when in X", and the difference only shows up for
whoever happens to start inside X.

**A ring can now fire on an overlap that already exists.** `Area3D.area_entered` is a crossing. If
the ring appears underneath someone who is already standing there, nothing is emitted and the route
waits forever. `RouteMarker` now checks `get_overlapping_areas()` one physics frame after it arms.

**That made overlapping trigger boxes unsafe**, because standing on ring *N* would then also
complete ring *N+1* — a leg scored clean without moving a foot. The kitchen had two such pairs
(markers 2–3 and 3–4, 0.75 m apart with 0.9 m boxes). Its five markers are now 0.7 m boxes, which
also matches the 0.68 m ring, so what you see is what the trigger is. `tools/check_project.py`
gained `check_route_markers()` and refuses any overlapping pair on a route from now on.

### Changed: one ring at a time

The rings are no longer all drawn at once in grey.

- Nothing is drawn until the route starts. During the hazard hunt the floor is empty.
- Then exactly **one** ring is visible: the next one, in **amber** — the colour the rest of the
  house already uses for "attend to this". Standing on it turns it **green** for 1.2 s, then it
  disappears and the next appears. A reached ring also plays the `confirm` cue.
- Only the room you are in shows its ring. Step out part-way through and the ring goes; the route
  keeps its place and comes back lit when you return.
- Finishing the route, or ending the session, clears the chain.

`RouteMarker` gained `set_shown()`, `dismiss()` and `reset()` for this; `RoomRoute` drives them.
Nothing about scoring, the leg rules or the hazard-crossing test changed.

### Also

- README: the stale "furniture is primitive blockout" limitation has been rewritten — it has not
  been true since the realism pass.
- A slide deck covering the whole project (`VR_Fall_Prevention_Trainer.pptx`).

## 2026-09-23 — bug-fix pass and per-test scoring

Two things happened in this release: every problem listed in `SYSTEM_ANALYSIS.md` was fixed, and
per-test scoring with an adaptive focus was added. Finding ids (F-C1, F-H1, …) refer to that
document.

A copy of the project as it was before this pass is in `_backup_before_fixes/` (it carries a
`.gdignore`, so Godot ignores it).

> **Not yet run in the engine.** These changes were made and checked statically — every script
> parses, every scene property matches an export, every NodePath and file reference resolves, and
> the scoring and focus rules were unit-tested outside the engine. Nothing has been run in Godot
> since. Expect to fix a few things on the first run, and see "What to check first" at the end.

### New: per-test scores, the performance board, and the adaptive focus

- Every room and the balance exercise is now scored 0–100 on its own (`SessionManager.room_score`,
  `balance_score`, `test_scores`), stored in each session as `rooms` and `tests`.
  Room = 70 % hazards + 30 % rail use, minus 10 per unrecognised near miss (capped at −20).
  Balance = steadiness of completed reaches × fraction completed.
- **Performance board** (`scripts/ui/performance_board.gd`, `scenes/ui/performance_board.tscn`), on
  the hallway wall by the start: one row per test with last time, today (live) and the change, the
  focus row outlined, and a footer explaining the choice.
- **Adaptive focus** (`SessionManager.compute_focus`): the lowest average over the participant's
  last 3 sessions, if it is below 90. Named on the instruction panel and in the spoken welcome,
  marked with a beacon at the room's doorway (`scripts/world/focus_beacon.gd` + `FocusMarkers` in
  `main.tscn`), and turned into spoken hints on entry built from what was missed there last time
  (`HINTS` in `session_manager.gd`).
- **Room tracking** (`scripts/world/room_zone.gd`): per-room time, "visited", live per-room scores,
  and the "you found everything in this room" cue.
- **GO AGAIN** button: start another session straight from the debrief, with the focus recalculated
  to include the session just played.
- Debrief gained a room-by-room section and a "next time, focus on …" line; the report tool gained
  a per-test table, per-test trends, the recent averages with the next focus, and `--participant`.

## 2026-10-04 — Core System I: crossing a room without touching anything

Finding a hazard and getting past one are different skills, and until now only
the first was tested. You could point at the glass coffee table, name it
correctly, and walk your shin into it.

Five rooms now have a **walking route**: a chain of green rings on the floor. The
first lights when you walk in, standing on it lights the next, and the stretch
between two is a leg. A leg is clean only if you neither touched a hazard on the
way nor chose a line straight through one — so it scores both the walking and the
planning. Crossing a hazard counts even if you had already flagged it; the near
miss is about recognition, this is about navigation, and the log keeps the two
apart.

### The legs are meant to be awkward

Rings placed along a safe path would test nothing. Ten of the seventeen legs in
the house have a **blocked direct line** — the rug edge spans the hall, the
cupboard door stands open across the kitchen, the lead runs across the living
room — and the task is to notice and go round.

Every leg was verified to have a clear path before being placed, by breadth-first
search on a 5 cm grid over each room's real furniture and hazard footprints. That
search found a genuine design fault: **the living room could not be crossed on
foot at all.** The television lead was 2.3 m long in a 3.8 m room, and with the
sofa on one side and the side table on the other there was a 6 cm gap — the sofa
and the coffee table were unreachable by walking. The lead is now 1.95 m, leaving
0.4 m at the west end. It still runs across the floor from the television, so the
hazard is unchanged; the room is now one you can cross carefully instead of one
you cannot cross.

### Two sizes for a slip zone

`SlipZone.extents` is a *warning* volume and is deliberately generous — you want
to be told a moment before you are standing in the wet patch. Judging a route
against that would condemn nearly every path through a room, including the only
ones that exist, so `route_extents` holds the real object: the width of the lead,
the edge of the mat. Five new footprints were added for floor obstacles that had
none (the hall cord, the coffee table, the footstool, the open cupboard door, the
bath mat), so walking into those is now recorded at all. Twelve zones, up from
seven.

### Scoring

A room is now 50 % hazards found, 20 % rail use, 30 % route cleanliness, with the
near-miss penalty unchanged. Route cleanliness is the share of the room's legs
crossed cleanly; legs never attempted count against it. A route registers itself
as the room loads, so ignoring the rings scores zero for that 30 % rather than
having it quietly redistributed — otherwise skipping the task would be the
easiest route to a good score. The street and the overall weighting are unchanged,
and the staircase has no route because its gated step discs already are one.

Session log schema 3. Additive only: every key version 2 wrote is still written,
so old logs still load and still drive the adaptive focus.

### Nothing is enforced

You can ignore the rings, walk anywhere and leave. Gating a living room would
teach compliance with a video game rather than confidence in a house.

Verified: all 41 scripts parse, the checker is clean, and every hazard, decoy,
room zone, teleport disc, rail, gated region, crossing, car, stair flight and
beacon is byte-identical to before the change.

## 2026-09-27 — three rendering levels, because the default was wrong for a laptop

The realism pass ran badly on an M2 MacBook Air. That was a bad default on my
part rather than a limit of the machine: when the question was "where will this
be shown", the answer was "desktop / tethered PC VR, go all in", and I took it
literally and switched on a feature set that assumes a discrete GPU. A fanless
laptop with integrated graphics is exactly what that set punishes.

**What was costing what**, in descending order:

- **SDFGI** — real-time bounced light. On integrated graphics it can cost more
  per frame than everything else put together.
- **Five shadow-casting `OmniLight3D`s.** A point light's shadow is a cube, so
  each one is six renders of the whole scene, every frame. That is roughly thirty
  extra passes before a single visible triangle is drawn.
- **Volumetric fog**, **SSIL** and **screen-space reflections** stacked on top.
- **4x MSAA at Retina resolution.** The "1280x720" window is really 2560x1440
  physical pixels — 3.7 million of them, shaded four times over.
- **vsync was off** (`vsync_mode=0`). That is the sneaky one: it renders flat
  out instead of capping at the display's refresh rate, so a fanless laptop heats
  up, throttles, and gets *slower the longer it runs*.
- 345 props on triplanar materials, which is three texture fetches each instead
  of one — worth it for floorboards that run continuously, but it adds up.

### The fix

`scripts/util/graphics_quality.gd` groups the expensive features into **Smooth /
Balanced / Ultra** and chooses one at startup from `RenderingServer.
get_video_adapter_name()`: integrated adapters start on Smooth, everything else
on Balanced. Nothing starts on Ultra — a first run that stutters is worse than
one that looks slightly flatter.

**F8 cycles the levels while running** and shows the level and current frame
rate for a few seconds, so you can find out what a given machine minds instead of
guessing. The choice is saved in `user://settings.cfg` as
`Settings.graphics_quality` (-1 means "decide from the adapter again").

Smooth keeps everything you actually look at — the textures, the materials, the
filleted edges, sun shadows and ambient occlusion — and drops SDFGI, point-light
shadows, volumetric fog and SSIL, renders 3D at 75% with FSR 1 and uses FXAA.
Ambient light is lifted slightly at the lower levels so that losing the bounced
light makes rooms flatter rather than darker.

FSR 1 rather than FSR 2 deliberately: FSR 2 looks better but is temporal, and
temporal upscalers ghost behind moving objects, which is not something to inflict
on an application whose subject is judging where things are. In VR the headset
sets its own render scale, so only the effects change there.

Also: `vsync_mode` is now 1, and the project's startup MSAA is 0 because
GraphicsQuality sets it per level at runtime.

Nothing in the gameplay inventory moved — 68 nodes, still identical to before the
realism pass began.

## 2026-09-27 — the architrave crash, and three more of the same kind

The first run of the realism pass threw *Trying to assign an array of type
"Array" to a variable of type "Array[float]"* from `room_builder.gd`, repeatedly,
and the debugger stopped on it.

**The bug.** One line in `_add_doorway_trim`:

```gdscript
var sides: Array[float] = [1.0, -1.0] if architrave_both_sides else [1.0]
```

GDScript cannot infer the element type of an array literal that comes out of a
conditional expression. It parses, it compiles, and then it fails the moment the
line is reached — which is why `gdparse` had nothing to say about it. `sides`
stayed empty, the loop ran zero times, and every doorway in the house lost its
architrave. It is now built with a plain branch on a `PackedFloat32Array`, which
has one unambiguous element type and cannot go wrong this way.

**Three more found by looking for the same shape of mistake:**

- `mesh_kit.gd` declared `var samples: Array[PackedFloat32Array] = [...]` from a
  literal of function calls — the same trap one step from biting. Now an untyped
  array with the element type asserted where it is read.
- `_add_glazing` used `axis["centre"] as Vector3` to get a Vector3 out of a
  Variant. `as` is for object types; on a built-in it parses and can return
  something unexpected. Replaced with typed locals.
- Four separate runs of skirting on one wall were all named `Skirt_0`, so Godot
  quietly renamed them. Harmless, but it made the tree unreadable. Trim nodes now
  carry a per-build serial.

**What the stack trace ruled out.** `_build_joinery` builds skirting and coving
*before* architrave, and both had already been generated when the error hit — so
the material library, the texture loading, the filleted-box generator and its
tangent generation were all confirmed working by the same trace that showed the
bug.

### Two new checks, so neither kind can come back

`tools/check_project.py` now also:

- **Flags GDScript runtime traps a parser cannot see** — a typed `Array`
  assigned from a conditional, or from a bare literal after declaration. Both
  compile cleanly and fail when reached.
- **Sweeps every room's wall geometry** from its real numbers: holes that run off
  the end of a wall, reach above the ceiling, overlap each other, sit on the
  floor when they should be on a sill, or are declared in a wall that
  `build_walls` never builds — plus a point-by-point sweep of each wall plane
  confirming every point is either inside a hole or covered by exactly one
  segment. All six rooms, six doorways and five windows pass.

Both were verified by deliberately reintroducing the faults and confirming they
were caught.

## 2026-09-25 — making it look like a real house

The rooms were the right shape and the wrong material: correctly proportioned
boxes in flat colours, which reads as a diagram of a house rather than a house.
This pass changes what everything is made of and how it is lit, and adds the
joinery and clutter a real room has, without moving anything the training
depends on.

**Nothing was downloadable.** Every asset host is blocked from both machines this
was built on, so there is no imported model and no photograph: the 23 PBR texture
sets in `assets/textures/` are baked from numpy by `tools/make_textures.py`, and
the geometry is generated from dimensions. That turned out better than an asset
pack would have been, because a texture generated at the size it represents tiles
perfectly and a prop built from its dimensions is always to scale.

### What changed

- **23 generated PBR texture sets** (albedo, normal, roughness; all seamless):
  oak boards, porcelain and slate tile, carpet, wool rug, plaster, wallpaper,
  subway tile, brick, render, paving, bitmac, grass, oak, walnut, satin paint,
  upholstery, linen, leather, quartz, brushed steel, roof tile.
- **`Surfaces`**, a shared material library keyed by name, with **world-space
  triplanar UVs** -- so the floorboards run the whole length of the hallway and
  the grout lines carry across the bathroom threshold instead of restarting at
  every slab. No UV authoring anywhere.
- **`MeshKit`** puts an exact 18 mm fillet on every edge of every prop. Faces stay
  dead flat and the outer dimensions are unchanged, so a table top is still a
  table top and collision is untouched.
- **Joinery generated by `RoomBuilder`**: skirting with a moulded cap, two-step
  coving, architrave, door linings and reveals, oak thresholds. All from the
  numbers that already made the walls.
- **Real windows.** `openings` could only cut from the floor up, which is a
  doorway; `window_openings` stands a hole on a sill, keeps the wall below solid,
  and fits a lining, a projecting sill, glazing bars and a pane that stops the
  teleport arc. Five of them, replacing the flat bright panels that used to be
  stuck on the walls.
- **New lighting**: ACES tonemapping, SDFGI, SSAO and SSIL, screen-space
  reflections, volumetric fog, a physical sky, and a sun with a real angular size
  so shadows soften with distance. Every room light is now a visible pendant with
  the lamp inside its shade.
- **Dressing** in all seven spaces: cushions, throws, duvets, curtains, radiators,
  mirrors, pictures, plants, books, mugs, kitchen cabinet doors with handles, a
  splashback, taps, an extractor hood, bathroom suite detail, coat hooks, a smoke
  alarm, light switches and sockets, belisha beacons at the crossing, hedges,
  gate posts, front-door furniture. This is not only decoration: a hazard is only
  a real test of discrimination if it sits among things that are not hazards, and
  a trailing flex is easy to spot in an empty room.

### What deliberately did not change

- **Two lights stay bad.** The bedroom and stairwell are at `light_energy = 0.4`
  because inadequate lighting is the hazard in both. The pass worked around them:
  the bedroom window has its curtains drawn and its ceiling pendant is modelled
  unlit, which is both why the room is dim and what a real bedroom in that state
  looks like.
- **The sofa still has no arms.** That is the hazard.
- **The wet patches, the wet leaves and the wheelie bin keep their flat colours.**
  The participant has to be able to see a hazard to flag it, so how visible it is
  is a training decision, not a look one. Same for the crisp white road markings.
- **Every trim piece has no collision**, and the decorative furniture that would
  otherwise narrow a route (the kitchen chairs) is non-colliding and tucked in.
  The navigable space is exactly what was tested.

### How it was verified without an engine

`tools/check_project.py` is new: it parses every script, resolves every resource
path, NodePath and `load_steps` count, and validates every property name in every
scene and sub-resource against the scripts' own `@export` lists.

That last check exists because **Godot silently discards a `.tscn` assignment
whose property does not exist** -- no error, no warning, and the line vanishes the
next time the editor saves. It caught a real instance during this pass: 35 decor
nodes in the kitchen referenced an `ExtResource` id that scene had never declared,
and every one would have loaded as a bare `Node3D` with all its properties
dropped, in total silence.

It also dumps a **gameplay inventory** as JSON. Taken before the pass and after
and diffed: **67 nodes across 14 categories, zero differences.** Not one hazard,
decoy, slip zone, room zone, teleport disc, handrail, gated region, crossing, car,
stair flight, balance node, wall button or collision setting moved.

Separately, the rounded-box geometry and the wall generation were checked
numerically before they ever reached Godot -- exact dimensions, flat faces, unit
normals, consistent winding, and a grid sweep of every wall across seven layouts
confirming no gaps, no overlapping segments and holes exactly where asked. Godot's
winding order and normal-map convention were verified against the engine's own
documentation, which caught a real bug: the custom mesh had no tangents, so every
normal map would have darkened the props instead of texturing them.

> **Still not run in the engine.** On the first open, let Godot finish importing
> the textures before pressing F5 or the house comes up in its old flat colours.
> If the filleted props ever look inside-out, that is the `WINDING_CW` constant at
> the top of `mesh_kit.gd` and flipping it fixes all of them at once.

## 2026-09-24 — a button to skip the talking

The spoken instructions are written for someone hearing them for the first time. From the second
session on they are just a wait, and a tester running the same room ten times in a row hears the
welcome ten times. There is now a fourth button on the west wall, `Skip talking`, next to `START`,
`Seated mode` and `Say that again`.

- It is enabled at **every** stage, unlike the other three, so it works mid-sentence during the
  welcome, the exploration briefing, the balance instructions and the debrief.
- Pressing it stops the current line (`AudioCues.stop_speech()`) and suppresses the rest of the
  narration for that stage: the welcome, the "well done, now the balance task" line and the spoken
  focus-room hint all check `_skip_speech` before speaking.
- Nothing is lost. The **written** instructions on the panel are untouched, and the focus line is
  refreshed on the panel at the moment you press it, so the room you are meant to practise is still
  named in text.
- `Say that again` clears the flag and reads the current stage from the top, so skipping is not a
  one-way door.
- Each new stage clears the flag too — skipping the welcome does not silence the exploration
  briefing. Skip is per-stage, deliberately, so a participant who skips one thing is not left with
  no guidance for the rest of the session.
- `F9` on the keyboard does the same thing, for testing without walking to the wall. It is logged
  as `instructions_skipped` with the stage, so a session log shows which stages were heard.

The three west-wall buttons were re-spaced from z = −0.62 / 0 / 0.62 to −0.93 / −0.31 / 0.31 to
make room for the fourth at 0.93. The outermost edge sits at 1.07 m, inside the hallway's 1.24 m
inner half-width, so nothing clips the wall corners.

## 2026-09-24 — a bigger house

- **Two new rooms.** A **living room** (3.8 × 4.7 m) and a **kitchen** (3.8 × 3.7 m), both fully
  furnished as blockout, opening off the west end of the hall. They cover the two settings where
  domestic falls in this age group actually happen and which the house was missing: getting out of
  a seat, and reaching in a kitchen.
- **Eight new hazards**: sofa too low and armless, low glass coffee table on the walking route,
  television lead across the floor, footstool left in the way, everyday things stored too high, a
  wobbly step stool, a spill by the sink, a cupboard door open across the walkway. Plus a third
  bathroom hazard — a bath mat with no grip backing — and two new decoys (an armchair with firm
  arms, deliberately placed beside the bad sofa, and a kettle). The house now has **24 hazards and
  6 decoys**, up from 15 and 4.
- **The hall is 12 m long** (was 8) with six doorways, and the start area — panel, progress board
  and the three buttons — moved to the new west end. The board is bigger and its viewport scaled to
  match, because there are now eight tests on it.
- **The board and the focus system gained `Living room` and `Kitchen`** as tests in their own
  right; the report tool lists them too.
- The roof and the front lawn were refitted around the bigger footprint (12.5 × 12.5 m).

## 2026-09-24 — walking now climbs

- **Walking was purely horizontal.** WASD moved the rig sideways only, so walking into the
  staircase left the eyes at ground-floor height while the virtual body stood on the tread above —
  giant legs filling the screen and a view that never rose. The desktop rig now follows the ground
  (`_follow_ground`): up stair treads, down the kerb, out through the front door, smoothly rather
  than as a jolt, with `step_height` (0.45 m) deciding what is a step and what is a wall. Seated
  mode's lift is preserved.
- **The body stands where the RIG stands**, not under wherever the head happens to be. Leaning out
  over a stairwell used to shrink the body and bring its hips up to eye level. The feet still take
  their own ground readings, so one foot on a tread and one on the tread below is still right.

## 2026-09-24 — holding the rail actually works

- **The grip reached the rail but never took hold.** The hand was moved onto the rail and then
  asked to grab whatever its grab volume overlapped — but the physics engine only learns the hand
  has moved on the next step, so it overlapped nothing and the grip passed with nothing held (the
  rail glowed blue, "in range", instead of green). `GrabController.grab_specific()` now takes the
  object the hand reached for, with no overlap race. The nearer hand does the reaching, rather than
  the left hand always crossing the body.
- **Walking up a step locked the whole flight.** The chain tracked the last point you *teleported*
  to, so walking (desktop keys, or room-scale in a headset) left you standing next to a disc the
  system did not think you were on, and every disc read "One step at a time".
  `GatedTeleportPoint.standing_point()` now works out which step you are on from where you actually
  are, however you got there.

## 2026-09-24 — reaching the rail

- **The discs were in the middle of the treads** while the rail is against the wall, so standing on
  one put the rail 0.6 m across the step. They now sit 0.25 m to the rail side, where a person
  actually walks, putting the rail ~0.35 m from the shoulder.
- **Space now reaches.** On the desktop rig the hands are parked at fixed offsets and cannot be
  moved sideways, so the grip could never touch a rail beside you — you had to walk off the step to
  reach it, which moved you off the step. Holding Space now moves the grabbing hand onto the
  nearest rail or ball within 1.3 m (`desktop_reach` on the `FlatDebugRig` node) and keeps it there
  until you release or walk out of range. `GrabRail` and `BalanceOrb` join a `grabbable` group so
  the rig can find them.

## 2026-09-24 — desktop grip moved to Space

- Gripping (taking hold of a handrail or the balance orb) is now **Space** on the desktop rig;
  right click is the teleport arc only. They used to share the right button, which made it
  impossible to aim a teleport without also grabbing at whatever was near your hand. The input map
  action `debug_grab` became `debug_grip` (Space) and `debug_teleport` (right click).

## 2026-09-24 — stairwell top, take two

- **You could see over the house.** Standing on the landing puts the eyes at ~3.2 m, but the
  stairwell borrows the hallway's north wall, which is only 2.4 m tall — so the view at the top was
  the underside of the roof slabs cutting across the screen. `NorthGable` now fills that wall from
  2.4 m to the top of the shaft.
- **The landing was a ledge.** The flight now starts 0.6 m earlier, making the half-landing 1.9 m
  deep instead of 1.3 m, and the shaft is 1.5 m wide instead of 1.2 m.
- **Somewhere to stand and something to look at**: a window at the half-landing (with daylight
  spilling onto the treads below) and the door moved to the side wall. `TP_LandingBack` lets the
  participant step back from the edge to the window; `TP_Landing` arrives facing up the flight, so
  nobody lands staring down the drop.
- `TP_Landing` no longer requires the rail — it is flat ground, and the rail cannot be reached from
  the far end of a landing. Going back down still requires it, because `TP_Step6` does, which is
  the habit that matters.
- The street's roof slabs and lawn were refitted around the wider shaft.

## 2026-09-24 — the street

- **A street outside the front door** (`scenes/outdoor/street.tscn`, reached through a new opening
  in the hallway's south wall): garden path, pavement, a road with a marked crossing and dropped
  kerbs, the far pavement with a postbox and bench, neighbouring houses, and a roof on the house so
  it reads as a house from outside. The sky is now a real sky rather than a flat colour.
- **Five outdoor hazards** (step down at the front door, lifted paving slab, wet leaves, high kerb,
  bin blocking the pavement) and one decoy (the postbox), with slip zones on the leaves and the
  lifted slab. The house now has 15 hazards and 4 decoys.
- **Crossing measurement** (`scripts/world/street_crossing.gd`): every step into the road is scored
  out of 100 — 40 for using the crossing, 40 for looking both ways beforehand (checked against the
  camera's yaw while still on the pavement), 20 for leaving a six-second gap. It measures rather
  than blocks, and says the single most useful thing at the moment it matters.
- **One slow car** (`scripts/world/street_car.gd`): 3.5 m/s with an 11 s gap between runs, eases to
  a stop for anyone in the road, never collides, no horn, no camera movement.
- **"Street" is a sixth test** on the board and in the focus system: 50 % outdoor hazards + 50 %
  crossing quality, with focus hints covering both the missed hazards and the crossing habit.
- `Prop` gained a `walkable` flag: paths, pavements and the road accept the teleport arc, grass and
  walls do not, which keeps the participant on the route without a single invisible wall.
- The report tool gained a road-crossing table and per-crossing CSV columns.

### Also added

- **Virtual body** (`scripts/player/virtual_body.gd`, a node on the `XRPlayer`): a slim waist, legs
  with feet that step as you walk, and a shadow. Nothing above the waist — a chest sits ~30 cm
  below the eyes and hides the floor, which is the one thing this app needs visible. Feet are
  placed on the floor found by a downward ray, so they sit correctly on stair treads; the hips lag
  the head and only turn past ~45° of twist; a teleport re-plants both feet. No head (near-plane
  clipping), no collision, no idle animation. Turn it off with `enabled` on the node; sizes and
  step length are exports.
- Floor and hazard labels are single-sided and (for teleport points) fully billboarded, so reading
  one from above no longer shows the text mirrored.
- Desktop walking now moves relative to where the camera looks in the world, not to its yaw within
  the rig — with the rig rotated at spawn, WASD came out turned by 90°.
- **Stairwell rebuilt** (`scenes/rooms/staircase.tscn`): a 1.2 m wide shaft with the 0.9 m flight
  filling it, instead of the same flight standing in the middle of a 2.6 m room where the rail was
  marooned out in the open. The good rail is wall-mounted on brackets over the tread edge at 0.9 m
  above the nosing line; the broken side has matching brackets and no rail; the light is a wall
  fitting rather than a pendant in an open shaft; the landing now meets the back wall and has a
  closed door at the head of the flight. The gate, compliance zone and all four teleport points
  were re-measured to the new layout.
- Teleport-point captions are smaller and a locked one only explains itself within 2.2 m, so a
  flight no longer shows four stacked captions at once.

### Critical

- **F-C1** Stair handrail was horizontal at 1.78 m and 0.65 m beyond the treads, so it could not be
  gripped and the stairs could not be climbed. Rebuilt on the flight's slope at the tread edge
  (`StairRailWest` in `staircase.tscn`), with balusters, and the broken-rail brackets and hazard
  mirrored to match.
- **F-C2** Entering the stairwell trapped the participant: no destination outside the gated region
  was legal and there was no exit point. The gate now starts at the first tread and `TP_Bottom`
  sits outside it.
- **F-C3** Player spawn, instruction panel, debrief panel and all wall buttons faced the wall
  (a row/column mix-up in the hand-written transforms). All corrected in `main.tscn`, spawn height
  set to 0, and `SessionDirector` now turns the rig to face the panel at start-up.

### High

- **F-H1** Seated-mode height was erased by every teleport and reset against the spawn floor.
  The lift is now relative and re-applied in `XRPlayer.teleport_to`.
- **F-H2** A saved "seated mode ON" no longer leaves the participant at standing height: the rig
  re-measures once XR (or the desktop rig) is up.
- **F-H3** Descending skipped the rail (the bottom point was always active). Points are now
  selectable only from the one directly above or below, and the bottom point needs the rail
  whenever you are coming down to it.
- **F-H4** Stair arrival yaw was reversed — the participant arrived facing back down the stairs.
- **F-H5** Timed-out balance trials no longer count as steadiness (standing still scored ~100);
  the instructions no longer tell people to step, which was scored as sway; and the target is
  placed where there is room for it.
- **F-H6** Comfort vignette and the slip-zone red flash were drawn outside the field of view.
  Quad resized to an angle that is actually visible, and a short "blink" now closes it on teleport.
- **F-H7** A corrupt log was silently overwritten. Writes are atomic (temp file + rename) and a
  damaged log is copied aside first.

### Medium

- **F-M1** `started_utc` recorded the END of the session.
- **F-M2** The bathroom compliance zone penalised ordinary walking and contradicted its own
  "no grab bar where you step in" hazard; removed, with a note on how to do bath transfers properly.
- **F-M3** Every rail crossing is now recorded (not just the last one per zone), the stair zone
  excludes the landing, and the tips are worded per room.
- **F-M4** Physics state changed inside area signals (Godot "blocked during in/out signal") — now
  `set_deferred` in `balance_orb.gd` and `wall_button.gd`.
- **F-M5** Free teleport could land on the wardrobe, the bed and the bath rim. Destinations must be
  in the new `walkable` group (floors and stair treads).
- **F-M6** `main.tscn` referenced every sub-scene by a UID that did not match the file; references
  are now by path.
- **F-M7** Generated room/stair/prop geometry no longer sets `owner` in the editor, so saving a
  room scene cannot bake duplicate copies into the `.tscn`.
- **F-M8** Spoken lines queue instead of cutting each other off; the balance intro waits for speech
  to finish; countdown numbers still interrupt.
- **F-M9** Slip zones narrowed so a careful route past each hazard exists.
- **F-M10** Doubled walls at every room join removed (one side builds each shared wall), with a
  filler for the part of the bedroom wall the hallway does not cover.

### Low

- Decoys play a neutral tone instead of the "wrong" buzz, and repeated flags of the same object
  count once (F-L1).
- The touched balance orb stays green until the next countdown (F-L2).
- A rail that auto-releases when the hand drifts away now tells the grab controller (F-L3).
- Two-tone cues accumulate phase, so they no longer click (F-L4).
- Player spawn height is 0 rather than 0.199 (F-L5).
- `force_debrief` is bound to F10; `smooth_locomotion` (never implemented) removed; `text_scale`
  applies live; `xr_active` is recorded in the session; participant id can be set with
  `-- --participant=P01`; the unused "welcome" line is gone and "room_complete" is now used (F-L6).
- Panels only re-render after their content changes (F-L7) and use plain linear filtering (F-L8).
- `delta` compares only components present in both sessions, per participant (F-L9).
- Desktop rig: crosshair, hands reach out while gripping, pointer aims at the crosshair (F-L11).
- godot-xr-tools note explains why this project's own Teleporter must stay for the stairs (F-L12).
- Valve Index and Windows Mixed Reality interaction profiles added (F-L13).
- `.gitignore` added; README version corrected; "0 minutes" now reads "under a minute" (F-L14).

### What to check first on the next run in Godot

1. Open `main.tscn` and look down at the house: the start panel, the board and the buttons should
   face into the hallway, and the participant should start facing them.
2. Walk to the stairs and grab the rail from the bottom point, then climb one step at a time.
3. Press F10 mid-session to jump to the debrief and confirm the room-by-room numbers and the board.
4. Run a second session and check the board's "Last time" column and the focus beacon.
5. Re-save the OpenXR action map from *Project Settings → OpenXR → Action Map* in your Godot
   version before building for a headset (the binding format is version-sensitive).
