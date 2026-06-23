extends CharacterBody3D

# ─────────────────────────────────────────
#  Enemy AI — Combat Android
#  + Procedural walking leg/arm swing animations
#  + Ranged shooting back at the player
#  + Visually striking red laser bullet tracers
#  + Tween-based hit flash & death fall animations
# ─────────────────────────────────────────

const SoundGen := preload("res://scripts/sound_generator.gd")

enum State { IDLE, PATROL, ALERT, CHASE, ATTACK, DEAD }

@export_group("Stats")
@export var max_health: float    = 90.0
@export var move_speed: float    = 4.0
@export var chase_speed: float   = 6.2
@export var attack_damage: float = 24.0
@export var attack_range: float  = 100.0
@export var attack_interval: float = 0.95
@export var detection_range: float = 100.0
@export var field_of_view: float = 110.0

@export_group("Patrol")
@export var patrol_points: Array[StringName] = []

@export_group("Appearance")
@export var use_soldier_skin: bool = true

@export_group("Weapon Attachment")
@export var weapon_pos_offset: Vector3 = Vector3(0.0, 10.0, 15.0)
@export var weapon_rot_offset: Vector3 = Vector3(0.0, -PI/2, PI/2)

# --- State ---
var current_state: State = State.IDLE
var health: float
var attack_timer: float  = 0.0
var alert_timer: float   = 0.0
var patrol_index: int    = 0
var player: Node3D       = null
var body_mat: StandardMaterial3D   # unique material for hit flash
var original_color: Color

# --- Patrol/Random AI ---
var start_position: Vector3
var random_patrol_target: Vector3 = Vector3.ZERO
var random_patrol_timer: float = 0.0

# --- Soldier Skin Nodes ---
var soldier_instance: Node3D = null
var soldier_skeleton: Skeleton3D = null
var soldier_materials: Array[Material] = []
var soldier_original_colors: Array[Color] = []
var base_visuals_y: float = 0.0
var bone_left_leg: int = -1
var bone_right_leg: int = -1
var bone_left_arm: int = -1
var bone_right_arm: int = -1

# --- Animation State ---
var bob_timer: float  = 0.0
var walk_timer: float = 0.0

# --- Nodes ---
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visuals: Node3D              = $Visuals
@onready var torso: MeshInstance3D        = $Visuals/Torso
@onready var head: MeshInstance3D         = $Visuals/Head
@onready var left_arm: MeshInstance3D     = $Visuals/LeftArm
@onready var right_arm: MeshInstance3D    = $Visuals/RightArm
@onready var left_leg: MeshInstance3D     = $Visuals/LeftLeg
@onready var right_leg: MeshInstance3D    = $Visuals/RightLeg
@onready var muzzle_flash: MeshInstance3D = $Visuals/RightArm/Gun/MuzzleFlash

# --- Audio ---
var _audio: AudioStreamPlayer3D
var _snd_grunt: AudioStreamWAV
var _snd_die:   AudioStreamWAV
var _snd_alert: AudioStreamWAV
var _snd_shoot: AudioStreamWAV

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

signal enemy_died


func _ready() -> void:
	health = max_health
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	base_visuals_y = visuals.position.y

	# Make unique material so color changes don't affect all enemies
	if torso:
		body_mat = torso.get_surface_override_material(0).duplicate()
		torso.set_surface_override_material(0, body_mat)
		original_color = body_mat.albedo_color

	if use_soldier_skin:
		_setup_soldier_skin()

	# Generate sounds
	_snd_grunt = SoundGen.enemy_grunt()
	_snd_die   = SoundGen.enemy_die()
	_snd_alert = SoundGen.enemy_alert()
	_snd_shoot = SoundGen.gunshot()

	_audio = AudioStreamPlayer3D.new()
	add_child(_audio)

	bob_timer = randf_range(0.0, TAU)

	if patrol_points.size() > 0 or use_soldier_skin:
		_set_state(State.PATROL)
	else:
		_set_state(State.IDLE)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	match current_state:
		State.IDLE:   _state_idle(delta)
		State.PATROL: _state_patrol(delta)
		State.ALERT:  _state_alert(delta)
		State.CHASE:  _state_chase(delta)
		State.ATTACK: _state_attack(delta)

	_check_player_visibility()
	_animate_idle_bob(delta)
	_animate_limbs(delta)
	move_and_slide()


# ── State Behaviours ──────────────────────────────────────────────────────────

func _state_idle(_delta: float) -> void:
	velocity.x = 0
	velocity.z = 0


func _state_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		if random_patrol_target == Vector3.ZERO or nav_agent.is_navigation_finished() or random_patrol_timer <= 0.0:
			var map = nav_agent.get_navigation_map()
			if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
				var random_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
				var random_dist = randf_range(4.0, 12.0)
				var test_target = start_position + random_dir * random_dist
				var closest = NavigationServer3D.map_get_closest_point(map, test_target)
				if closest != Vector3.ZERO or start_position.length() < 0.1:
					random_patrol_target = closest
					nav_agent.target_position = random_patrol_target
					random_patrol_timer = randf_range(6.0, 12.0)
			
		if random_patrol_target != Vector3.ZERO:
			random_patrol_timer -= delta
			_move_toward_target(move_speed)
		else:
			velocity.x = 0
			velocity.z = 0
		return

	var target: Node = get_node_or_null(NodePath(patrol_points[patrol_index]))
	if target:
		nav_agent.target_position = target.global_position
		_move_toward_target(move_speed)
		if nav_agent.is_navigation_finished():
			patrol_index = (patrol_index + 1) % patrol_points.size()


func _state_alert(delta: float) -> void:
	velocity.x = 0
	velocity.z = 0
	alert_timer -= delta
	if alert_timer <= 0:
		_set_state(State.CHASE)


func _state_chase(_delta: float) -> void:
	if not player or not player.is_inside_tree():
		_set_state(State.PATROL)
		return
	nav_agent.target_position = player.global_position
	_move_toward_target(chase_speed)

	var dist: float = global_position.distance_to(player.global_position)
	if dist <= attack_range and _has_line_of_sight():
		_set_state(State.ATTACK)
	elif dist > detection_range * 1.5:
		_set_state(State.PATROL)


func _state_attack(delta: float) -> void:
	if not player or not player.is_inside_tree():
		_set_state(State.PATROL)
		return

	# If we lose line of sight, immediately revert to chase to run after the player!
	var dist: float = global_position.distance_to(player.global_position)
	if not _has_line_of_sight() or dist > attack_range * 1.1:
		_set_state(State.CHASE)
		return

	# Face the player
	var look: Vector3 = (player.global_position - global_position).normalized()
	look.y = 0
	if look != Vector3.ZERO:
		transform.basis = transform.basis.slerp(Basis.looking_at(look, Vector3.UP), 0.15)

	# If we are far, keep approaching while shooting!
	if dist > 22.0:
		_move_toward_target(chase_speed * 0.8)
	else:
		velocity.x = 0
		velocity.z = 0

	attack_timer -= delta
	if attack_timer <= 0:
		attack_timer = attack_interval
		_do_shoot()


func _do_shoot() -> void:
	if not player or current_state == State.DEAD or not _has_line_of_sight():
		return

	# Play shoot sound
	_play_sound(_snd_shoot, 2.0)

	# Trigger muzzle flash
	if muzzle_flash:
		muzzle_flash.visible = true
		_hide_muzzle_flash_later()

	# Spawn visual tracer from muzzle to player
	var start_pos: Vector3 = muzzle_flash.global_position if muzzle_flash else global_position + Vector3(0.3, 0.8, -0.6)
	var end_pos: Vector3 = player.global_position + Vector3(0.0, randf_range(0.6, 1.4), 0.0) # Aim at chest/head

	# Inaccuracy check
	var hit_chance: float = 0.38 # 38% accuracy
	var is_hit: bool = randf() < hit_chance

	if not is_hit:
		# Divert the bullet away
		end_pos += Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))

	_spawn_tracer(start_pos, end_pos)

	if is_hit and player.has_method("take_damage"):
		player.take_damage(attack_damage)


func _hide_muzzle_flash_later() -> void:
	await get_tree().create_timer(0.05).timeout
	if muzzle_flash:
		muzzle_flash.visible = false


func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	
	var dist: float = start.distance_to(end)
	cyl.height = dist
	tracer.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.1, 1.0)
	mat.emission_energy_multiplier = 5.0
	tracer.set_surface_override_material(0, mat)

	get_tree().root.add_child(tracer)
	tracer.global_position = start.lerp(end, 0.5)
	tracer.look_at(end, Vector3.UP)
	tracer.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	await get_tree().create_timer(0.06).timeout
	tracer.queue_free()


# ── Utilities ─────────────────────────────────────────────────────────────────

func _has_line_of_sight() -> bool:
	if not is_inside_tree() or not player or not player.is_inside_tree():
		return false
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 1.5, 0.0)
	var to := player.global_position + Vector3(0.0, 1.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result:
		return result.collider == player
	return false


func _check_player_visibility() -> void:
	if not is_inside_tree() or not player or not player.is_inside_tree() or current_state == State.DEAD:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist > detection_range:
		return
	var dir: Vector3 = (player.global_position - global_position).normalized()
	var angle: float = rad_to_deg(transform.basis.z.angle_to(-dir))
	if angle < field_of_view / 2.0:
		if current_state in [State.IDLE, State.PATROL]:
			alert_timer = 0.5
			_set_state(State.ALERT)
		elif current_state == State.ALERT:
			_set_state(State.CHASE)


func _move_toward_target(speed: float) -> void:
	var next: Vector3 = nav_agent.get_next_path_position()
	# Fallback if navigation region is not baked or path fails:
	if next.is_equal_approx(global_position) or nav_agent.is_navigation_finished():
		next = nav_agent.target_position

	var dir: Vector3 = (next - global_position).normalized()
	dir.y = 0
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dir != Vector3.ZERO:
		transform.basis = transform.basis.slerp(Basis.looking_at(dir, Vector3.UP), 0.15)


func _set_state(new_state: State) -> void:
	current_state = new_state
	if new_state == State.ALERT:
		_play_sound(_snd_alert, 0.0)


func _play_sound(stream: AudioStreamWAV, db: float = 0.0) -> void:
	if _audio:
		_audio.stream = stream
		_audio.max_db = db
		_audio.play()


# ── Damage & Death ────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
	health -= amount

	_animate_hit_flash()

	if current_state in [State.IDLE, State.PATROL]:
		_set_state(State.CHASE)

	if health <= 0.0:
		_die()
	else:
		if randf() > 0.5:
			_play_sound(_snd_grunt, -3.0)


func _die() -> void:
	_set_state(State.DEAD)
	velocity = Vector3.ZERO
	_play_sound(_snd_die, 3.0)
	_animate_death()
	enemy_died.emit()


# ── Animations ────────────────────────────────────────────────────────────────

func _animate_idle_bob(delta: float) -> void:
	if current_state == State.DEAD:
		return
	bob_timer += delta * 2.0
	var bob: float = sin(bob_timer) * 0.035
	visuals.position.y = base_visuals_y + bob


func _animate_limbs(delta: float) -> void:
	if current_state == State.DEAD:
		return

	if use_soldier_skin and soldier_skeleton:
		_animate_soldier_skeleton(delta)
		return

	var speed_2d: float = Vector2(velocity.x, velocity.z).length()
	if speed_2d > 0.1:
		walk_timer += delta * speed_2d * 2.6
		left_arm.rotation.x  = sin(walk_timer) * 0.65
		right_arm.rotation.x = -sin(walk_timer) * 0.65
		left_leg.rotation.x  = -sin(walk_timer) * 0.55
		right_leg.rotation.x = sin(walk_timer) * 0.55
	else:
		# Return back to default resting positions
		left_arm.rotation.x  = lerp(left_arm.rotation.x, 0.0, 12.0 * delta)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, 12.0 * delta)
		left_leg.rotation.x  = lerp(left_leg.rotation.x, 0.0, 12.0 * delta)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 12.0 * delta)


func _animate_soldier_skeleton(delta: float) -> void:
	var left_leg_idx = bone_left_leg
	var right_leg_idx = bone_right_leg
	var left_arm_idx = bone_left_arm
	var right_arm_idx = bone_right_arm
	
	var speed_2d: float = Vector2(velocity.x, velocity.z).length()
	if speed_2d > 0.1:
		walk_timer += delta * speed_2d * 2.6
		var leg_swing = sin(walk_timer) * 0.45
		var arm_swing = sin(walk_timer) * 0.45
		
		if left_leg_idx != -1:
			soldier_skeleton.set_bone_pose_rotation(left_leg_idx, Quaternion(Vector3.RIGHT, -leg_swing))
		if right_leg_idx != -1:
			soldier_skeleton.set_bone_pose_rotation(right_leg_idx, Quaternion(Vector3.RIGHT, leg_swing))
			
		if current_state in [State.CHASE, State.ATTACK]:
			# Aiming pose: arms forward
			if right_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(right_arm_idx, Quaternion(Vector3(0.0, 1.0, 0.0), -1.5) * Quaternion(Vector3(1.0, 0.0, 0.0), 0.4))
			if left_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(left_arm_idx, Quaternion(Vector3(0.0, 1.0, 0.0), 1.5) * Quaternion(Vector3(1.0, 0.0, 0.0), 0.4))
		else:
			# Patrolling/Idle: Swing arms
			if left_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(left_arm_idx, Quaternion(Vector3.RIGHT, arm_swing))
			if right_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(right_arm_idx, Quaternion(Vector3.RIGHT, -arm_swing))
	else:
		# Standing still
		if current_state in [State.CHASE, State.ATTACK]:
			# Aiming pose while standing still
			if right_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(right_arm_idx, Quaternion(Vector3(0.0, 1.0, 0.0), -1.5) * Quaternion(Vector3(1.0, 0.0, 0.0), 0.4))
			if left_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(left_arm_idx, Quaternion(Vector3(0.0, 1.0, 0.0), 1.5) * Quaternion(Vector3(1.0, 0.0, 0.0), 0.4))
		else:
			# Reset to rest pose
			if left_leg_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(left_leg_idx, Quaternion.IDENTITY)
			if right_leg_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(right_leg_idx, Quaternion.IDENTITY)
			if left_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(left_arm_idx, Quaternion.IDENTITY)
			if right_arm_idx != -1:
				soldier_skeleton.set_bone_pose_rotation(right_arm_idx, Quaternion.IDENTITY)


func _animate_hit_flash() -> void:
	if use_soldier_skin and not soldier_materials.is_empty():
		var tween := create_tween()
		tween.set_parallel(true)
		for i in range(soldier_materials.size()):
			var mat = soldier_materials[i]
			tween.tween_property(mat, "albedo_color", Color(2.5, 2.5, 2.5, 1.0), 0.04)
		
		# Wait and tween back
		var t_back := create_tween()
		t_back.set_parallel(true)
		await get_tree().create_timer(0.04).timeout
		for i in range(soldier_materials.size()):
			var mat = soldier_materials[i]
			var orig = soldier_original_colors[i]
			t_back.tween_property(mat, "albedo_color", orig, 0.12)
	else:
		if not body_mat:
			return
		var tween := create_tween()
		tween.tween_property(body_mat, "albedo_color", Color(1.0, 1.0, 1.0, 1.0), 0.03)
		tween.tween_property(body_mat, "albedo_color", original_color, 0.12)

	# Scale pulse
	var t3 := create_tween()
	t3.tween_property(visuals, "scale", Vector3(1.15, 0.88, 1.15), 0.04)
	t3.tween_property(visuals, "scale", Vector3(1.0, 1.0, 1.0), 0.1)


func _animate_death() -> void:
	if use_soldier_skin:
		for mat in soldier_materials:
			mat.albedo_color = Color(0.4, 0.1, 0.1, 1.0)
	else:
		if body_mat:
			body_mat.albedo_color = Color(0.4, 0.1, 0.1, 1)

	var tween := create_tween()
	tween.set_parallel(true)
	# Fall forward and collapse
	tween.tween_property(visuals, "rotation:x", -PI / 2.0, 0.35).set_ease(Tween.EASE_IN)
	tween.tween_property(visuals, "position:y", -0.7, 0.35)
	tween.tween_property(visuals, "scale", Vector3(1.0, 0.7, 1.0), 0.35)

	await get_tree().create_timer(3.0).timeout
	queue_free()


func _setup_soldier_skin() -> void:
	var scene = load("res://assets/models/soldier/scene.gltf")
	if not scene:
		push_warning("Failed to load soldier skin from res://assets/models/soldier/scene.gltf")
		return

	soldier_instance = scene.instantiate()
	visuals.add_child(soldier_instance)
	soldier_instance.scale = Vector3(0.01, 0.01, 0.01)
	soldier_instance.position = Vector3(0.0, -0.9, 0.0)
	
	soldier_skeleton = _find_skeleton(soldier_instance)
	if soldier_skeleton:
		bone_left_leg = soldier_skeleton.find_bone("mixamorig_LeftUpLeg_062")
		bone_right_leg = soldier_skeleton.find_bone("mixamorig_RightUpLeg_057")
		bone_left_arm = soldier_skeleton.find_bone("mixamorig_LeftArm_011")
		bone_right_arm = soldier_skeleton.find_bone("mixamorig_RightArm_035")
		var bone_attach = BoneAttachment3D.new()
		bone_attach.name = "RightHandAttachment"
		bone_attach.bone_name = "mixamorig_RightHand_037"
		soldier_skeleton.add_child(bone_attach)
		
		var gun = $Visuals/RightArm/Gun
		if gun:
			gun.get_parent().remove_child(gun)
			bone_attach.add_child(gun)
			gun.scale = Vector3(100.0, 100.0, 100.0)
			gun.position = weapon_pos_offset
			gun.rotation = weapon_rot_offset
	
	_setup_soldier_materials(soldier_instance)
	
	if torso: torso.visible = false
	if head: head.visible = false
	if left_arm: left_arm.visible = false
	if right_arm: right_arm.visible = false
	if left_leg: left_leg.visible = false
	if right_leg: right_leg.visible = false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var res = _find_skeleton(child)
		if res:
			return res
	return null


func _setup_soldier_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for i in range(node.get_mesh().get_surface_count()):
			var mat = node.get_active_material(i)
			if mat and mat is BaseMaterial3D:
				var dupe_mat = mat.duplicate()
				node.set_surface_override_material(i, dupe_mat)
				soldier_materials.append(dupe_mat)
				soldier_original_colors.append(dupe_mat.albedo_color)
	for child in node.get_children():
		_setup_soldier_materials(child)
