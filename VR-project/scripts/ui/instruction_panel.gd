class_name InstructionPanel
extends Control
## The welcome / instruction / settings-status panel.
##
## Same typography and colour contract as the debrief panel (see
## debrief_panel.gd). Rendered through ViewportPanel3D at 1.75 m.
##
## Note what this panel does NOT do: it has no clickable widgets. Every choice
## the participant can make is a physical button in the room beside the panel
## (Architectural Fix 5.4). The panel only ever tells them what is true right
## now -- what to do next, and which comfort options are on.

const BG := Color("#1e1e22")
const TEXT := Color("#f4f1ea")
const HEADING := Color("#ffd400")
const DIM := Color("#a8a8b0")
const ON := Color("#3ddc6b")

const SIZE_TITLE := 84
const SIZE_BODY := 50
const SIZE_SMALL := 40

var _title: Label
var _body: Label
var _status: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	Settings.settings_changed.connect(refresh_status)
	refresh_status()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 70)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 60)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 30)
	margin.add_child(column)

	_title = _make_label("Welcome", SIZE_TITLE, HEADING)
	column.add_child(_title)

	_body = _make_label("", SIZE_BODY, TEXT)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_body)

	var rule := ColorRect.new()
	rule.color = Color("#3a3a42")
	rule.custom_minimum_size = Vector2(0, 4)
	column.add_child(rule)

	_status = VBoxContainer.new()
	_status.add_theme_constant_override("separation", 12)
	column.add_child(_status)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", int(round(float(size) * Settings.text_scale)))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	return label


## Show a step of the script. Also spoken aloud, head-locked.
func show_step(title: String, body: String, speak: bool = true) -> void:
	_title.text = title
	_body.text = body
	if speak:
		AudioCues.speak_text(body)


func refresh_status() -> void:
	for child in _status.get_children():
		child.queue_free()
	_add_status("Seated mode", Settings.seated_mode)
	_add_status("Comfort vignette", Settings.comfort_vignette)
	_add_status("Spoken instructions", Settings.spoken_instructions)


func _add_status(name_text: String, is_on: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var name_label := _make_label(name_text, SIZE_SMALL, DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# The word "On"/"Off" carries the state; colour only reinforces it.
	var value_label := _make_label("On" if is_on else "Off", SIZE_SMALL, ON if is_on else DIM)
	row.add_child(value_label)

	_status.add_child(row)
