extends CharacterBody3D

# ─────────────────────────────────────────
#  FPS Player Controller
#  + Procedural footstep sounds
# ─────────────────────────────────────────

const SoundGen := preload("res://scripts/sound_generator.gd")
const WEAPON_RIFLE := preload("res://scenes/weapon_rifle.tscn")
const WEAPON_PISTOL := preload("res://scenes/weapon_pistol.tscn")

# --- Movement Settings ---wWWwW
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 9.0
@export var crouch_speed: float = 2.5
@export var jump_velocity: float = 5.0
@export var mouse_sensitivity: float = 0.15

# --- Camera Settings ---
@export var camera_bob_frequency: float = 2.0
@export var camera_bob_amplitude: float = 0.05
@export var fov_default: float = 75.0
@export var fov_aim: float = 55.0

# --- Health ---
@export var max_health: float = 100.0
var health: float = max_health
var is_dead: bool = false

# --- Footsteps ---
var _footstep_snd: AudioStream
var _footstep_audio: AudioStreamPlayer3D
var _footstep_timer: float = 0.0
var _footstep_interval: float = 0.45

# --- Weapons ---
var weapons: Array[Node3D] = []
var current_weapon_index: int = 0

# --- Internal State ---
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_sprinting: bool = false
var is_crouching: bool = false
var is_aiming: bool = false
var bob_time: float = 0.0
var current_speed: float = walk_speed

# --- Node References ---
@onready var camera: Camera3D = $Head/Camera3D
@onready var head: Node3D = $Head
@onready var weapon_holder: Node3D = $Head/Camera3D/WeaponHolder
@onready var raycast: RayCast3D = $Head/Camera3D/RayCast3D

signal health_changed(new_health: float, max_hp: float)
signal player_died
signal aim_changed(aiming: bool)
signal ammo_changed(current: int, reserve: int)
signal reloading_started(time: float)
signal enemy_hit
signal reload_cancelled


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.fov = fov_default
	health_changed.emit(health, max_health)
	
	# Load shotgun dynamically
	var shotgun_scene = load("res://scenes/weapon_shotgun.tscn")
	if shotgun_scene:
		var shotgun = shotgun_scene.instantiate()
		weapon_holder.add_child(shotgun)
		shotgun.position = Vector3.ZERO
		shotgun.rotation = Vector3.ZERO
		
	# Load sniper dynamically
	var sniper_scene = load("res://scenes/weapon_sniper.tscn")
	if sniper_scene:
		var sniper = sniper_scene.instantiate()
		weapon_holder.add_child(sniper)
		sniper.position = Vector3.ZERO
		sniper.rotation = Vector3.ZERO
	
	# Load custom imported weapons
	_load_custom_weapons_from_folder()
	
	# Initialize weapons
	weapons.clear()
	for child in weapon_holder.get_children():
		if "weapon_name" in child:
			weapons.append(child)
	_show_weapon(0)
	
	# Initialize footsteps using custom sound file if available
	var fs_loaded = load("res://assets/sounds/footsteps.mp3")
	if fs_loaded:
		_footstep_snd = fs_loaded
	else:
		_footstep_snd = SoundGen.footstep()
		
	_footstep_audio = AudioStreamPlayer3D.new()
	_footstep_audio.max_db = -4.0 # Keep footsteps subtler than gunfire
	add_child(_footstep_audio)


func _unhandled_input(event: InputEvent) -> void:
	# Toggle mouse capture with escape key
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Recapture mouse on clicking window
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Scroll wheel weapon swapping
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_weapon((current_weapon_index - 1 + weapons.size()) % weapons.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_weapon((current_weapon_index + 1) % weapons.size())

	# Keypad weapon selection
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_select_weapon(0)
		elif event.keycode == KEY_2:
			_select_weapon(1)
		elif event.keycode == KEY_3:
			_select_weapon(2)

	# Standard swap weapon action
	if event.is_action_pressed("swap_weapon"):
		_select_weapon((current_weapon_index + 1) % weapons.size())


func _select_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size() or is_dead:
		return
	current_weapon_index = index
	_show_weapon(index)


func _show_weapon(index: int) -> void:
	for i in range(weapons.size()):
		var w = weapons[i]
		if i == index:
			w.visible = true
			# Connect weapon signals
			if not w.ammo_changed.is_connected(_on_weapon_ammo_changed):
				w.ammo_changed.connect(_on_weapon_ammo_changed)
			if not w.reloading_started.is_connected(_on_weapon_reloading):
				w.reloading_started.connect(_on_weapon_reloading)
			
			# Emit current state to HUD
			ammo_changed.emit(w.current_ammo, w.reserve_ammo)
			if w.is_reloading:
				reloading_started.emit(w.reload_timer)
				
			# Add a brief delay so player cannot fire instantly on switch
			w.fire_timer = maxf(w.fire_timer, 0.25)
		else:
			w.visible = false
			# Cancel reloading on inactive weapon
			if w.has_method("cancel_reload") and w.is_reloading:
				w.cancel_reload()
				reload_cancelled.emit()
				
			# Disconnect from inactive weapons to avoid duplicate signal handlers
			if w.ammo_changed.is_connected(_on_weapon_ammo_changed):
				w.ammo_changed.disconnect(_on_weapon_ammo_changed)
			if w.reloading_started.is_connected(_on_weapon_reloading):
				w.reloading_started.disconnect(_on_weapon_reloading)


func _on_weapon_ammo_changed(current: int, reserve: int) -> void:
	ammo_changed.emit(current, reserve)


func _on_weapon_reloading(time: float) -> void:
	reloading_started.emit(time)


func notify_enemy_hit() -> void:
	enemy_hit.emit()


func alert_enemies_of_shot() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("hear_gunshot"):
			var dist = enemy.global_position.distance_to(global_position)
			if dist < 35.0: # 35 meters hearing range
				enemy.hear_gunshot(global_position)



func _physics_process(delta: float) -> void:
	if is_dead:
		return

	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_states()
	_handle_camera_bob(delta)
	_handle_fov(delta)
	_handle_footsteps(delta)
	
	# Smoothly interpolate weapon position for ADS
	var target_weapon_pos: Vector3
	if is_aiming:
		if weapons.size() > current_weapon_index and weapons[current_weapon_index].weapon_name == "Sniper Rifle":
			target_weapon_pos = Vector3(0.0, -0.06, -0.2)
		elif weapons.size() > current_weapon_index and weapons[current_weapon_index].weapon_name == "Pump Shotgun":
			target_weapon_pos = Vector3(0.0, -0.08, -0.2)
		else: # "Assault Rifle"
			target_weapon_pos = Vector3(0.0, -0.065, -0.3)
	else:
		target_weapon_pos = Vector3(0.22, -0.22, -0.4)
	weapon_holder.position = weapon_holder.position.lerp(target_weapon_pos, 14.0 * delta)

	move_and_slide()


func _handle_footsteps(delta: float) -> void:
	if not is_on_floor() or velocity.length() < 0.5:
		return
		
	var current_interval := _footstep_interval
	if is_sprinting:
		current_interval = _footstep_interval * 0.65
	elif is_crouching:
		current_interval = _footstep_interval * 1.4
		
	_footstep_timer -= delta
	if _footstep_timer <= 0:
		_footstep_timer = current_interval
		_footstep_audio.stream = _footstep_snd
		_footstep_audio.pitch_scale = randf_range(0.9, 1.1)
		_footstep_audio.play()


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity


func _handle_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and input_dir != Vector2.ZERO
	is_crouching = Input.is_action_pressed("crouch")

	if is_sprinting:
		current_speed = sprint_speed
	elif is_crouching:
		current_speed = crouch_speed
	else:
		current_speed = walk_speed

	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)


func _handle_states() -> void:
	# Crouch height adjustment
	if is_crouching:
		head.position.y = lerp(head.position.y, 0.5, 0.1)
	else:
		head.position.y = lerp(head.position.y, 1.6, 0.1)

	var was_aiming: bool = is_aiming
	is_aiming = Input.is_action_pressed("aim")
	if is_aiming != was_aiming:
		aim_changed.emit(is_aiming)


func _handle_camera_bob(delta: float) -> void:
	if is_on_floor() and velocity.length() > 0.5:
		bob_time += delta * camera_bob_frequency * (1.5 if is_sprinting else 1.0)
		camera.position.y = sin(bob_time) * camera_bob_amplitude
		camera.position.x = cos(bob_time / 2.0) * camera_bob_amplitude * 0.5
	else:
		camera.position.y = lerp(camera.position.y, 0.0, 10.0 * delta)
		camera.position.x = lerp(camera.position.x, 0.0, 10.0 * delta)


func _handle_fov(delta: float) -> void:
	var weapon_fov: float = fov_aim
	if weapons.size() > current_weapon_index:
		var current_w = weapons[current_weapon_index]
		if current_w.weapon_name == "Pump Shotgun":
			weapon_fov = 62.0
		elif current_w.weapon_name == "Sniper Rifle":
			weapon_fov = 20.0
		else: # "Assault Rifle"
			weapon_fov = 55.0

	var target_fov: float = weapon_fov if is_aiming else fov_default
	camera.fov = lerp(camera.fov, target_fov, 10.0 * delta)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	player_died.emit()
	# TODO: play death animation, show respawn screen


func _load_custom_weapons_from_folder() -> void:
	var dir_path := "res://assets/weapons"
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_absolute(dir_path)
		return
	
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var full_path = dir_path + "/" + file_name
				if file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
					_instantiate_raw_glb_weapon(full_path)
				elif file_name.ends_with(".tscn"):
					_instantiate_tscn_weapon(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()


func _instantiate_raw_glb_weapon(file_path: String) -> void:
	var base_name := file_path.get_file().get_basename()
	# Avoid duplicates
	for w in weapon_holder.get_children():
		if w.name == base_name:
			return
			
	var mesh_scene = load(file_path)
	if not mesh_scene:
		return
		
	var weapon_script := load("res://scripts/weapon.gd")
	var weapon_node = weapon_script.new()
	weapon_node.name = base_name
	
	# Configure default parameters based on filename keyword
	var lower_name := base_name.to_lower()
	weapon_node.weapon_name = base_name.replace("_", " ").to_upper()
	if lower_name.contains("shotgun"):
		weapon_node.damage = 15.0
		weapon_node.fire_rate = 0.9
		weapon_node.mag_size = 6
		weapon_node.reserve_ammo = 18
		weapon_node.bullet_spread = 0.08
		weapon_node.is_automatic = false
		weapon_node.is_shotgun = true
		weapon_node.shotgun_pellets = 8
		weapon_node.range_max = 25.0
	elif lower_name.contains("sniper") or lower_name.contains("snipe") or lower_name.contains("awp"):
		weapon_node.damage = 95.0
		weapon_node.fire_rate = 1.3
		weapon_node.mag_size = 5
		weapon_node.reserve_ammo = 15
		weapon_node.bullet_spread = 0.001
		weapon_node.is_automatic = false
		weapon_node.range_max = 180.0
	elif lower_name.contains("mac10"):
		weapon_node.damage = 16.0
		weapon_node.fire_rate = 0.06
		weapon_node.mag_size = 32
		weapon_node.reserve_ammo = 96
		weapon_node.bullet_spread = 0.04
		weapon_node.is_automatic = true
		weapon_node.range_max = 50.0
	elif lower_name.contains("rocket") or lower_name.contains("launcher"):
		weapon_node.damage = 250.0
		weapon_node.fire_rate = 2.0
		weapon_node.mag_size = 1
		weapon_node.reserve_ammo = 5
		weapon_node.bullet_spread = 0.03
		weapon_node.is_automatic = false
		weapon_node.range_max = 120.0
	else: # default rifle/pistol
		weapon_node.damage = 26.0
		weapon_node.fire_rate = 0.12
		weapon_node.mag_size = 30
		weapon_node.reserve_ammo = 90
		weapon_node.bullet_spread = 0.02
		weapon_node.is_automatic = true
		weapon_node.range_max = 100.0

	var mesh_inst = mesh_scene.instantiate()
	mesh_inst.name = "Model"
	weapon_node.add_child(mesh_inst)
	
	# Scale and position to sit naturally in hand based on model type
	var scale_factor := 0.95
	var pos_offset := Vector3(0.0, -0.05, 0.0)
	
	if lower_name.contains("mac10"):
		scale_factor = 1.05
		pos_offset = Vector3(0.0, -0.03, 0.05)
	elif lower_name.contains("awp") or lower_name.contains("sniper"):
		scale_factor = 0.8
		pos_offset = Vector3(0.0, -0.05, -0.15)
	elif lower_name.contains("rocket") or lower_name.contains("launcher"):
		scale_factor = 0.8
		pos_offset = Vector3(0.0, -0.08, -0.1)
	elif lower_name.contains("shotgun"):
		scale_factor = 0.9
		pos_offset = Vector3(0.0, -0.05, -0.05)
		
	mesh_inst.scale = Vector3.ONE * scale_factor
	mesh_inst.position = pos_offset
	# Rotate the weapon 90 degrees clockwise around Y to point forward (along -Z) instead of left (along -X)
	mesh_inst.rotation = Vector3(0.0, PI/2, 0.0)
	
	# Get AABB of the mesh to calculate muzzle position dynamically
	var aabb = _get_mesh_aabb(mesh_inst)
	var muzzle_z = aabb.position.x * scale_factor + pos_offset.z
	var muzzle_y = (aabb.position.y + aabb.size.y * 0.5) * scale_factor + pos_offset.y
	
	var muzzle_node := Node3D.new()
	muzzle_node.name = "MuzzlePoint"
	muzzle_node.position = Vector3(0.0, muzzle_y, muzzle_z)
	weapon_node.add_child(muzzle_node)
	
	weapon_holder.add_child(weapon_node)
	print("Dynamically registered raw GLB weapon: %s | Mesh Rot: %s | Mesh Global Rot: %s" % [base_name, mesh_inst.rotation, mesh_inst.global_rotation])


func _get_mesh_aabb(node: Node) -> AABB:
	var aabb = AABB()
	var first = true
	var queue = [node]
	while queue.size() > 0:
		var curr = queue.pop_front()
		if curr is MeshInstance3D and curr.mesh:
			var child_aabb = curr.mesh.get_aabb()
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
		for child in curr.get_children():
			queue.push_back(child)
	return aabb


func _instantiate_tscn_weapon(file_path: String) -> void:
	var base_name := file_path.get_file().get_basename()
	for w in weapon_holder.get_children():
		if w.name == base_name:
			return
	var scene := load(file_path)
	if scene:
		var inst = scene.instantiate()
		inst.name = base_name
		weapon_holder.add_child(inst)
		inst.position = Vector3.ZERO
		inst.rotation = Vector3.ZERO
		print("Dynamically registered custom weapon scene: %s" % base_name)
