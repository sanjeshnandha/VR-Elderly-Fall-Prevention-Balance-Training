class_name DebriefPanel
extends Control
## Core System E, presentation half -- the end-of-session scoring screen.
##
## Rendered through `ViewportPanel3D` (or `XRToolsViewport2Din3D`) onto a quad
## 1.75 m in front of the participant. See viewport_panel_3d.gd for why that
## distance is not negotiable.
##
## TYPOGRAPHY AND COLOUR CONTRACT (Architectural Fix 5.3)
## ------------------------------------------------------
##  * Background is dark grey (#1E1E22), NOT black. Pure black next to bright
##    text produces halation through VR lenses and smears the glyph edges.
##  * Text is warm white and amber-yellow, NOT pure white. Same reason, and
##    yellow-on-dark survives the blue-light loss of an ageing crystalline lens.
##  * Body text is 46 px in a 1600 px viewport mapped to a 1.2 m quad at 1.75 m
##    -- roughly a 1.2 degree cap height, comfortably above the ~0.8 degree
##    floor where VR text starts to break up.
##  * No colour is load-bearing on its own: every green/amber state also carries
##    a word or an arrow, for the ~8% of men with colour vision deficiency.
##  * Everything on this panel is also spoken aloud, head-locked.

const BG := Color("#1e1e22")
const PANEL_BG := Color("#2a2a30")
const TEXT := Color("#f4f1ea")
const HEADING := Color("#ffd400")
const GOOD := Color("#3ddc6b")
const WARN := Color("#ffab40")
const DIM := Color("#a8a8b0")

const SIZE_TITLE := 84
const SIZE_SECTION := 56
const SIZE_BODY := 46
const SIZE_SCORE := 110

var _root: VBoxContainer
var _summary: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 22)
	scroll.add_child(_root)


## Render a summary dictionary from `SessionManager.build_summary()`.
func show_summary(summary: Dictionary) -> void:
	_summary = summary
	for child in _root.get_children():
		child.queue_free()

	var score: Dictionary = summary.get("score", {})
	var hazards: Dictionary = summary.get("hazards", {})
	var handrail: Dictionary = summary.get("handrail", {})
	var balance: Dictionary = summary.get("balance", {})
	var delta: Dictionary = summary.get("delta", {"has_previous": false})

	_add_label("Your session results", SIZE_TITLE, HEADING)
	_add_label(
		"Participant %s  ·  %s minutes" % [
			summary.get("participant_id", "?"),
			str(int(float(summary.get("duration_seconds", 0.0)) / 60.0)),
		],
		SIZE_BODY, DIM
	)
	_add_spacer(10)

	# --- Overall -----------------------------------------------------------
	var overall := float(score.get("overall", 0.0))
	_add_label("%d out of 100" % int(round(overall)), SIZE_SCORE, _score_color(overall))
	if delta.get("has_previous", false):
		_add_label(_delta_line("Compared with your last session", float(delta.get("overall", 0.0))),
			SIZE_BODY, _delta_color(float(delta.get("overall", 0.0))))
	else:
		_add_label("This is your first session. Future sessions will be compared with this one.",
			SIZE_BODY, DIM)
	_add_spacer(18)

	# --- Hazards -----------------------------------------------------------
	_add_label("Hazards you spotted", SIZE_SECTION, HEADING)
	_add_label("%d of %d" % [hazards.get("found", 0), hazards.get("total", 0)],
		SIZE_BODY, _score_color(float(hazards.get("accuracy_pct", 0.0))))
	_add_bar(float(hazards.get("accuracy_pct", 0.0)))
	if delta.get("has_previous", false):
		_add_label(_delta_line("Change", float(delta.get("hazard", 0.0))), SIZE_BODY,
			_delta_color(float(delta.get("hazard", 0.0))))
	_add_spacer(14)

	# --- Handrail ----------------------------------------------------------
	_add_label("Using the rails", SIZE_SECTION, HEADING)
	var pct := float(handrail.get("compliance_pct", 0.0))
	if int(handrail.get("opportunities", 0)) == 0:
		_add_label("No stairs or bath transfers this session.", SIZE_BODY, DIM)
	else:
		_add_label("You held on for %d of %d crossings (%d%%)" % [
			handrail.get("complied", 0), handrail.get("opportunities", 0), int(round(pct))
		], SIZE_BODY, _score_color(pct))
		_add_bar(pct)

	_add_spacer(14)

	# --- Balance -----------------------------------------------------------
	_add_label("Balance and reach", SIZE_SECTION, HEADING)
	if int(balance.get("trials", 0)) == 0:
		_add_label("The balance exercise was not completed this session.", SIZE_BODY, DIM)
	else:
		_add_label("Steadiness score %d out of 100" % int(round(float(balance.get("mean_stability", 0.0)))),
			SIZE_BODY, _score_color(float(balance.get("mean_stability", 0.0))))
		_add_label("Average time to reach the target: %.1f seconds" % float(balance.get("mean_completion_s", 0.0)),
			SIZE_BODY, TEXT)
		_add_label("Furthest you leaned: %.0f cm" % float(balance.get("max_sway_cm", 0.0)), SIZE_BODY, TEXT)
		_add_bar(float(balance.get("mean_stability", 0.0)))
		_add_label(
			"This is a rough guide from headset movement, not a medical measurement.",
			SIZE_BODY - 8, DIM
		)

	_add_spacer(18)

	# --- Tips --------------------------------------------------------------
	_add_label("What to work on", SIZE_SECTION, HEADING)
	var tips: Array = summary.get("tips", [])
	for tip in tips:
		_add_bullet(str(tip))

	_add_spacer(18)
	_add_label("Your results have been saved. Press the green button on the wall to finish.",
		SIZE_BODY, DIM)

	_speak_summary(summary)


# ---------------------------------------------------------------------------
#  Spoken version -- head-locked, never positional (Architectural Fix 5.3)
# ---------------------------------------------------------------------------

func _speak_summary(summary: Dictionary) -> void:
	var hazards: Dictionary = summary.get("hazards", {})
	var handrail: Dictionary = summary.get("handrail", {})
	var lines: Array[String] = []
	lines.append("Here are your results.")
	lines.append("You found %s of %s hazards." % [hazards.get("found", 0), hazards.get("total", 0)])
	if int(handrail.get("opportunities", 0)) > 0:
		lines.append("You used the rails on %d percent of crossings." % int(round(float(handrail.get("compliance_pct", 0.0)))))
	var tips: Array = summary.get("tips", [])
	if tips.size() > 0:
		lines.append("One thing to work on. " + str(tips[0]))
	AudioCues.speak_text(" ".join(lines))


# ---------------------------------------------------------------------------
#  Widget helpers
# ---------------------------------------------------------------------------

func _scaled(size: int) -> int:
	return int(round(float(size) * Settings.text_scale))


func _add_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", _scaled(size))
	label.add_theme_color_override("font_color", color)
	# A dark outline keeps every glyph legible regardless of what is behind it.
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_root.add_child(label)
	return label


func _add_bullet(text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_root.add_child(row)

	var dot := Label.new()
	dot.text = "•"
	dot.add_theme_font_size_override("font_size", _scaled(SIZE_BODY))
	dot.add_theme_color_override("font_color", HEADING)
	row.add_child(dot)

	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", _scaled(SIZE_BODY))
	body.add_theme_color_override("font_color", TEXT)
	row.add_child(body)


## A wide progress bar. Deliberately tall and high contrast; a thin bar is
## invisible through a headset lens.
func _add_bar(percent: float) -> void:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = clampf(percent, 0.0, 100.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 36)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _score_color(percent)
	fill.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	_root.add_child(bar)


func _add_spacer(height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	_root.add_child(spacer)


func _score_color(percent: float) -> Color:
	if percent >= 80.0:
		return GOOD
	if percent >= 50.0:
		return WARN
	return Color("#ff7043")


## Colour is never the only signal: the arrow and the words carry the meaning.
func _delta_line(prefix: String, value: float) -> String:
	if absf(value) < 0.5:
		return "%s: about the same" % prefix
	if value > 0.0:
		return "%s: ↑ up %.0f points" % [prefix, value]
	return "%s: ↓ down %.0f points" % [prefix, absf(value)]


func _delta_color(value: float) -> Color:
	if value > 0.5:
		return GOOD
	if value < -0.5:
		return WARN
	return DIM
