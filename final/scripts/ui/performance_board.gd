class_name PerformanceBoard
extends Control
## The performance board: one row per test (Hallway, Bathroom, Stairs, Bedroom,
## Balance), each scored 0-100, showing last time, today (live, while you
## play), the change, and which test is today's FOCUS.
##
## Mounted on the hallway wall next to the start, rendered through
## ViewportPanel3D, so the participant sees where they stand before they begin
## and can walk back to watch today's numbers fill in. The debrief panel
## repeats the same room-by-room scores at the end.
##
## The focus is SessionManager.compute_focus(): the test with the lowest
## average over the last few sessions, if it is below the mastery threshold.
##
## Same typography and colour contract as the debrief panel: dark grey, warm
## white and amber, big text, and every colour backed by a word or an arrow.

## Emitted whenever the board's content changes, so ViewportPanel3D re-renders.
signal changed

const BG := Color("#1e1e22")
const ROW_BG := Color("#26262c")
const FOCUS_BG := Color("#3a2f14")
const TEXT := Color("#f4f1ea")
const HEADING := Color("#ffd400")
const GOOD := Color("#3ddc6b")
const WARN := Color("#ffab40")
const LOW := Color("#ff7043")
const DIM := Color("#a8a8b0")

const SIZE_TITLE := 72
const SIZE_BODY := 42
const SIZE_SMALL := 34

const COL_NAME := 470
const COL_NUM := 230

var _root: VBoxContainer
var _pending: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	margin.add_child(_root)

	SessionManager.scores_changed.connect(_queue_redraw_board)
	SessionManager.session_started.connect(_queue_redraw_board)
	SessionManager.room_changed.connect(_queue_redraw_board.unbind(1))
	SessionManager.session_ended.connect(_queue_redraw_board.unbind(1))
	Settings.settings_changed.connect(_queue_redraw_board)
	redraw_board()


## Coalesce bursts of score events into one rebuild per frame.
func _queue_redraw_board() -> void:
	if _pending:
		return
	_pending = true
	redraw_board.call_deferred()


func redraw_board() -> void:
	_pending = false
	for child in _root.get_children():
		child.queue_free()

	var sessions := SessionManager.session_count()
	var running := SessionManager.session_active
	var finished := SessionManager.session_finished

	_label(_root, "Your progress", SIZE_TITLE, HEADING)
	var subtitle := "Participant %s  ·  " % Settings.participant_id
	if sessions == 0 and not finished:
		subtitle += "first session"
	else:
		subtitle += "%d session%s so far" % [sessions, "" if sessions == 1 else "s"]
	_label(_root, subtitle, SIZE_SMALL, DIM)

	# Header
	var header := _header_row()
	_cell(header, "Test", COL_NAME, SIZE_SMALL, DIM)
	_cell(header, "Last time", COL_NUM, SIZE_SMALL, DIM)
	_cell(header, "Today" if (running or finished) else "", COL_NUM, SIZE_SMALL, DIM)
	_cell(header, "Change" if (running or finished) else "", COL_NUM, SIZE_SMALL, DIM)

	for row: Dictionary in SessionManager.board_rows():
		_add_test_row(row)

	_root.add_child(_spacer(6))
	for line in _footer_lines():
		_label(_root, line[0], SIZE_SMALL, line[1])
	changed.emit()


func _add_test_row(row: Dictionary) -> void:
	var is_focus: bool = row["is_focus"]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FOCUS_BG if is_focus else ROW_BG
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	if is_focus:
		style.border_color = WARN
		style.set_border_width_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	column.add_child(line)

	var name_text := str(row["name"])
	if is_focus:
		name_text += "  » FOCUS"
	_cell(line, name_text, COL_NAME, SIZE_BODY, WARN if is_focus else TEXT)

	var last: Variant = row["last"]
	var today: Variant = row["today"]
	var change: Variant = row["change"]
	_cell(line, _fmt(last), COL_NUM, SIZE_BODY, _score_color(last) if last != null else DIM)
	_cell(line, _fmt(today), COL_NUM, SIZE_BODY, _score_color(today) if today != null else DIM)
	_cell(line, _fmt_change(change), COL_NUM, SIZE_BODY, _change_color(change))

	# Bar: today's score if there is one, otherwise last time's.
	var shown: Variant = today if today != null else last
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = clampf(float(shown), 0.0, 100.0) if shown != null else 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#34343c")
	bar_bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = _score_color(shown) if shown != null else DIM
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", fill)
	column.add_child(bar)


func _footer_lines() -> Array:
	var focus: Dictionary = SessionManager.current_focus
	var lines: Array = []
	match str(focus.get("reason", "")):
		"lowest_average":
			lines.append(["Today's focus: %s -- your lowest average over the last %d session%s (%d out of 100)." % [
				focus.get("name", ""), int(focus.get("sessions_considered", 1)),
				"" if int(focus.get("sessions_considered", 1)) == 1 else "s",
				int(round(float(focus.get("average", 0.0)))),
			], WARN])
			var hints: Array = focus.get("hints", [])
			if not hints.is_empty():
				lines.append(["Tip: " + str(hints[0]), TEXT])
		"all_above_threshold":
			lines.append(["Every test is %d or above. No focus today -- explore freely." % int(SessionManager.FOCUS_THRESHOLD), GOOD])
		_:
			lines.append(["After your first session, the test with the lowest score becomes your focus.", DIM])
	if SessionManager.session_finished:
		var next: Dictionary = SessionManager.get_last_summary().get("next_focus", {})
		if str(next.get("test", "")) != "":
			lines.append(["Next time, focus on: %s." % next.get("name", ""), HEADING])
	return lines


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

func _scaled(size: int) -> int:
	return int(round(float(size) * Settings.text_scale))


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", _scaled(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(label)
	return label


func _header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_left", 18)
	wrapper.add_theme_constant_override("margin_right", 18)
	wrapper.add_child(row)
	_root.add_child(wrapper)
	return row


func _cell(parent: Node, text: String, width: int, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.clip_text = true
	label.add_theme_font_size_override("font_size", _scaled(size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	parent.add_child(label)


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _fmt(value: Variant) -> String:
	if value == null:
		return "—"
	return "%d" % int(round(float(value)))


## The arrow and the words carry the meaning; colour only reinforces it.
func _fmt_change(value: Variant) -> String:
	if value == null:
		return ""
	var v := float(value)
	if absf(v) < 0.5:
		return "= same"
	if v > 0.0:
		return "↑ +%d" % int(round(v))
	return "↓ %d" % int(round(v))


func _change_color(value: Variant) -> Color:
	if value == null:
		return DIM
	var v := float(value)
	if v > 0.5:
		return GOOD
	if v < -0.5:
		return WARN
	return DIM


func _score_color(value: Variant) -> Color:
	var v := float(value)
	if v >= 80.0:
		return GOOD
	if v >= 50.0:
		return WARN
	return LOW
