extends Node3D

# ─────────────────────────────────────────
#  Weapon System — Assault Rifle
#  + Tween shooting recoil animation
#  + Tween reloading animation
#  + Procedural sound effects
#  + Holographic Sight Support
# ─────────────────────────────────────────

const SoundGen := preload("res://scripts/sound_generator.gd")

@export_group("Weapon Stats")
@export var weapon_name: String   = "Assault Rifle"
@export var damage: float         = 25.0
@export var fire_rate: float      = 0.1
@export var mag_size: int         = 30
@export var reserve_ammo: int     = 90
@export var reload_time: float    = 2.0
@export var is_automatic: bool    = true
@export var bullet_spread: float  = 0.012
@export var range_max: float      = 100.0
@export var is_shotgun: bool      = false
@export var shotgun_pellets: int  = 8

# --- State ---
var current_ammo: int
var is_reloading: bool  = false
var fire_timer: float   = 0.0
var reload_timer: float = 0.0
var original_position: Vector3
var original_rotation: Vector3
var flash_timer: float  = 0.0

# --- Tweens ---
var recoil_tween: Tween
var reload_tween: Tween

# --- Cached Audio Streams ---
var _snd_shoot:   AudioStream
var _snd_impact:  AudioStream
var _snd_reload:  AudioStream
var _snd_reload1: AudioStream # procedural fallback
var _snd_reload2: AudioStream # procedural fallback
var _snd_empty:   AudioStream

# --- Node References ---
var muzzle_flash_mesh: MeshInstance3D
var muzzle_light: OmniLight3D
var raycast: RayCast3D

# --- Audio Players ---
var _audio_shoot:  AudioStreamPlayer3D
var _audio_impact: AudioStreamPlayer3D
var _audio_reload: AudioStreamPlayer3D

signal ammo_changed(current: int, reserve: int)
signal reloading_started(time: float)


func _ready() -> void:
	current_ammo    = mag_size
	original_position = position
	original_rotation = rotation

	# Node refs
	raycast          = get_node("../../RayCast3D")
	muzzle_flash_mesh = get_node_or_null("MuzzlePoint/MuzzleFlashMesh")
	muzzle_light      = get_node_or_null("MuzzlePoint/MuzzleLight")

	if muzzle_flash_mesh: muzzle_flash_mesh.visible = false
	if muzzle_light:      muzzle_light.visible = false

	# Load sounds dynamically from folder
	var name_lower := weapon_name.to_lower()
	var shoot_stream: AudioStream = null

	if name_lower.contains("shotgun"):
		shoot_stream = load("res://assets/sounds/shotgun_shoot.mp3")
	elif name_lower.contains("sniper") or name_lower.contains("awp"):
		shoot_stream = load("res://assets/sounds/sniper_shoot.mp3")
	elif name_lower.contains("rocket") or name_lower.contains("launcher"):
		shoot_stream = load("res://assets/sounds/rocket_shoot.mp3")
	elif name_lower.contains("mac10") or name_lower.contains("smg"):
		shoot_stream = load("res://assets/sounds/smg_shoot.mp3")
	elif name_lower.contains("pistol"):
		shoot_stream = load("res://assets/sounds/pistol_shoot.mp3")
	else:
		shoot_stream = load("res://assets/sounds/rifle_shoot.mp3")

	if shoot_stream:
		_snd_shoot = shoot_stream
	else:
		# Fallback to procedural SoundGen
		if name_lower.contains("shotgun"):
			_snd_shoot = SoundGen.gunshot_shotgun()
		elif name_lower.contains("sniper") or name_lower.contains("awp"):
			_snd_shoot = SoundGen.gunshot_sniper()
		elif name_lower.contains("rocket") or name_lower.contains("launcher"):
			_snd_shoot = SoundGen.gunshot_rocket()
		elif name_lower.contains("mac10") or name_lower.contains("smg"):
			_snd_shoot = SoundGen.gunshot_smg()
		elif name_lower.contains("pistol"):
			_snd_shoot = SoundGen.gunshot_pistol()
		else:
			_snd_shoot = SoundGen.gunshot()

	var reload_stream = load("res://assets/sounds/reload.mp3")
	if reload_stream:
		_snd_reload = reload_stream
	else:
		_snd_reload1 = SoundGen.reload_click()
		_snd_reload2 = SoundGen.reload_mag()

	_snd_impact  = SoundGen.impact_spark()
	_snd_empty   = SoundGen.empty_click()

	# Create audio players
	_audio_shoot  = _make_audio_player(4.0)
	_audio_impact = _make_audio_player(0.0)
	_audio_reload = _make_audio_player(0.0)

	ammo_changed.emit(current_ammo, reserve_ammo)


func _make_audio_player(max_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.max_db = max_db
	add_child(p)
	return p


func _process(delta: float) -> void:
	if not visible:
		return
	_handle_fire(delta)
	_handle_reload(delta)
	_handle_flash_timer(delta)


# ── Firing ────────────────────────────────────────────────────────────────────

func _handle_fire(delta: float) -> void:
	if fire_timer > 0:
		fire_timer -= delta
	if is_reloading:
		return

	var should_fire := false
	if is_automatic:
		should_fire = Input.is_action_pressed("shoot")
	else:
		should_fire = Input.is_action_just_pressed("shoot")

	if should_fire and fire_timer <= 0:
		if current_ammo > 0:
			_fire()
		elif not is_reloading and reserve_ammo > 0:
			_start_reload()
		else:
			_audio_shoot.stream = _snd_empty
			_audio_shoot.play()
			fire_timer = fire_rate

	if Input.is_action_just_pressed("reload") and current_ammo < mag_size and reserve_ammo > 0:
		_start_reload()


func _fire() -> void:
	current_ammo -= 1
	fire_timer = fire_rate
	ammo_changed.emit(current_ammo, reserve_ammo)

	_play_shoot_sound()

	# Alert enemies of gunshot
	var player_node = get_parent().get_parent().get_parent()
	if player_node and player_node.has_method("alert_enemies_of_shot"):
		player_node.alert_enemies_of_shot()


	# Raycast (with multiple pellets if shotgun)
	if raycast:
		var pellets: int = shotgun_pellets if is_shotgun else 1
		var hit_registered: bool = false
		
		for i in range(pellets):
			var spread: Vector3 = Vector3(
				randf_range(-bullet_spread, bullet_spread),
				randf_range(-bullet_spread, bullet_spread),
				0.0
			)
			raycast.target_position = Vector3(0, 0, -range_max) + spread
			raycast.force_raycast_update()

			if raycast.is_colliding():
				var hit: Object = raycast.get_collider()
				var point: Vector3 = raycast.get_collision_point()
				var normal: Vector3 = raycast.get_collision_normal()

				var is_rocket := weapon_name.to_lower().contains("rocket") or weapon_name.to_lower().contains("launcher")

				if hit.has_method("take_damage") or is_rocket:
					if is_rocket:
						_apply_explosion_splash(point)
						hit_registered = true
					else:
						hit.take_damage(damage)
						hit_registered = true
						_spawn_damage_number(damage, point)

				_spawn_impact(point, normal)

		if hit_registered:
			# WeaponHolder -> Camera3D -> Head -> Player
			if player_node and player_node.has_method("notify_enemy_hit"):
				player_node.notify_enemy_hit()

	_show_muzzle_flash()
	_apply_recoil_animation()

	# Auto reload sniper and rocket launcher, or any gun when completely empty
	if (weapon_name.to_lower().contains("sniper") or weapon_name.to_lower().contains("awp") or \
		weapon_name.to_lower().contains("rocket") or weapon_name.to_lower().contains("launcher") or \
		current_ammo <= 0) and reserve_ammo > 0:
		get_tree().create_timer(0.15).timeout.connect(func():
			if is_inside_tree() and not is_reloading and current_ammo < mag_size:
				_start_reload()
		)


func _apply_explosion_splash(point: Vector3) -> void:
	_spawn_explosion_vfx(point)
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			var dist = enemy.global_position.distance_to(point)
			var splash_radius := 6.0
			if dist < splash_radius:
				var falloff = 1.0 - (dist / splash_radius)
				var splash_dmg = damage * falloff
				if splash_dmg > 10.0:
					enemy.take_damage(splash_dmg)
					_spawn_damage_number(splash_dmg, enemy.global_position + Vector3.UP)


func _spawn_explosion_vfx(pos: Vector3) -> void:
	var exp_audio := AudioStreamPlayer3D.new()
	exp_audio.stream = _snd_shoot
	exp_audio.max_db = 4.0
	get_tree().root.add_child(exp_audio)
	exp_audio.global_position = pos
	exp_audio.play()

	var particles := CPUParticles3D.new()
	get_tree().root.add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 40
	particles.lifetime = 0.8
	particles.spread = 180.0
	particles.gravity = Vector3(0, 1.5, 0)
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 10.0
	particles.scale_amount_min = 0.1
	particles.scale_amount_max = 0.4
	particles.color = Color(1.0, 0.45, 0.1, 1.0)

	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
		if is_instance_valid(exp_audio):
			exp_audio.queue_free()
	)


func _spawn_damage_number(amount: float, pos: Vector3) -> void:
	var float_scene = load("res://scenes/floating_number.tscn")
	if float_scene:
		var f = float_scene.instantiate()
		f.text = str(int(amount))
		get_tree().root.add_child(f)
		f.global_position = pos


# ── Recoil Animation ──────────────────────────────────────────────────────────

func _apply_recoil_animation() -> void:
	if recoil_tween and recoil_tween.is_running():
		recoil_tween.kill()

	# Snap back on Z and kick up on X rotation
	recoil_tween = create_tween()
	recoil_tween.set_parallel(true)
	recoil_tween.tween_property(self, "position:z", original_position.z + 0.045, 0.035)
	recoil_tween.tween_property(self, "rotation:x", original_rotation.x + 0.08, 0.035)

	# Recover smoothly back to original position
	recoil_tween.chain().set_parallel(true)
	recoil_tween.tween_property(self, "position:z", original_position.z, 0.09).set_ease(Tween.EASE_OUT)
	recoil_tween.tween_property(self, "rotation:x", original_rotation.x, 0.09).set_ease(Tween.EASE_OUT)


# ── Reload Animation ──────────────────────────────────────────────────────────

func _start_reload() -> void:
	if reserve_ammo <= 0 or current_ammo == mag_size or is_reloading:
		return
	is_reloading = true
	reload_timer = reload_time
	reloading_started.emit(reload_time)

	# Play reload sounds
	if _snd_reload:
		_audio_reload.stream = _snd_reload
		_audio_reload.play()
	else:
		_audio_reload.stream = _snd_reload1
		_audio_reload.play()
		_play_reload_part2()

	# Trigger reload animation
	_apply_reload_animation()


func cancel_reload() -> void:
	if is_reloading:
		is_reloading = false
		reload_timer = 0.0
		if reload_tween and reload_tween.is_running():
			reload_tween.kill()
		if _audio_reload:
			_audio_reload.stop()
		position = original_position
		rotation = original_rotation


func _play_reload_part2() -> void:
	await get_tree().create_timer(reload_time * 0.55).timeout
	if is_reloading:
		_audio_reload.stream = _snd_reload2
		_audio_reload.play()



func _apply_reload_animation() -> void:
	if reload_tween and reload_tween.is_running():
		reload_tween.kill()

	reload_tween = create_tween()
	reload_tween.set_ease(Tween.EASE_OUT)
	reload_tween.set_trans(Tween.TRANS_QUAD)

	# 1. Drop gun and tilt it (Mag Out)
	reload_tween.tween_property(self, "position:y", original_position.y - 0.22, reload_time * 0.25)
	reload_tween.parallel().tween_property(self, "rotation:z", original_rotation.z + 0.45, reload_time * 0.25)
	reload_tween.parallel().tween_property(self, "rotation:x", original_rotation.x - 0.18, reload_time * 0.25)

	# 2. Shake slightly (Mag Lock-in)
	reload_tween.tween_property(self, "position:y", original_position.y - 0.20, reload_time * 0.15).set_delay(reload_time * 0.1)
	reload_tween.tween_property(self, "position:y", original_position.y - 0.22, reload_time * 0.1)

	# 3. Pull back up to idle stance
	reload_tween.tween_property(self, "position", original_position, reload_time * 0.3).set_delay(reload_time * 0.1)
	reload_tween.parallel().tween_property(self, "rotation", original_rotation, reload_time * 0.3).set_delay(reload_time * 0.1)


func _handle_reload(delta: float) -> void:
	if not is_reloading:
		return
	reload_timer -= delta
	if reload_timer <= 0:
		var needed := mag_size - current_ammo
		var loaded := mini(needed, reserve_ammo)
		current_ammo += loaded
		reserve_ammo -= loaded
		is_reloading = false
		ammo_changed.emit(current_ammo, reserve_ammo)


# ── Muzzle Flash ──────────────────────────────────────────────────────────────

func _show_muzzle_flash() -> void:
	if muzzle_flash_mesh: muzzle_flash_mesh.visible = true
	if muzzle_light:      muzzle_light.visible = true
	flash_timer = 0.06


func _handle_flash_timer(delta: float) -> void:
	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			if muzzle_flash_mesh: muzzle_flash_mesh.visible = false
			if muzzle_light:      muzzle_light.visible = false


# ── Bullet Impact VFX ─────────────────────────────────────────────────────────

func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var imp_audio := AudioStreamPlayer3D.new()
	imp_audio.stream = _snd_impact
	imp_audio.max_db = -2.0
	get_tree().root.add_child(imp_audio)
	imp_audio.global_position = pos
	imp_audio.play()

	var sparks := CPUParticles3D.new()
	get_tree().root.add_child(sparks)
	sparks.global_position = pos
	sparks.emitting              = true
	sparks.one_shot              = true
	sparks.explosiveness         = 0.95
	sparks.amount               = 18
	sparks.lifetime              = 0.5
	sparks.spread               = 55.0
	sparks.direction            = normal
	sparks.gravity              = Vector3(0, -9.8, 0)
	sparks.initial_velocity_min  = 2.5
	sparks.initial_velocity_max  = 7.0
	sparks.scale_amount_min      = 0.03
	sparks.scale_amount_max      = 0.08
	sparks.color                 = Color(1.0, 0.65, 0.15, 1.0)

	var dot := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	dot.mesh   = sph
	var mat    := StandardMaterial3D.new()
	mat.albedo_color             = Color(1, 0.9, 0.6, 1)
	mat.emission_enabled         = true
	mat.emission                 = Color(1, 0.85, 0.4, 1)
	mat.emission_energy_multiplier = 5.0
	dot.set_surface_override_material(0, mat)
	get_tree().root.add_child(dot)
	dot.global_position = pos

	await get_tree().create_timer(0.9).timeout
	sparks.queue_free()
	dot.queue_free()
	imp_audio.queue_free()


func upgrade_damage(amount: float) -> void:
	damage += amount
	print("Weapon damage upgraded to: ", damage)


func _play_shoot_sound() -> void:
	_audio_shoot.volume_db = 4.0
	if _audio_shoot.playing:
		_audio_shoot.stop()

	_audio_shoot.stream = _snd_shoot
	_audio_shoot.pitch_scale = randf_range(0.9, 1.1)
	_audio_shoot.play()


func stop_shoot_sound() -> void:
	if _audio_shoot:
		_audio_shoot.stop()
