class_name XRToolsBridge
extends Node
## Optional integration layer for `GodotVR/godot-xr-tools`.
##
## The project deliberately ships working, self-contained implementations of
## pointing, grabbing, teleporting and comfort, so it opens and runs in a clean
## Godot 4 install with no addons. That matters for a semester project: a marker
## should be able to clone, open and press Play.
##
## If you *do* install godot-xr-tools (recommended for the final build -- its
## pickup, climbing and player-body code is far more mature than anything worth
## writing from scratch), drop this node under the XRPlayer. It:
##
##   * forwards `XRToolsPickable` grab/drop signals to the GrabRail interface,
##     so HandrailZone compliance measurement works unchanged;
##   * forwards `XRToolsFunctionTeleport` to respect GatedRegion, so
##     Architectural Fix 5.1 still holds with the addon's teleporter;
##   * hands `SeatedMode` a reference to `XRToolsPlayerBody` for Fix 5.2.
##
## Every lookup is by duck-typing (`has_method` / property presence) rather than
## by class name, so this file parses fine whether or not the addon exists.
##
## INSTALLING THE ADDON
##   1. AssetLib -> "Godot XR Tools" -> Download -> install into res://addons/
##   2. Project -> Project Settings -> Plugins -> enable "Godot XR Tools"
##   3. For headset vendor support: AssetLib -> "Godot OpenXR Vendors"
##   4. Add this node as a child of XRPlayer and press Play.

## Automatically find and wire everything under the player rig on _ready().
@export var auto_wire: bool = true

var _pickables: Array[Node] = []
var _teleport_functions: Array[Node] = []
var _player_body: Node = null
## XRToolsPickable -> the GrabRail whose state it drives.
var _rail_for_pickable: Dictionary = {}


func _ready() -> void:
	if not auto_wire:
		return
	var root := get_tree().current_scene
	if root == null:
		return
	_scan(root)
	_wire_pickables()
	_report()


func _scan(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
			_classify(child)


func _classify(node: Node) -> void:
	# XRToolsPickable exposes `picked_up(pickable)` / `dropped(pickable)`.
	if node.has_signal("picked_up") and node.has_signal("dropped"):
		_pickables.append(node)
	# XRToolsFunctionTeleport exposes a `can_teleport` property.
	elif "can_teleport" in node:
		_teleport_functions.append(node)
	# XRToolsPlayerBody exposes `player_calibrate_height`.
	elif "player_calibrate_height" in node:
		_player_body = node


func _wire_pickables() -> void:
	for pickable in _pickables:
		# A GrabRail parent or sibling receives the state, so the compliance
		# measurement in HandrailZone keeps working unchanged.
		var rail := _find_rail_for(pickable)
		if rail == null:
			continue
		_rail_for_pickable[pickable] = rail
		pickable.connect("picked_up", _on_pickable_picked_up)
		pickable.connect("dropped", _on_pickable_dropped)


func _on_pickable_picked_up(pickable: Variant) -> void:
	_set_rail_held(pickable, true)


func _on_pickable_dropped(pickable: Variant) -> void:
	_set_rail_held(pickable, false)


func _set_rail_held(pickable: Variant, held: bool) -> void:
	var rail: GrabRail = _rail_for_pickable.get(pickable)
	if rail == null:
		return
	rail.is_held = held
	if held:
		rail.grabbed.emit(pickable)
	else:
		rail.released.emit(pickable)


func _find_rail_for(pickable: Node) -> GrabRail:
	var parent := pickable.get_parent()
	if parent == null:
		return null
	var rail := parent as GrabRail
	if rail != null:
		return rail
	for sibling in parent.get_children():
		var sibling_rail := sibling as GrabRail
		if sibling_rail != null:
			return sibling_rail
	return null


func _process(_delta: float) -> void:
	# Architectural Fix 5.1 with the addon's teleporter: switch its master
	# enable off while the participant is inside a GatedRegion, so free-aim
	# teleport cannot bypass the stairs. The GatedTeleportPoints remain the only
	# way through, and they are still gated on the handrail grip.
	if _teleport_functions.is_empty():
		return
	var gated := GatedRegion.is_player_gated()
	for fn in _teleport_functions:
		fn.set("can_teleport", not gated)


func _report() -> void:
	print("[XRToolsBridge] pickables=%d teleport_functions=%d player_body=%s" % [
		_pickables.size(), _teleport_functions.size(),
		"yes" if _player_body != null else "no",
	])
	if _player_body != null:
		var seated := get_parent().find_child("SeatedMode", true, false)
		if seated != null:
			seated.set("_xr_tools_body", _player_body)
