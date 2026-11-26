class_name RunHud
extends Control
## Landscape run HUD (D1, §3.1): stats top-left, wave info top-right, pause in
## the top-right corner, Vespera's health bar top-center, virtual stick
## bottom-left, 3 skill buttons bottom-right. Overlays: boon draft (§2F),
## pause menu (D29) and run summary (D10). Safe margins ≥ 48 px.
## Overlays are built in code and keep working while the tree is paused.

const SAFE_MARGIN := 48.0
const CRIMSON := Color("#D92638")
const PANEL_BG := Color("#121318")

@onready var stats: Label = $Stats
@onready var stick: VirtualStick = $VirtualStick
@onready var buttons: Array[SkillButton] = [$Skill1, $Skill2, $Skill3]

var hero: HeroController
var run: DungeonRun
var wave_info: Label
var pause_button: Button
var boss_bar: ProgressBar
var boss_label: Label
var draft_panel: PanelContainer
var draft_buttons: Array[Button] = []
var pause_panel: PanelContainer
var summary_panel: PanelContainer
var summary_label: Label

var _boss: BossVespera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top_right()
	_build_boss_bar()
	_build_draft()
	_build_pause()
	_build_summary()


func bind(target_hero: HeroController) -> void:
	hero = target_hero
	for b in buttons:
		b.bind(hero.skills)


func bind_run(target_run: DungeonRun) -> void:
	run = target_run


func _process(_delta: float) -> void:
	if hero == null:
		return
	var line := "%s   HP %d / %d" % [hero.hero_id, hero.hp, hero.max_hp]
	if hero.hero_class == HeroController.HeroClass.BRUTE:
		line += "   Guard %d%%" % roundi(hero.guard_fraction() * 30.0)
	elif hero.hero_class == HeroController.HeroClass.MAGI:
		line += "   Barrier %s" % ("UP" if hero.barrier_up else "…")
	elif hero.hero_class == HeroController.HeroClass.ROGUE:
		line += "   %s" % ("DAGGERS" if hero.rogue_mode == HeroController.RogueMode.DAGGERS else "BOW")
	stats.text = line
	if run != null:
		wave_info.text = wave_text()
	if _boss != null and is_instance_valid(_boss):
		boss_bar.value = _boss.hp
		boss_label.text = "VESPERA%s" % ("" if _boss.adaptation_id() == "" else "  ·  " + str(_boss.adaptation.get("name", "")))


## A touch on open ground (not a HUD control or overlay) conducts an Echo cue (D41).
func _input(event: InputEvent) -> void:
	if run == null or not (event is InputEventScreenTouch) or not event.pressed:
		return
	if is_over_control(event.position) or not run.echo_player.has_live_cue():
		return
	if run.conduct_at_screen(event.position):
		get_viewport().set_input_as_handled()


func is_over_control(pos: Vector2) -> bool:
	if draft_panel.visible or pause_panel.visible or summary_panel.visible:
		return true
	var controls: Array[Control] = [stick, pause_button]
	controls.append_array(buttons)
	for c in controls:
		if c.visible and c.get_global_rect().has_point(pos):
			return true
	return false


func wave_text() -> String:
	match run.phase:
		DungeonRun.Phase.BOSS_INTRO, DungeonRun.Phase.BOSS:
			return "Vespera"
		DungeonRun.Phase.ENDED:
			return run.result.capitalize()
		DungeonRun.Phase.DRAFT:
			return "Choose a boon"
		DungeonRun.Phase.ROOM_CLEARED:
			return "Room %d clear — onward" % (run.room + 1)
	return "Room %d / %d   ·   Wave %d / %d" % [run.room + 1, StageLayout.ROOM_COUNT,
		maxi(run.wave, 0) + 1, run.waves_in(run.room).size()]


# --- Overlays used by DungeonRun ----------------------------------------------------

func show_draft(offers: Array) -> void:
	for i in draft_buttons.size():
		var b := draft_buttons[i]
		b.visible = i < offers.size()
		if b.visible:
			b.text = "%s\n%s" % [offers[i]["name"], _boon_text(offers[i])]
	draft_panel.visible = true


func hide_draft() -> void:
	draft_panel.visible = false


func show_pause(on: bool) -> void:
	pause_panel.visible = on


func show_boss(boss: BossVespera) -> void:
	_boss = boss
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp
	boss_bar.visible = true
	boss_label.visible = true


func show_summary(s: Dictionary) -> void:
	draft_panel.visible = false
	pause_panel.visible = false
	boss_bar.visible = false
	boss_label.visible = false
	summary_label.text = summary_text(s)
	summary_panel.visible = true


## Plain-English run summary (D10): stars (victory only), drops kept, forge
## progress retained, boons lost.
static func summary_text(s: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append({"VICTORY": "Vespera falls.", "DEFEAT": "You fell.", "ABANDONED": "Run abandoned."}.get(s["result"], s["result"]))
	var st: Dictionary = s["star"]
	if s["result"] == "VICTORY":
		lines.append("%s ★  %s" % [st["name"], "earned" if s["star_earned"] else "not earned"])
	else:
		lines.append("Stars are only earned on a clear.")
	if not s["star_earned"]:
		lines.append("  progress: %s / %s" % [_fmt(st["value"], st["metric"]), _fmt(st["threshold"], st["metric"])])
	lines.append("Drops kept: %d weapon(s)%s" % [s["drops"].size(), "  +  Vespera essence" if s["essence"] != "" else ""])
	lines.append("Forge progress kept.")
	if not s["boons_lost"].is_empty():
		lines.append("Boons lost: %s" % ", ".join(PackedStringArray(s["boons_lost"])).replace("_", " ").capitalize())
	if s["adaptation"] != "":
		lines.append("Vespera adapts: %s" % s["adaptation"])
	return "\n".join(lines)


static func _fmt(v, metric: String) -> String:
	if metric == "guard_uptime_fraction":
		return "%d%%" % roundi(float(v) * 100.0)
	return str(int(v))


static func _boon_text(b: Dictionary) -> String:
	var v := float(b["value"])
	match str(b["effect"]):
		"damage_mult":
			return "+%d%% damage" % roundi(v * 100)
		"max_hp_and_heal":
			return "+%d max HP, heal %d" % [int(v), int(v)]
		"move_and_attack_speed":
			return "+%d%% move and attack speed" % roundi(v * 100)
		"projectile_damage_taken_mult":
			return "%d%% less projectile damage" % roundi(v * 100)
		"once_heal_below":
			return "Once: below %d%% HP, heal %d%%" % [roundi(float(b["threshold"]) * 100), roundi(v * 100)]
		"cooldown_mult":
			return "Skill cooldowns −%d%%" % roundi(v * 100)
	return ""


# --- Construction ---------------------------------------------------------------------

func _build_top_right() -> void:
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "II"
	pause_button.add_theme_font_size_override("font_size", 40)
	pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -SAFE_MARGIN - 110.0
	pause_button.offset_right = -SAFE_MARGIN
	pause_button.offset_top = SAFE_MARGIN
	pause_button.offset_bottom = SAFE_MARGIN + 90.0
	pause_button.pressed.connect(func() -> void:
		if run != null:
			run.set_paused(true))
	add_child(pause_button)
	wave_info = Label.new()
	wave_info.name = "WaveInfo"
	wave_info.add_theme_font_size_override("font_size", 34)
	wave_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wave_info.offset_left = -SAFE_MARGIN - 110.0 - 24.0 - 900.0
	wave_info.offset_right = -SAFE_MARGIN - 110.0 - 24.0
	wave_info.offset_top = SAFE_MARGIN
	wave_info.offset_bottom = SAFE_MARGIN + 60.0
	add_child(wave_info)


func _build_boss_bar() -> void:
	boss_label = Label.new()
	boss_label.name = "BossLabel"
	boss_label.add_theme_font_size_override("font_size", 28)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_label.offset_left = -500.0
	boss_label.offset_right = 500.0
	boss_label.offset_top = SAFE_MARGIN + 70.0
	boss_label.offset_bottom = SAFE_MARGIN + 110.0
	boss_label.visible = false
	add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.name = "BossBar"
	boss_bar.show_percentage = false
	boss_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_bar.offset_left = -500.0
	boss_bar.offset_right = 500.0
	boss_bar.offset_top = SAFE_MARGIN + 115.0
	boss_bar.offset_bottom = SAFE_MARGIN + 145.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = CRIMSON
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_bar.visible = false
	add_child(boss_bar)


func _panel(node_name: String, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -560.0
	panel.offset_right = 560.0
	panel.offset_top = -330.0
	panel.offset_bottom = 330.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(PANEL_BG, 0.94)
	bg.border_color = CRIMSON
	bg.set_border_width_all(3)
	bg.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", bg)
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 44)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	return box


func _big_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 120)
	b.add_theme_font_size_override("font_size", 32)
	return b


func _build_draft() -> void:
	var box := _panel("BoonDraft", "Choose one boon")
	draft_panel = box.get_parent()
	for i in 3:
		var b := _big_button("")
		b.name = "Boon%d" % (i + 1)
		var idx := i
		b.pressed.connect(func() -> void:
			if run != null:
				run.pick_boon(idx))
		box.add_child(b)
		draft_buttons.append(b)


func _build_pause() -> void:
	var box := _panel("PauseMenu", "Paused")
	pause_panel = box.get_parent()
	var resume := _big_button("Resume")
	resume.name = "Resume"
	resume.pressed.connect(func() -> void:
		if run != null:
			run.set_paused(false))
	box.add_child(resume)
	var abandon := _big_button("Abandon run")
	abandon.name = "Abandon"
	abandon.pressed.connect(func() -> void:
		if run != null:
			run.abandon())
	box.add_child(abandon)
	var note := Label.new()
	note.text = "Abandoning keeps every drop from cleared rooms; boons are lost."
	note.add_theme_font_size_override("font_size", 24)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)


func _build_summary() -> void:
	var box := _panel("Summary", "Run summary")
	summary_panel = box.get_parent()
	summary_label = Label.new()
	summary_label.name = "SummaryText"
	summary_label.add_theme_font_size_override("font_size", 30)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(summary_label)
	var cont := _big_button("Continue")
	cont.name = "Continue"
	cont.pressed.connect(func() -> void:
		if run != null:
			run.restart())
	box.add_child(cont)
