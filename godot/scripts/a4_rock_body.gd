extends RigidBody3D
# Spawned by native VoxelInstancer.remove_instances_in_sphere(). The same
# transform is assigned BEFORE add_child. A4 manager owns persistence.
@export var rock_id: String = ""
var restored_from_disk: bool = false

func _ready() -> void:
    if rock_id.is_empty():
        var p := global_position
        rock_id = "x%d_y%d_z%d" % [roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]
    var manager := get_tree().get_first_node_in_group("a4_rock_manager")
    if manager != null:
        manager.register_body(self)
    elif not OS.get_cmdline_user_args().has("--a4-standalone-physics"):
        push_error("A4_BODY_ORPHAN: no rock manager")
