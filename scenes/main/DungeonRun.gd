class_name DungeonRun
extends Node3D
## Phase 2 gray-box run: one empty arena with training dummies, the committed
## hero, the D3 camera, input and the run HUD. Rooms, waves, boons, pause and
## the run summary arrive in Phase 3.

const HERO_SCENE := preload("res://scenes/actors/HeroActor.tscn")

## Used when the scene is run directly (no hero committed from the Hub yet).
@export var dev_hero: String = "BRUTE"

@onready var arena: Node3D = $Arena
@onready var camera_rig: CameraRig = $CameraRig
@onready var hero_input: HeroInput = $HeroInput
@onready var hud: RunHud = $HUD/RunHud

var hero: HeroController


func _ready() -> void:
	var id := GameState.active_hero
	if id == "":
		id = dev_hero
		GameState.begin_run(id, int(Time.get_unix_time_from_system()))
	hero = HERO_SCENE.instantiate()
	hero.name = "Hero"
	arena.add_child(hero)
	hero.global_position = ($Arena/HeroSpawn as Node3D).global_position
	hero.setup(id)
	camera_rig.follow(hero)
	hero_input.bind(hero, hud.stick)
	hud.bind(hero)
