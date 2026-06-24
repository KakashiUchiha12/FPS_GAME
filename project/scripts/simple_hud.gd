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
var last_health: float = 100.0

# --- Reload HUD Variables ---
var is_reloading_hud: bool = false
var reload_total_time: float = 0.0
var reload_time_left: float = 0.0
var reload_progress: ProgressBar = null


func _ready() -> void:
	reload_label.visible = false
	
	# Instantiate reload progress bar programmatically
	reload_progress = ProgressBar.new()
	reload_progress.size = Vector2(160, 16)
	reload_progress.show_percentage = false
	reload_progress.visible = false
	
	# Center it below the center of the screen
	reload_progress.set_anchors_preset(Control.PRESET_CENTER)
	reload_progress.grow_horizontal = Control.GROW_DIRECTION_BOTH
	reload_progress.grow_vertical = Control.GROW_DIRECTION_BOTH
	reload_progress.position = Vector2(-80, 50)
	
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	style_bg.border_width_left = 1
	style_bg.border_width_right = 1
	style_bg.border_width_top = 1
	style_bg.border_width_bottom = 1
	style_bg.border_color = Color(0.3, 0.3, 0.3, 0.8)
	
	var style_fg = StyleBoxFlat.new()
	style_fg.bg_color = Color(0.2, 0.6, 1.0, 0.95)
	
	reload_progress.add_theme_stylebox_override("background", style_bg)
	reload_progress.add_theme_stylebox_override("fill", style_fg)
	add_child(reload_progress)
	
	# Instantiate Hitmarker programmatically
	var hitmarker_script = load("res://scripts/hitmarker.gd")
	if hitmarker_script:
		var hm = Control.new()
		hm.set_script(hitmarker_script)
		add_child(hm)
		hitmarker_ref = hm
		
	# Instantiate DamageOverlay programmatically
	var damage_overlay_script = load("res://scripts/damage_overlay.gd")
	if damage_overlay_script:
		var overlay = Control.new()
		overlay.name = "DamageOverlay"
		overlay.set_script(damage_overlay_script)
		add_child(overlay)
		move_child(overlay, 0) # Render behind crosshair/labels

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
		last_health = player.health
		player.health_changed.connect(_on_health_changed)
		player.aim_changed.connect(_on_aim_changed)
		player.ammo_changed.connect(_on_ammo_changed)
		player.reloading_started.connect(_on_reloading)
		player.enemy_hit.connect(_on_enemy_hit)
		player.reload_cancelled.connect(_on_reload_cancelled)
		
		# Set initial weapon HUD readings
		if player.weapons.size() > player.current_weapon_index:
			var w = player.weapons[player.current_weapon_index]
			_on_ammo_changed(w.current_ammo, w.reserve_ammo)

	# Connect Level Manager upgrades
	var gm = get_parent().get_node_or_null("LevelManager")
	if gm:
		gm.upgrade_unlocked.connect(_on_upgrade_unlocked)


func _process(delta: float) -> void:
	if is_reloading_hud:
		reload_time_left -= delta
		if reload_time_left > 0:
			var progress_pct = (1.0 - (reload_time_left / reload_total_time)) * 100.0
			if reload_progress:
				reload_progress.value = progress_pct
		else:
			_hide_reload_ui()


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.value = (current / maximum) * 100.0
	
	if current < last_health:
		var diff = last_health - current
		var pct = diff / maximum
		var overlay = get_node_or_null("DamageOverlay")
		if overlay:
			overlay.trigger_hit(pct)
			
	last_health = current


func _on_aim_changed(aiming: bool) -> void:
	crosshair.visible = not aiming


func _on_ammo_changed(current: int, reserve: int) -> void:
	var active_weapon_name := "Weapon"
	if player and player.weapons.size() > player.current_weapon_index:
		var w = player.weapons[player.current_weapon_index]
		active_weapon_name = w.weapon_name
	ammo_label.text = "%s: %d  /  %d" % [active_weapon_name, current, reserve]


func _on_reloading(reload_time: float) -> void:
	is_reloading_hud = true
	reload_total_time = reload_time
	reload_time_left = reload_time
	reload_label.visible = true
	if reload_progress:
		reload_progress.value = 0.0
		reload_progress.visible = true


func _on_reload_cancelled() -> void:
	_hide_reload_ui()


func _hide_reload_ui() -> void:
	is_reloading_hud = false
	reload_label.visible = false
	if reload_progress:
		reload_progress.visible = false



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
