extends Node3D

@export var forward_speed: float = 10.0
@export var speed_increase_per_tunnel: float = 0.5
const MAX_FORWARD_SPEED: float = 35.0

const SEGMENT_LENGTH: float = 1.5708
const TILES_PER_TUNNEL: int = 10

const SAVE_PATH: String = "user://highscore.save"

var score: int = 0
var high_score: int = 0
var tunnels_passed: int = 0

var game_state: String = "menu"

const NUM_LANES: int = 12
const LANE_ANGLE_STEP: float = TAU / NUM_LANES
const SWERVE_DURATION: float = 0.2
const SWERVE_GRACE_DURATION: float = 0.05

var current_lane: int = 0
var swipe_start_pos: Vector2 = Vector2.ZERO
var swipe_threshold: float = 50.0

var target_tunnel_rotation_z: float = 0.0
var lane_tween: Tween
var swerve_grace_timer: float = 0.0

var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var left_arm: Node3D
var right_arm: Node3D
var body_mesh_node: MeshInstance3D
var antenna_tip_node: MeshInstance3D
var run_time: float = 0.0

var start_position: Vector3
var base_forward_speed: float

const SHATTER_PIECE_COUNT: int = 10
const SHATTER_DURATION: float = 1.5
const SHATTER_GRAVITY: float = 9.0
const SHATTER_BOUNCE_DAMPING: float = 0.5
const SHATTER_PIECE_RADIUS: float = 0.08

var shatter_balls: Array = []
var shatter_timer: float = 0.0

@onready var tunnel: Node3D = get_node("%TunnelPivot")

func _ready() -> void:
	start_position = position
	base_forward_speed = forward_speed

	load_high_score()

	build_character()

	get_node("%PlayButton").pressed.connect(start_game)
	get_node("%RoundScoreLabel").visible = false

	# Show the persisted high score right away, even before this
	# session's first run, since it's meaningful data from past play.
	if high_score > 0:
		get_node("%HighScoreLabel").text = "High Score: " + str(high_score)
		get_node("%HighScoreLabel").visible = true
	else:
		get_node("%HighScoreLabel").visible = false

func load_high_score() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		high_score = file.get_as_text().to_int()
		file.close()

func save_high_score() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(str(high_score))
	file.close()

func build_character() -> void:
	var mesh_root: MeshInstance3D = $PlayerMesh
	mesh_root.mesh = null
	for child in mesh_root.get_children():
		child.queue_free()

	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.2
	body_mesh.height = 0.4
	body.mesh = body_mesh
	body.position = Vector3(0, 0.32, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.25, 0.75, 0.65)
	body.material_override = body_mat
	mesh_root.add_child(body)
	body_mesh_node = body

	var antenna_stalk := MeshInstance3D.new()
	var stalk_mesh := CylinderMesh.new()
	stalk_mesh.top_radius = 0.015
	stalk_mesh.bottom_radius = 0.02
	stalk_mesh.height = 0.16
	antenna_stalk.mesh = stalk_mesh
	antenna_stalk.position = Vector3(0, 0.5, 0)
	var stalk_mat := StandardMaterial3D.new()
	stalk_mat.albedo_color = Color(0.15, 0.45, 0.4)
	antenna_stalk.material_override = stalk_mat
	mesh_root.add_child(antenna_stalk)

	var antenna_tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.04
	tip_mesh.height = 0.08
	antenna_tip.mesh = tip_mesh
	antenna_tip.position = Vector3(0, 0.59, 0)
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(1.0, 0.9, 0.3)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(1.0, 0.9, 0.3)
	antenna_tip.material_override = tip_mat
	mesh_root.add_child(antenna_tip)
	antenna_tip_node = antenna_tip

	var limb_mat := StandardMaterial3D.new()
	limb_mat.albedo_color = Color(0.2, 0.55, 0.5)

	for x_side in [-1, 1]:
		var arm_pivot := Node3D.new()
		arm_pivot.position = Vector3(x_side * 0.18, 0.34, 0.02)
		mesh_root.add_child(arm_pivot)

		var arm := MeshInstance3D.new()
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.045
		arm_mesh.height = 0.22
		arm.mesh = arm_mesh
		arm.rotation_degrees.z = 90
		arm.position = Vector3(x_side * 0.1, 0, 0)
		arm.material_override = limb_mat
		arm_pivot.add_child(arm)

		if x_side == -1:
			left_arm = arm_pivot
		else:
			right_arm = arm_pivot

	for x_side in [-1, 1]:
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.05
		leg_mesh.height = 0.24
		leg.mesh = leg_mesh
		leg.position = Vector3(x_side * 0.1, 0.12, 0)
		leg.material_override = limb_mat
		mesh_root.add_child(leg)
		if x_side == -1:
			left_leg = leg
		else:
			right_leg = leg

func start_game() -> void:
	get_node("%MainMenu").visible = false

	position = start_position
	current_lane = 0
	target_tunnel_rotation_z = 0.0
	if lane_tween:
		lane_tween.kill()
	tunnel.rotation.z = 0.0
	forward_speed = base_forward_speed
	score = 0
	tunnels_passed = 0
	swerve_grace_timer = 0.0
	get_node("%ScoreLabel").text = "0"

	$PlayerMesh.visible = true
	game_state = "playing"

func _process(delta: float) -> void:
	if game_state == "menu":
		return

	if game_state == "dying":
		update_shatter(delta)
		return

	var prev_z: float = position.z
	position.z -= forward_speed * delta

	run_time += delta * forward_speed * 0.35

	if left_leg and right_leg:
		left_leg.rotation_degrees.x = sin(run_time) * 28.0
		right_leg.rotation_degrees.x = -sin(run_time) * 28.0

	if left_arm and right_arm:
		left_arm.rotation_degrees.x = -sin(run_time) * 24.0
		right_arm.rotation_degrees.x = sin(run_time) * 24.0

	if body_mesh_node:
		body_mesh_node.position.y = 0.32 + (1.0 - cos(run_time * 2.0)) * 0.015

	if antenna_tip_node:
		antenna_tip_node.rotation_degrees.z = sin(run_time * 0.9) * 8.0

	var current_tile: int = int(abs(position.z) / SEGMENT_LENGTH)
	var current_tunnel: int = current_tile / TILES_PER_TUNNEL
	if current_tunnel > tunnels_passed:
		tunnels_passed = current_tunnel
		score += 1
		forward_speed = min(forward_speed + speed_increase_per_tunnel, MAX_FORWARD_SPEED)
		get_node("%ScoreLabel").text = str(score)

	if swerve_grace_timer > 0.0:
		swerve_grace_timer -= delta
	else:
		check_obstacle_collision(prev_z, position.z)

func check_obstacle_collision(prev_z: float, new_z: float) -> void:
	var z_min: float = min(prev_z, new_z)
	var z_max: float = max(prev_z, new_z)

	for obs in tunnel.obstacles:
		if obs["lane"] == current_lane:
			if z_min <= obs["z_front"] and obs["z_back"] <= z_max:
				trigger_game_over()
				return

func trigger_game_over() -> void:
	start_shatter()

func start_shatter() -> void:
	game_state = "dying"
	$PlayerMesh.visible = false

	shatter_balls.clear()
	shatter_timer = 0.0

	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.25, 0.75, 0.65)

	for i in range(SHATTER_PIECE_COUNT):
		var ball := MeshInstance3D.new()
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = SHATTER_PIECE_RADIUS
		ball_mesh.height = SHATTER_PIECE_RADIUS * 2.0
		ball.mesh = ball_mesh
		ball.material_override = ball_mat
		ball.position = Vector3(0, 0.3, 0)
		add_child(ball)

		var vel := Vector3(randf_range(-2.0, 2.0), randf_range(2.0, 4.0), randf_range(-2.0, 2.0))
		shatter_balls.append({"node": ball, "velocity": vel})

func update_shatter(delta: float) -> void:
	shatter_timer += delta

	for b in shatter_balls:
		var node: MeshInstance3D = b["node"]
		var vel: Vector3 = b["velocity"]

		vel.y -= SHATTER_GRAVITY * delta
		node.position += vel * delta

		if node.position.y <= 0.0 and vel.y < 0.0:
			node.position.y = 0.0
			vel.y = -vel.y * SHATTER_BOUNCE_DAMPING

		b["velocity"] = vel

	if shatter_timer >= SHATTER_DURATION:
		end_shatter()

func end_shatter() -> void:
	for b in shatter_balls:
		b["node"].queue_free()
	shatter_balls.clear()

	show_end_menu()

func show_end_menu() -> void:
	var round_score: int = score
	if round_score > high_score:
		high_score = round_score
		save_high_score()

	get_node("%RoundScoreLabel").text = "Score: " + str(round_score)
	get_node("%RoundScoreLabel").visible = true
	get_node("%HighScoreLabel").text = "High Score: " + str(high_score)
	get_node("%HighScoreLabel").visible = true

	get_node("%MainMenu").visible = true
	game_state = "menu"

func _input(event: InputEvent) -> void:
	if game_state == "menu":
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			start_game()
		return

	if game_state != "playing":
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			swipe_start_pos = event.position
		else:
			var diff_x: float = event.position.x - swipe_start_pos.x
			if abs(diff_x) > swipe_threshold:
				if diff_x > 0:
					switch_lane(1)
				else:
					switch_lane(-1)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			switch_lane(-1)
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			switch_lane(1)

func switch_lane(direction: int) -> void:
	current_lane = (current_lane + direction) % NUM_LANES
	if current_lane < 0:
		current_lane += NUM_LANES

	if tunnel == null:
		return

	target_tunnel_rotation_z += -direction * LANE_ANGLE_STEP
	swerve_grace_timer = SWERVE_GRACE_DURATION

	if lane_tween:
		lane_tween.kill()
	lane_tween = create_tween()
	lane_tween.set_trans(Tween.TRANS_CUBIC)
	lane_tween.set_ease(Tween.EASE_OUT)
	lane_tween.tween_property(tunnel, "rotation:z", target_tunnel_rotation_z, SWERVE_DURATION)
