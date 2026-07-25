class_name MeshKit3D
extends RefCounted

## Procedural colored meshes for the 3D jam slice (no external 3D packs required).


static func mat(color: Color, emission: Color = Color(0, 0, 0, 1), emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


static func box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	return mi


static func sphere(radius: float, color: Color, pos: Vector3 = Vector3.ZERO, emission_energy: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat(color, color, emission_energy)
	mi.position = pos
	return mi


static func cylinder(radius: float, height: float, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	return mi


static func capsule_like(radius: float, height: float, color: Color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	return mi


static func static_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, collision_layer: int = 4) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = collision_layer
	body.collision_mask = 0
	body.position = pos
	body.add_child(box(size, color))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


static func ground_plane(parent: Node3D, size: Vector2, color: Color, y: float = 0.0) -> StaticBody3D:
	return static_box(parent, Vector3(size.x, 1.0, size.y), color, Vector3(0, y - 0.5, 0))


static func sun_and_env(parent: Node3D, sun_energy: float = 1.1, ambient: Color = Color(0.35, 0.45, 0.4)) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	parent.add_child(sun)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.72, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_node.environment = env
	parent.add_child(env_node)
