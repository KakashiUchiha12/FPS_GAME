extends CanvasLayer

# ─────────────────────────────────────────
#  HUD — Heads-Up Display
#  Shows: health, ammo, crosshair, kill feed, objective
# ─────────────────────────────────────────

@onready var health_bar: ProgressBar = $MarginContainer/HUD/BottomLeft/HealthBar
@onready var health_label: Label = $MarginContainer/HUD/BottomLeft/HealthLabel
@onready var ammo_current: Label = $MarginContainer/HUD/BottomRight/AmmoCurrent
@onready var ammo_reserve: Label = $MarginContainer/HUD/BottomRight/AmmoReserve
@onready var reload_bar: ProgressBar = $MarginContainer/HUD/BottomRight/ReloadBar
@onready var crosshair: Control = $Crosshair
@onready var kill_feed: VBoxContainer = $MarginContainer/HUD/TopRight/KillFeed
@onready var objective_label: Label = $MarginContainer/HUD/TopLeft/ObjectiveLabel
@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var hit_marker: TextureRect = $Crosshair/HitMarker

var damage_overlay_alpha: float = 0.0


func _ready() -> void:
	damage_overlay.modulate.a = 0.0
	if hit_marker:
		hit_marker.modulate.a = 0.0


func _process(delta: float) -> void:
	# Fade out damage overlay
	if damage_overlay_alpha > 0:
		damage_overlay_alpha -= delta * 2.0
		damage_overlay.modulate.a = damage_overlay_alpha


func update_health(current: float, maximum: float) -> void:
	health_bar.value = (current / maximum) * 100.0
	health_label.text = "%d / %d" % [int(current), int(maximum)]

	# Flash red damage overlay
	damage_overlay_alpha = 0.4


func update_ammo(current: int, reserve: int) -> void:
	ammo_current.text = str(current)
	ammo_reserve.text = "/ %d" % reserve


func show_reload(reload_time: float) -> void:
	reload_bar.visible = true
	var tween := create_tween()
	tween.tween_property(reload_bar, "value", 100.0, reload_time).from(0.0)
	tween.tween_callback(func(): reload_bar.visible = false)


func show_hit_marker() -> void:
	if hit_marker:
		hit_marker.modulate.a = 1.0
		var tween := create_tween()
		tween.tween_property(hit_marker, "modulate:a", 0.0, 0.15)


func add_kill_feed(killer: String, victim: String) -> void:
	var label := Label.new()
	label.text = "%s  ☠  %s" % [killer, victim]
	label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	kill_feed.add_child(label)
	# Remove after 4 seconds
	await get_tree().create_timer(4.0).timeout
	label.queue_free()


func set_objective(text: String) -> void:
	objective_label.text = "▶ " + text
