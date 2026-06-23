extends Control

class BloodDrop:
	var pos: Vector2
	var radius: float
	var color: Color
	
	func _init(p: Vector2, r: float, c: Color):
		pos = p
		radius = r
		color = c

var drops: Array[BloodDrop] = []
var flash_alpha: float = 0.0

func _ready() -> void:
	# Stretch to fill whole viewport
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_generate_border_drops()

func _generate_border_drops():
	# Generate static border blood drops that represent the vignette shape
	var screen_size = get_viewport_rect().size
	if screen_size.x < 100 or screen_size.y < 100:
		screen_size = Vector2(1920, 1080) # Fallback if viewport not ready
		
	var edge_count = 25 # Reduced from 60 for better rendering performance
	drops.clear()
	
	for i in range(edge_count):
		var side = randi() % 4
		var pos = Vector2.ZERO
		match side:
			0: # Top
				pos = Vector2(randf() * screen_size.x, randf() * 120.0)
			1: # Bottom
				pos = Vector2(randf() * screen_size.x, screen_size.y - randf() * 120.0)
			2: # Left
				pos = Vector2(randf() * 120.0, randf() * screen_size.y)
			3: # Right
				pos = Vector2(screen_size.x - randf() * 120.0, randf() * screen_size.y)
				
		var radius = randf_range(50.0, 150.0)
		var r = randf_range(0.35, 0.6)
		var color = Color(r, 0.0, 0.0, randf_range(0.35, 0.65))
		drops.append(BloodDrop.new(pos, radius, color))
		
	queue_redraw()

func trigger_hit(damage_percent: float):
	var screen_size = get_viewport_rect().size
	# Spawn a main splat center somewhere on the screen
	var splat_center = Vector2(
		randf_range(screen_size.x * 0.15, screen_size.x * 0.85),
		randf_range(screen_size.y * 0.15, screen_size.y * 0.85)
	)
	
	# Add the main splat drop
	drops.append(BloodDrop.new(splat_center, randf_range(35.0, 75.0), Color(0.45, 0.0, 0.0, 0.8)))
	
	# Add satellite droplets around the splat (reduced from 5-10 to 3-5 for performance)
	for i in range(randi_range(3, 5)):
		var angle = randf() * TAU
		var dist = randf_range(20.0, 100.0)
		var drop_pos = splat_center + Vector2(cos(angle), sin(angle)) * dist
		drops.append(BloodDrop.new(drop_pos, randf_range(6.0, 18.0), Color(0.4, 0.0, 0.0, 0.8)))
		
	# Cap memory/performance
	if drops.size() > 80: # Reduced from 180 to 80
		drops = drops.slice(drops.size() - 80)
		
	# Set flash alpha based on damage percentage
	flash_alpha = clamp(flash_alpha + damage_percent * 2.0, 0.0, 0.9)
	queue_redraw() # Re-render static geometry buffer since list changed

func _process(delta: float) -> void:
	# Fade out flash alpha
	if flash_alpha > 0.0:
		flash_alpha = max(0.0, flash_alpha - delta * 1.5)
		
	# Check player health for low-health vignette warning
	var hud = get_parent()
	var persistent_alpha = 0.0
	if hud and "player" in hud and hud.player:
		var health_pct = hud.player.health / hud.player.max_health
		if health_pct < 0.35:
			# Pulse frequency increases as health decreases
			var pulse_speed = 4.0 + (1.0 - health_pct / 0.35) * 8.0
			var pulse = (sin(Time.get_ticks_msec() * 0.001 * pulse_speed) + 1.0) * 0.5
			persistent_alpha = (1.0 - health_pct / 0.35) * (0.2 + pulse * 0.25)
			
	# Update modulate.a on the CanvasItem directly.
	# Godot caches the drawn circles, so changing modulate.a does not rebuild geometry.
	var target_alpha = clamp(flash_alpha + persistent_alpha, 0.0, 1.0)
	if modulate.a != target_alpha:
		modulate.a = target_alpha

func _draw() -> void:
	# Draw all border and hit blood splatters at full alpha (parent modulation handles fading!)
	for drop in drops:
		draw_circle(drop.pos, drop.radius, drop.color)
		
	# Draw screen tint
	var tint_color = Color(0.8, 0.0, 0.0, 0.05)
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), tint_color)
