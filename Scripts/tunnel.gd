extends Node3D

const NUM_LANES: int = 12
const LANE_ANGLE_STEP: float = TAU / NUM_LANES
const TUNNEL_RADIUS: float = 3.0
const SEGMENT_LENGTH: float = 1.5708

const TUNNEL_SIDES: int = 64
const SEGMENTS_AHEAD_BUFFER: int = 26
const TILES_PER_TUNNEL: int = 10
const OBSTACLE_SAFE_START_TILES: int = 20

const OBSTACLE_TILE_INTERVAL: int = 4
const OBSTACLE_MIN_COUNT: int = 2
const OBSTACLE_MAX_COUNT: int = 4
const MAX_ADJACENT_OBSTACLES: int = 2

const OBSTACLE_BASE_RADIUS: float = TUNNEL_RADIUS
const OBSTACLE_HEIGHT: float = 0.5
const OBSTACLE_ARC_SUBDIVISIONS: int = 4  # more segments = smoother curve along the base

const ACCENT_COLORS: Array[Color] = [
	Color.WHITE, Color.ORANGE, Color.YELLOW, Color.GREEN,
	Color.CYAN, Color.BLUE, Color.PURPLE, Color.MAGENTA
]

@onready var player: Node3D = get_node("../Player")

var segments_built: int = 0
var obstacles: Array = []

func _ready() -> void:
	randomize()
	rotation = Vector3.ZERO
	for i in range(SEGMENTS_AHEAD_BUFFER):
		build_next_segment()

func _process(_delta: float) -> void:
	var player_segment: int = int(abs(player.position.z) / SEGMENT_LENGTH)
	while segments_built < player_segment + SEGMENTS_AHEAD_BUFFER:
		build_next_segment()

func build_next_segment() -> void:
	var tile_index: int = segments_built
	var z_center: float = -tile_index * SEGMENT_LENGTH - (SEGMENT_LENGTH / 2.0)
	build_segment(z_center, tile_index)

	if tile_index >= OBSTACLE_SAFE_START_TILES and tile_index % OBSTACLE_TILE_INTERVAL == 0:
		spawn_obstacles_for_tile(z_center, tile_index)

	segments_built += 1

func spawn_obstacles_for_tile(z_center: float, tile_index: int) -> void:
	var chosen_lanes: Array = generate_obstacle_lanes()
	for lane in chosen_lanes:
		spawn_obstacle(lane, z_center, tile_index)

func generate_obstacle_lanes() -> Array:
	var attempts: int = 0
	while attempts < 200:
		attempts += 1
		var count: int = randi_range(OBSTACLE_MIN_COUNT, OBSTACLE_MAX_COUNT)
		var lanes: Array = range(NUM_LANES)
		lanes.shuffle()
		var chosen: Array = lanes.slice(0, count)
		if is_valid_pattern(chosen):
			return chosen
	return []

func is_valid_pattern(chosen: Array) -> bool:
	var blocked: Array = []
	for i in range(NUM_LANES):
		blocked.append(chosen.has(i))

	var run: int = 0
	for i in range(NUM_LANES * 2):
		var idx: int = i % NUM_LANES
		if blocked[idx]:
			run += 1
			if run > MAX_ADJACENT_OBSTACLES:
				return false
		else:
			run = 0
	return true

func build_segment(z_center: float, tile_index: int) -> void:
	var wrapper := Node3D.new()
	wrapper.rotation_degrees.x = 90
	wrapper.position = Vector3(0, 0, z_center)
	add_child(wrapper)

	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = TUNNEL_RADIUS
	cyl.bottom_radius = TUNNEL_RADIUS
	cyl.height = SEGMENT_LENGTH
	cyl.radial_segments = TUNNEL_SIDES
	cyl.cap_top = false
	cyl.cap_bottom = false
	mesh_instance.mesh = cyl

	var material := StandardMaterial3D.new()
	material.albedo_texture = make_checkerboard_texture(tile_index)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material

	mesh_instance.rotation_degrees.y = 180.0 / NUM_LANES

	wrapper.add_child(mesh_instance)

func spawn_obstacle(lane: int, z_center: float, tile_index: int) -> void:
	var angle_center: float = lane * LANE_ANGLE_STEP
	var half_angle: float = (LANE_ANGLE_STEP * 0.95) / 2.0
	var half_z: float = (SEGMENT_LENGTH * 0.95) / 2.0

	var a_minus: float = angle_center - half_angle
	var a_plus: float = angle_center + half_angle
	var z_front: float = z_center + half_z
	var z_back: float = z_center - half_z

	var apex_radius: float = OBSTACLE_BASE_RADIUS - OBSTACLE_HEIGHT
	var apex := Vector3(apex_radius * sin(angle_center), -apex_radius * cos(angle_center), z_center)

	# Build the base as a full curved outline (front arc, straight right
	# edge, back arc, straight left edge) instead of just 4 flat corners
	# — this is what actually makes it hug the tunnel's real curve.
	var base_points: Array = []

	for i in range(OBSTACLE_ARC_SUBDIVISIONS + 1):
		var t: float = float(i) / OBSTACLE_ARC_SUBDIVISIONS
		var a: float = lerp(a_minus, a_plus, t)
		base_points.append(Vector3(OBSTACLE_BASE_RADIUS * sin(a), -OBSTACLE_BASE_RADIUS * cos(a), z_front))

	base_points.append(Vector3(OBSTACLE_BASE_RADIUS * sin(a_plus), -OBSTACLE_BASE_RADIUS * cos(a_plus), z_back))

	for i in range(1, OBSTACLE_ARC_SUBDIVISIONS + 1):
		var t: float = float(i) / OBSTACLE_ARC_SUBDIVISIONS
		var a: float = lerp(a_plus, a_minus, t)
		base_points.append(Vector3(OBSTACLE_BASE_RADIUS * sin(a), -OBSTACLE_BASE_RADIUS * cos(a), z_back))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(base_points.size()):
		var p1: Vector3 = base_points[i]
		var p2: Vector3 = base_points[(i + 1) % base_points.size()]
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(apex)
	st.generate_normals()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.15, 0.05)
	material.emission_energy_multiplier = 1.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material

	add_child(mesh_instance)
	obstacles.append({"lane": lane, "z_front": z_front, "z_back": z_back})

func make_checkerboard_texture(tile_index: int) -> ImageTexture:
	var tunnel_index: int = tile_index / TILES_PER_TUNNEL
	var tile_within_tunnel: int = tile_index % TILES_PER_TUNNEL
	var accent_color: Color = ACCENT_COLORS[tunnel_index % ACCENT_COLORS.size()]

	var width: int = NUM_LANES * 32
	var img := Image.create(width, 4, false, Image.FORMAT_RGB8)
	for x in range(width):
		var lane: int = int(float(x) / width * NUM_LANES)
		var is_black: bool = (lane + tile_within_tunnel) % 2 == 0
		var col: Color = Color.BLACK if is_black else accent_color
		for y in range(4):
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
