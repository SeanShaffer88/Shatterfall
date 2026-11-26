class_name HubUI
extends Control
## Hub screen (landscape, D1; safe margins ≥ 48 px). Built in code on top of
## MainHub's API: hero cards (left), Stage Briefing (center), Reliquary and
## Forge buttons, "Enter the Nave" (bottom-right), the Forge tome overlay
## (AD8), a bark line (D43) and the AD10 stained-glass wash.

const M := 48.0
const CRIMSON := Color("#D92638")
const BG := Color("#121318")
const AMBER := Color("#E8912D")

var hub: MainHub
var cards: Dictionary = {}                 # hero -> Button
var briefing_label: Label
var glass_label: Label
var window_label: Label
var restore_button: Button
var forge_button: Button
var enter_button: Button
var forge_panel: PanelContainer
var forge_box: VBoxContainer
var forge_note: Label
var bark_label: Label
var wash: ColorRect

var _bark_left: float = 0.0


func bind(owner_hub: MainHub) -> void:
	hub = owner_hub
	# Full-screen root: anchors AND offsets (not just anchors), so centre- and
	# bottom-anchored children never collapse to a 0×0 parent.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	hub.hub_changed.connect(refresh)


func _build() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(M, M)
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	glass_label = _label(30)
	col.add_child(glass_label)
	for h in MainHub.HEROES:
		var b := Button.new()
		b.name = "Card_" + h
		b.custom_minimum_size = Vector2(620, 170)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 24)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var hero_id := h
		b.pressed.connect(func() -> void: hub.select_hero(hero_id))
		col.add_child(b)
		cards[h] = b
	briefing_label = _label(26)
	briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing_label.position = Vector2(M + 680, M)
	briefing_label.size = Vector2(900, 620)
	add_child(briefing_label)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom.offset_left = -1300
	bottom.offset_right = -M
	bottom.offset_top = -M - 150
	bottom.offset_bottom = -M
	bottom.alignment = BoxContainer.ALIGNMENT_END
	add_child(bottom)
	var win_col := VBoxContainer.new()
	window_label = _label(22)
	window_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	window_label.custom_minimum_size = Vector2(420, 0)
	win_col.add_child(window_label)
	restore_button = _button("Restore window")
	restore_button.pressed.connect(func() -> void: hub.restore_window())
	win_col.add_child(restore_button)
	bottom.add_child(win_col)
	forge_button = _button("Forge")
	forge_button.pressed.connect(func() -> void:
		if not hub.forge_locked():
			forge_panel.visible = not forge_panel.visible
			refresh())
	bottom.add_child(forge_button)
	enter_button = _button("Enter the Nave")
	enter_button.add_theme_color_override("font_color", AMBER)
	enter_button.pressed.connect(func() -> void: hub.commit_run())
	bottom.add_child(enter_button)
	_build_forge()
	bark_label = _label(32)
	bark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bark_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bark_label.offset_left = -600
	bark_label.offset_right = 600
	bark_label.offset_top = -M - 260
	bark_label.offset_bottom = -M - 190
	bark_label.visible = false
	add_child(bark_label)
	wash = ColorRect.new()
	wash.name = "Wash"
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0.56, 0.31, 0.83, 0.0)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)


## AD8: the Forge as an open illuminated tome — left page the weapon and its
## evolution runes, right page the fodder with one-tap Absorb / Salvage.
func _build_forge() -> void:
	forge_panel = PanelContainer.new()
	forge_panel.name = "ForgeTome"
	forge_panel.set_anchors_preset(Control.PRESET_CENTER)
	forge_panel.offset_left = -900
	forge_panel.offset_right = 900
	forge_panel.offset_top = -400
	forge_panel.offset_bottom = 330
	var page := StyleBoxFlat.new()
	page.bg_color = Color("#2B2219")
	page.border_color = Color("#8A6A3A")
	page.set_border_width_all(6)
	page.set_content_margin_all(28)
	forge_panel.add_theme_stylebox_override("panel", page)
	forge_panel.visible = false
	add_child(forge_panel)
	var scroll := ScrollContainer.new()
	forge_panel.add_child(scroll)
	forge_box = VBoxContainer.new()
	forge_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_box.add_theme_constant_override("separation", 10)
	scroll.add_child(forge_box)
	forge_note = _label(24)
	forge_note.add_theme_color_override("font_color", AMBER)


func refresh() -> void:
	if hub == null:
		return
	var n := GameState.next_window()
	glass_label.text = "Glass %d   ·   Vespera essence %d   ·   Windows %d / %d" % [GameState.glass,
		GameState.inventory.essence_count("VESPERA_ESSENCE"), GameState.windows_restored, GameState.windows().size()]
	for h in cards:
		var c := hub.hero_card(h)
		var text := "%s%s\n%s · Stage %d · Lv %d · ATK %d%s" % [h.capitalize(), "  ★" if c["star"] else "",
			c["weapon"], c["stage"], c["level"], c["atk"], ""]
		if c["grudge"] != "":
			text += "\n%s — %s" % [c["grudge"], c["tip"]]
		cards[h].text = text
		cards[h].modulate = Color.WHITE if h == hub.selected_hero else Color(1, 1, 1, 0.6)
	var b := hub.briefing()
	var lines: PackedStringArray = ["%s — %s" % [b["stage"], hub.selected_hero.capitalize()], b["hazards"], ""]
	for s in b["stars"]:
		lines.append("%s %s (%s): %s" % ["★" if s["earned"] else "☆", s["name"], str(s["hero"]).capitalize(), s["condition"]])
	lines.append("")
	lines.append(b["echo_text"])
	lines.append("Vespera's adaptation: %s%s" % [b["adaptation"], "" if b["adaptation_tip"] == "" else " — " + b["adaptation_tip"]])
	briefing_label.text = "\n".join(lines)
	if n.is_empty():
		window_label.text = "The Reliquary is whole again."
		restore_button.disabled = true
	else:
		window_label.text = "Next: %s — %d Glass%s\n%s" % [n["name"], int(n["glass"]),
			" + Vespera essence" if int(n["essence"]) > 0 else "", n["unlock"]["text"]]
		restore_button.disabled = GameState.glass < int(n["glass"])
	forge_button.text = "Forge" if not hub.forge_locked() else "Forge (locked)"
	forge_button.tooltip_text = "" if not hub.forge_locked() else "The Forge wakes once Vespera falls."
	if forge_panel.visible:
		_fill_forge()


func _fill_forge() -> void:
	for c in forge_box.get_children():
		if c != forge_note:
			c.queue_free()
	if forge_note.get_parent() == null:
		forge_box.add_child(forge_note)
	var classes: Array = GameState.heroes_data["heroes"][hub.selected_hero]["weapon_classes"]
	if classes.size() > 1:
		var tabs := HBoxContainer.new()
		for cls in classes:
			var tb := _button(str(cls).capitalize())
			var wc: String = cls
			tb.pressed.connect(func() -> void: hub.select_class(wc))
			tabs.add_child(tb)
		forge_box.add_child(tabs)
	var items := hub.forge_items()
	var main: Weapon = items["main"]
	var runes := hub.rune_state(main)
	var head := _label(30)
	head.text = "%s — Stage %d, Lv %d (%d / %d XP), ATK %d" % [hub.weapon_name(main), main.evo_stage, main.level,
		main.xp, GameState.forge.xp_to_next(main.level), roundi(GameState.forge.atk_eff(main))]
	forge_box.add_child(head)
	var rune_line := _label(26)
	if runes["final"]:
		rune_line.text = "◆ Fully evolved"
	else:
		rune_line.text = "Runes:  %s Level   %s Shards   %s%s" % ["◆" if runes["level"] else "◇", "◆" if runes["shards"] else "◇",
			("◆" if runes["essence"] else "◇") + " Essence" if runes["needs_essence"] else "", "   ● reliquary orb" if runes["stage3_orb"] else ""]
	forge_box.add_child(rune_line)
	var evo := _button("Evolve")
	evo.disabled = not runes["available"]
	evo.pressed.connect(func() -> void: hub.evolve())
	forge_box.add_child(evo)
	for w in items["absorbable"]:
		forge_box.add_child(_fodder_row(w, true))
	for w in items["salvage_only"]:
		forge_box.add_child(_fodder_row(w, false))


func _fodder_row(w: Weapon, absorbable: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(22)
	l.custom_minimum_size = Vector2(900, 0)
	l.text = "%s  · Rarity %d · Lv %d%s" % [hub.weapon_name(w), w.rarity, w.level, "" if absorbable else "  — Not usable, salvage only"]
	row.add_child(l)
	var uid := w.uid
	if absorbable:
		var a := _button("Absorb")
		a.pressed.connect(func() -> void:
			var r := hub.absorb(uid)
			forge_note.text = r.get("error", "") if not r.get("ok", false) else "")
		row.add_child(a)
	var s := _button("Salvage")
	s.pressed.connect(func() -> void: hub.salvage(uid))
	row.add_child(s)
	return row


func show_bark(speaker: String, text: String) -> void:
	if forge_panel.visible:
		return                               # never over the Forge tome
	bark_label.text = ("Vespera: " if speaker == "VESPERA" else "") + text
	bark_label.visible = true
	_bark_left = float(GameState.barks_data["rules"]["duration"])


func set_wash(amount: float) -> void:
	wash.color.a = clampf(amount, 0.0, 1.0) * 0.85


func _process(delta: float) -> void:
	if _bark_left > 0.0:
		_bark_left -= delta
		bark_label.visible = _bark_left > 0.0


func _label(size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 110)
	b.add_theme_font_size_override("font_size", 30)
	return b
