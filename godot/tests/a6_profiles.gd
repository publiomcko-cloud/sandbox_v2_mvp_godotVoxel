extends RefCounted
# A6 isolated experiment matrix. Every profile retains 192m requested view,
# 4 LODs, 48m LOD distance and exactly the A5 world/physics/shaders.
# Cross-renderer CPU GL vs GPU VK is NOT a valid generator-only A/B.
const VIEW_DISTANCE_M := 192
const LOD_COUNT := 4
const LOD_DISTANCE_M := 48.0

static func supported_names() -> PackedStringArray:
    return PackedStringArray(["cpu16", "cpu32", "gpu16", "gpu32"])

static func config(name: String) -> Dictionary:
    match name:
        "cpu16":
            return {"mesh_block_size": 16, "use_gpu_generation": false}
        "cpu32":
            return {"mesh_block_size": 32, "use_gpu_generation": false}
        "gpu16":
            return {"mesh_block_size": 16, "use_gpu_generation": true}
        "gpu32":
            return {"mesh_block_size": 32, "use_gpu_generation": true}
    return {}

static func apply_to_scene(world: Node, name: String) -> bool:
    var values := config(name)
    if values.is_empty():
        return false
    # Properties must be set BEFORE add_child(world), never on a streaming world.
    var terrain: VoxelLodTerrain = world.get_node_or_null("Terrain") as VoxelLodTerrain
    var viewer: VoxelViewer = world.get_node_or_null("Player/VoxelViewer") as VoxelViewer
    if terrain == null or viewer == null:
        return false
    terrain.mesh_block_size = int(values["mesh_block_size"])
    terrain.use_gpu_generation = bool(values["use_gpu_generation"])
    if terrain.view_distance != VIEW_DISTANCE_M or terrain.lod_count != LOD_COUNT or absf(terrain.lod_distance - LOD_DISTANCE_M) > 0.01:
        return false
    if viewer.view_distance != VIEW_DISTANCE_M:
        return false
    return true
