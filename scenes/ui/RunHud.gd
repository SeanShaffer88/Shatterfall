class_name RunHud
extends Control
## Landscape run HUD (D1): stats top-left, virtual stick bottom-left, 3 skill
## buttons in a bottom-right arc. Safe margins ≥ 48 px (§3.1). Wave info and
## pause (top-right) arrive with the dungeon loop in Phase 3.

const SAFE_MARGIN := 48.0

@onready var stats: Label = $Stats
@onready var stick: VirtualStick = $VirtualStick
@onready var buttons: Array[SkillButton] = [$Skill1, $Skill2, $Skill3]

var hero: HeroController


func bind(target_hero: HeroController) -> void:
	hero = target_hero
	for b in buttons:
		b.bind(hero.skills)


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
