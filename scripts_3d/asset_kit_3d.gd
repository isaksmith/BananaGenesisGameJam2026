class_name AssetKit3D
extends RefCounted

## Kenney CC0 3D models used by the 3D Banana Genesis slice.

const MONKEY := "res://assets/models_3d/pets/animal-monkey.glb"
const BANANA := "res://assets/models_3d/food/banana.glb"
const APPLE := "res://assets/models_3d/food/apple.glb"
const STICK := "res://assets/models_3d/food/celery-stick.glb"
const CARROT := "res://assets/models_3d/food/carrot.glb"
const COCONUT := "res://assets/models_3d/food/coconut-half.glb"

const PALM := "res://assets/models_3d/nature/tree_palm.glb"
const PALM_TALL := "res://assets/models_3d/nature/tree_palmTall.glb"
const PALM_SHORT := "res://assets/models_3d/nature/tree_palmShort.glb"
const PALM_BEND := "res://assets/models_3d/nature/tree_palmBend.glb"
const TREE := "res://assets/models_3d/nature/tree_default.glb"
const ROCK_A := "res://assets/models_3d/nature/rock_largeA.glb"
const ROCK_B := "res://assets/models_3d/nature/rock_largeB.glb"
const ROCK_C := "res://assets/models_3d/nature/rock_largeC.glb"
const ROCK_SMALL := "res://assets/models_3d/nature/rock_smallA.glb"
const STONE_TALL := "res://assets/models_3d/nature/stone_tallC.glb"
const CAMPFIRE := "res://assets/models_3d/nature/campfire_logs.glb"
const CAMPFIRE_STONES := "res://assets/models_3d/nature/campfire_stones.glb"
const LOG_STACK := "res://assets/models_3d/nature/log_stack.glb"
const TENT_NATURE := "res://assets/models_3d/nature/tent_detailedOpen.glb"
const FLOWER := "res://assets/models_3d/nature/flower_yellowA.glb"

const CRATE := "res://assets/models_3d/props/crate.glb"
const BARREL := "res://assets/models_3d/props/barrel.glb"
const STAR := "res://assets/models_3d/props/star.glb"
const BLOCK_GRASS := "res://assets/models_3d/props/block-grass-large.glb"
const BLOCK_LONG := "res://assets/models_3d/props/block-grass-long.glb"

const HUT_TENT := "res://assets/models_3d/forest/tent.glb"
const FOREST_TREE := "res://assets/models_3d/forest/tree-high.glb"
const FOREST_ROCKS := "res://assets/models_3d/forest/rocks-high.glb"
const BUILDING := "res://assets/models_3d/forest/building-structure.glb"
const BUILDING_ROOF := "res://assets/models_3d/forest/building-roof.glb"


static func make(path: String, scale: float = 1.0, y_degrees: float = 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Missing 3D asset: %s" % path)
		return MeshKit3D.box(Vector3.ONE * scale, Color(1, 0, 1))
	var node := packed.instantiate() as Node3D
	node.scale = Vector3.ONE * scale
	if y_degrees != 0.0:
		node.rotation_degrees.y = y_degrees
	return node


static func add(parent: Node3D, path: String, pos: Vector3, scale: float = 1.0, y_degrees: float = 0.0) -> Node3D:
	var node := make(path, scale, y_degrees)
	node.position = pos
	parent.add_child(node)
	return node


static func scatter_palms(parent: Node3D, positions: Array) -> void:
	var variants := [PALM, PALM_TALL, PALM_SHORT, PALM_BEND]
	for i in positions.size():
		var path: String = variants[i % variants.size()]
		add(parent, path, positions[i], 1.0, float(i * 37))
