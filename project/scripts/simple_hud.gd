extends CanvasLayer

# Simple crosshair + ammo counter + health bar
# Attach to a CanvasLayer node in the level

@onready var ammo_label: Label = $AmmoLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var reload_label: Label = $ReloadLabel
@onready var crosshair: Control = $Crosshair

var player: Node = null
var hitmarker_ref: Control = null
var upgrade_label: Label = null

func _ready() -> void:
	reload_label.visible = false
	
	# Instantiate Hitmarker programmatically
	var hitmarker_script = load("res://scripts/hitmarker.gd")
	if hitmarker_script:
		var hm = Control.new()
		hm.set_script(hitmarker_script)
		add_child(hm)
		hitmarker_ref = hm

	# Instantiate Level Up Upgrade Label programmatically
	upgrade_label = Label.new()
	upgrade_label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	upgrade_label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	upgrade_label.set_anchors_preset(Control.PRESET_CENTER)
	upgrade_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	upgrade_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	upgrade_label.add_theme_font_size_override("font_size", 34)
	upgrade_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4, 1.0)) # green glow
	upgrade_label.add_theme_constant_override("outline_size", 12)
	upgrade_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	upgrade_label.text = ""
	upgrade_label.modulate.a = 0.0
	add_child(upgrade_label)

	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(_on_health_changed)
		player.aim_changed.connect(_on_aim_changed)
		player.ammo_changed.connect(_on_ammo_changed)
		player.reloading_started.connect(_on_reloading)
		player.enemy_hit.connect(_on_enemy_hit)
		
		# Set initial weapon HUD readings
		if player.weapons.size() > player.current_weapon_index:
			var w = player.weapons[player.current_weapon_index]
			_on_ammo_changed(w.current_ammo, w.reserve_ammo)

	# Connect Level Manager upgrades
	var gm = get_parent().get_node_or_null("LevelManager")
	if gm:
		gm.upgrade_unlocked.connect(_on_upgrade_unlocked)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.value = (current / maximum) * 100.0


func _on_aim_changed(aiming: bool) -> void:
	crosshair.visible = not aiming


func _on_ammo_changed(current: int, reserve: int) -> void:
	ammo_label.text = "%d  /  %d" % [current, reserve]


func _on_reloading(reload_time: float) -> void:
	reload_label.visible = true
	await get_tree().create_timer(reload_time).timeout
	reload_label.visible = false


func _on_enemy_hit() -> void:
	if hitmarker_ref:
		hitmarker_ref.show_hit()


func _on_upgrade_unlocked(upgrade_text: String) -> void:
	if not upgrade_label:
		return
	upgrade_label.text = "LEVEL UP!\n" + upgrade_text
	upgrade_label.modulate.a = 0.0
	
	# Position slightly above crosshair center
	upgrade_label.position = Vector2(0, -140)
	
	var tween := create_tween()
	tween.tween_property(upgrade_label, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	
	await get_tree().create_timer(3.0).timeout
	var fade := create_tween()
	fade.tween_property(upgrade_label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
