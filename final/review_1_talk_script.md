# Review 1 — Talking Script (5 minutes)

*Goal for this review: show the objects that exist in the scene so far. Walk through the editor
(or the running scene) room by room and speak roughly what's below in each section. Times are a
guide, not a script to read word for word.*

---

## 1. What this project is (30 sec)

"This is a VR training app for elderly users, built in Godot. The goal is to teach people to
spot fall hazards around the house, build the habit of using handrails, and do a light balance
exercise — like a physiotherapist would ask for. Everything is built at real-world scale, one
unit in the engine equals one metre, so the doorways, the stairs, the counters are the same size
as in a real house. For this review I'm showing the objects that make up the world — not the
full gameplay flow yet."

---

## 2. The house layout (30 sec)

"The whole thing is one connected house with four rooms: a hallway in the middle, and a
bathroom, a bedroom, and a staircase opening off it. You start in the hallway, and every room is
reachable by walking or teleporting through a doorway — there's no loading screen between rooms,
it's one continuous space, which matters for someone who's still learning to use the controls."

---

## 3. Hallway (45 sec)

"The hallway is the starting point. It has a small table with a lamp against one wall — that one
is a decoy, a completely safe object, there just to see if the person points at things that
aren't actually hazards. Then there are two real hazards: a rug with one edge curled up in the
middle of the floor, and an extension cord running across the walkway further down. Both are
common real-world trip hazards — actually more common causes of falls than something dramatic
like a broken step. Each hazard object can be pointed at and 'flagged' as spotted."

---

## 4. Bathroom (45 sec)

"The bathroom has a bathtub, a sink, a toilet, and a towel rail — the towel rail is a decoy, it's
safe. The two real hazards are a wet patch on the tile floor, shown with a shiny wet-looking
material, and the fact that there's no grab bar right where you actually step into the tub — there
is a grab bar fitted, but it's mounted at the wrong end, which is a genuine, common installation
mistake. There's also a separate invisible zone around the wet floor that reacts if you actually
walk into it, not just look at it."

---

## 5. Staircase (60 sec)

"The staircase is the most detailed room, because the stairs are where the handrail habit
actually gets tested. It's eight steps built at real stair dimensions — 19 centimetres up, 25
centimetres deep per step, the same as a normal house staircase. One step is very slightly taller
than the others, about two and a half centimetres, which is a realistic near-invisible trip
hazard. There's a working handrail on one side, and on the other side, just two mounting brackets
with nothing between them — a broken or missing rail, which is a flaggable hazard. There's also a
dim light fixture at the top, which is its own hazard — poor stairwell lighting is genuinely one
of the most common things that causes a fall on stairs."

---

## 6. Bedroom (45 sec)

"The bedroom has a bed, a bedside table with a lamp, and a wardrobe — the wardrobe is a decoy.
The three real hazards are: a chair with no armrests, which matters because without arms to push
off, standing up is much harder on the legs alone; a bedside lamp that's too dim to see by at
night; and clutter — a box, shoes, and books — placed directly on the path from the bed to the
door, which is the route someone takes when getting up at night, half-awake, in the dark."

---

## 7. Player and interaction objects (45 sec)

"On the player side, there's a VR rig with two hands. Each hand only does one thing: one hand
points and flags hazards, the other hand grabs — either a handrail or a glowing ball used for the
balance exercise. There are also three physical buttons on the wall at the start — Start, Seated
Mode, and Repeat Instructions — because for this audience, everything should be a big button you
can walk up to and press, not a hidden menu on the controller."

---

## 8. Closing (20 sec)

"So that's the full object inventory — four rooms, ten real hazards, three decoys, working
handrails, and the interaction objects for the player. Next step is wiring these into the full
session flow: flagging hazards, measuring handrail use, running the balance test, and generating
a results screen at the end."

---

*Total: roughly 5 minutes at a normal speaking pace. Cut section 5 (staircase) shorter first if
you're running long — it's the most detailed but the least essential to a first "here are the
objects" pass.*
