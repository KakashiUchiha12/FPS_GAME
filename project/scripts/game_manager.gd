extends Node

# ─────────────────────────────────────────
#  Level Manager — Endless Battle Mode
#  Tracks player score, enemy count, and handles respawns
# ─────────────────────────────────────────

const ENEMY_SCENE = preload("res://scenes/enemy.tscn")

const SPAWN_POINTS = [
	Vector3(-45.0, 1.0, -45.0),
	Vector3(45.0, 1.0, -45.0),
	Vector3(-45.0, 1.0, 45.0),
	Vector3(45.0, 1.0, 45.0),
	Vector3(0.0, 1.0, -50.0),
	Vector3(0.0, 1.0, 50.0),
	Vector3(-50.0, 1.0, 0.0),
	Vector3(50.0, 1.0, 0.0)
]

@export var max_active_enemies: int = 6

var score: int = 0
var level: int = 1
var enemies_killed_in_level: int = 0
var enemies_per_level: int = 5
var active_enemies: Array[Node] = []

signal level_changed(new_level: int)
signal score_changed(new_score: int)
signal upgrade_unlocked(upgrade_text: String)

@onready var player: Node = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	_setup_realistic_materials()
	
	# Register starting enemies
	var starting_enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in starting_enemies:
		active_enemies.append(enemy)
		enemy.enemy_died.connect(func(): _on_enemy_died(enemy))

	# Connect player death
	if player:
		player.player_died.connect(_on_player_died)

	level_changed.emit(level)
	score_changed.emit(score)

	_setup_sky_and_sun()
	print("Level started — Active enemies: %d" % active_enemies.size())


func _setup_sky_and_sun() -> void:
	# 1. Create a beautiful ProceduralSkyMaterial
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85, 1.0) # Richer sky blue
	sky_mat.sky_horizon_color = Color(0.7, 0.75, 0.8, 1.0) # Soft horizon haze
	sky_mat.ground_bottom_color = Color(0.15, 0.16, 0.18, 1.0) # Dark base
	sky_mat.ground_horizon_color = Color(0.7, 0.75, 0.8, 1.0) # Matches sky horizon

	# 2. Create Sky resource and assign the material
	var sky_res := Sky.new()
	sky_res.sky_material = sky_mat

	# 3. Create Environment resource
	var env := Environment.new()
	env.background_mode = 2 # BG_SKY
	env.sky = sky_res
	
	# 4. Set tonemapping, SSAO, and Glow
	env.tonemap_mode = 3 # ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.2
	env.glow_blend_mode = 0 # SCREEN
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = false

	# 5. Apply to WorldEnvironment node
	var we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if not we:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		get_tree().current_scene.add_child(we)
	we.environment = env
	print("Dynamically applied fresh Environment with Sky!")

	# 6. Configure Sun (DirectionalLight3D) properties and rotation
	var sun := get_node_or_null("../Sun") as DirectionalLight3D
	if not sun:
		# Search in current scene for any DirectionalLight3D
		for child in get_tree().current_scene.get_children():
			if child is DirectionalLight3D:
				sun = child
				break
	
	if sun:
		sun.light_color = Color(1.0, 0.96, 0.9, 1.0) # Sunny light
		sun.light_energy = 2.4 # Strong sunlight
		sun.shadow_enabled = true
		sun.shadow_bias = 0.03
		sun.shadow_normal_bias = 1.5
		# Enable high quality shadows
		sun.directional_shadow_split_1 = 0.1
		sun.directional_shadow_split_2 = 0.2
		sun.directional_shadow_split_3 = 0.5
		sun.directional_shadow_blend_splits = true
		# Set a beautiful afternoon angle: pitch 45 deg down, yaw 35 deg
		sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(35), 0)
		print("Dynamically configured Sun properties & rotation!")
	else:
		print("Sun node not found in scene!")



func _setup_realistic_materials() -> void:
	var root := get_tree().current_scene
	if not root:
		return
	
	# Load PBR texture maps
	# Floor (Grass004)
	var grass_color := load("res://assets/textures/Grass004_1K-JPG_Color.jpg")
	var grass_normal := load("res://assets/textures/Grass004_1K-JPG_NormalGL.jpg")
	var grass_roughness := load("res://assets/textures/Grass004_1K-JPG_Roughness.jpg")
	var grass_ao := load("res://assets/textures/Grass004_1K-JPG_AmbientOcclusion.jpg")
	
	var mat_floor := StandardMaterial3D.new()
	mat_floor.albedo_texture = grass_color
	mat_floor.normal_enabled = true
	mat_floor.normal_texture = grass_normal
	mat_floor.roughness_texture = grass_roughness
	mat_floor.ao_enabled = true
	mat_floor.ao_texture = grass_ao
	mat_floor.uv1_scale = Vector3(25, 25, 1)

	# Walls / House walls (Bricks076C)
	var brick_color := load("res://assets/textures/Bricks076C_1K-JPG_Color.jpg")
	var brick_normal := load("res://assets/textures/Bricks076C_1K-JPG_NormalGL.jpg")
	var brick_roughness := load("res://assets/textures/Bricks076C_1K-JPG_Roughness.jpg")
	var brick_ao := load("res://assets/textures/Bricks076C_1K-JPG_AmbientOcclusion.jpg")
	
	var mat_wall := StandardMaterial3D.new()
	mat_wall.albedo_texture = brick_color
	mat_wall.normal_enabled = true
	mat_wall.normal_texture = brick_normal
	mat_wall.roughness_texture = brick_roughness
	mat_wall.ao_enabled = true
	mat_wall.ao_texture = brick_ao
	mat_wall.uv1_triplanar = true
	mat_wall.uv1_scale = Vector3(0.15, 0.15, 0.15)

	# House Roof (RoofingTiles007)
	var roof_color := load("res://assets/textures/RoofingTiles007_1K-JPG_Color.jpg")
	var roof_normal := load("res://assets/textures/RoofingTiles007_1K-JPG_NormalGL.jpg")
	var roof_roughness := load("res://assets/textures/RoofingTiles007_1K-JPG_Roughness.jpg")
	var roof_ao := load("res://assets/textures/RoofingTiles007_1K-JPG_AmbientOcclusion.jpg")
	
	var mat_roof := StandardMaterial3D.new()
	mat_roof.albedo_texture = roof_color
	mat_roof.normal_enabled = true
	mat_roof.normal_texture = roof_normal
	mat_roof.roughness_texture = roof_roughness
	mat_roof.ao_enabled = true
	mat_roof.ao_texture = roof_ao
	mat_roof.uv1_triplanar = true
	mat_roof.uv1_scale = Vector3(0.2, 0.2, 0.2)

	# Tree Trunk (Bark014)
	var bark_color := load("res://assets/textures/Bark014_1K-JPG_Color.jpg")
	var bark_normal := load("res://assets/textures/Bark014_1K-JPG_NormalGL.jpg")
	var bark_roughness := load("res://assets/textures/Bark014_1K-JPG_Roughness.jpg")
	var bark_ao := load("res://assets/textures/Bark014_1K-JPG_AmbientOcclusion.jpg")
	
	var mat_bark := StandardMaterial3D.new()
	mat_bark.albedo_texture = bark_color
	mat_bark.normal_enabled = true
	mat_bark.normal_texture = bark_normal
	mat_bark.roughness_texture = bark_roughness
	mat_bark.ao_enabled = true
	mat_bark.ao_texture = bark_ao
	mat_bark.uv1_triplanar = true
	mat_bark.uv1_scale = Vector3(0.5, 0.5, 0.5)

	_apply_materials_recursive(root, mat_floor, mat_wall, mat_roof, mat_bark)


func _apply_materials_recursive(node: Node, mat_floor: Material, mat_wall: Material, mat_roof: Material, mat_bark: Material) -> void:
	if node is MeshInstance3D:
		var parent_name := node.get_parent().name
		if node.name == "FloorMesh":
			node.material_override = mat_floor
		elif node.name.contains("Wall") or parent_name.contains("Wall") or parent_name.contains("Inner"):
			node.material_override = mat_wall
		elif node.name == "Base" and parent_name.begins_with("House"):
			node.material_override = mat_wall
		elif node.name == "Roof" and parent_name.begins_with("House"):
			node.material_override = mat_roof
		elif node.name == "Trunk" and parent_name.begins_with("Tree"):
			node.material_override = mat_bark
	
	for child in node.get_children():
		_apply_materials_recursive(child, mat_floor, mat_wall, mat_roof, mat_bark)


func _on_enemy_died(enemy: Node) -> void:
	active_enemies.erase(enemy)
	score += 100
	score_changed.emit(score)
	enemies_killed_in_level += 1
	
	print("Score: %d | Enemies remaining: %d" % [score, active_enemies.size()])

	# Check if we need to level up
	if enemies_killed_in_level >= enemies_per_level:
		_level_up()

	# Start respawn timer
	get_tree().create_timer(3.5).timeout.connect(_respawn_enemy)


func _level_up() -> void:
	level += 1
	enemies_killed_in_level = 0
	enemies_per_level = int(enemies_per_level * 1.3)
	max_active_enemies = min(12, max_active_enemies + 1)
	
	level_changed.emit(level)
	print("=== LEVEL %d ===" % level)
	
	# Give player a random upgrade
	_give_player_upgrade()


func _give_player_upgrade() -> void:
	if not player:
		return
	
	var upgrade_type: int = randi() % 3
	
	match upgrade_type:
		0: # Health upgrade
			player.max_health += 20
			player.health = min(player.health + 20, player.max_health)
			player.health_changed.emit(player.health, player.max_health)
			print("UPGRADE: Max Health increased!")
			upgrade_unlocked.emit("Max Health Increased (+20 HP)!")
		1: # Speed upgrade
			player.walk_speed += 0.5
			player.sprint_speed += 0.8
			player.crouch_speed += 0.25
			print("UPGRADE: Movement Speed increased!")
			upgrade_unlocked.emit("Movement Speed Increased (+10%)!")
		2: # Weapon damage upgrade
			var weapons: Array = player.weapons
			for weapon in weapons:
				if weapon.has_method("upgrade_damage"):
					weapon.upgrade_damage(10)
			print("UPGRADE: Weapon Damage increased!")
			upgrade_unlocked.emit("Weapon Damage Increased (+10)!")


func _respawn_enemy() -> void:
	if active_enemies.size() >= max_active_enemies:
		return

	# Find a spawn point not too close to the player
	var valid_spawns: Array[Vector3] = []
	var player_pos := Vector3.ZERO
	if player:
		player_pos = player.global_position

	for spawn in SPAWN_POINTS:
		if not player or spawn.distance_to(player_pos) > 10.0:
			valid_spawns.append(spawn)

	if valid_spawns.is_empty():
		valid_spawns = SPAWN_POINTS # Fallback

	var spawn_pos: Vector3 = valid_spawns[randi() % valid_spawns.size()]

	# Instance and configure enemy
	var new_enemy = ENEMY_SCENE.instantiate()
	new_enemy.position = spawn_pos
	# Scale enemy stats based on level
	_apply_enemy_scaling(new_enemy)
	# Add to main level root so it doesn't get freed with LevelManager
	get_tree().root.add_child(new_enemy)

	active_enemies.append(new_enemy)
	new_enemy.enemy_died.connect(func(): _on_enemy_died(new_enemy))

	# Make it chase player immediately upon spawn
	new_enemy._set_state(new_enemy.State.CHASE)

	print("Respawned enemy at: ", spawn_pos)


func _apply_enemy_scaling(enemy: Node) -> void:
	var scale_factor: float = 1.0 + (level - 1) * 0.15
	enemy.max_health = int(enemy.max_health * scale_factor)
	enemy.health = enemy.max_health
	enemy.attack_damage = int(enemy.attack_damage * scale_factor)
	enemy.chase_speed = enemy.chase_speed * (1.0 + (level - 1) * 0.05)


func _on_player_died() -> void:
	print("Player died — Game Over!")
	await get_tree().create_timer(3.0).timeout
	get_tree().reload_current_scene()
