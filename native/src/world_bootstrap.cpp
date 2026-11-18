#include "world_bootstrap.hpp"

#include <godot_cpp/classes/voxel_lod_terrain.hpp>
#include <godot_cpp/classes/voxel_tool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/node_path.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

void WorldBootstrap::_bind_methods() {
    ClassDB::bind_method(D_METHOD("is_voxel_ready"), &WorldBootstrap::is_voxel_ready);
}

void WorldBootstrap::_ready() {
    set_process(true);
    auto *terrain = Object::cast_to<VoxelLodTerrain>(get_node_or_null(NodePath("Terrain")));
    if (terrain == nullptr) {
        UtilityFunctions::push_error("A0_FAIL: Terrain is not a VoxelLodTerrain");
        return;
    }
    Ref<VoxelTool> tool = terrain->get_voxel_tool();
    if (!tool.is_valid()) {
        UtilityFunctions::push_error("A0_FAIL: VoxelLodTerrain.get_voxel_tool() unavailable");
        return;
    }
    voxel_ready_ = true;
    UtilityFunctions::print("A0_VOXEL_CPP_API_OK");
}

void WorldBootstrap::_process(double delta) {
    ++frame_count_;
    seconds_ += delta;
    const double delta_ms = delta * 1000.0;
    if (delta_ms > worst_delta_ms_) worst_delta_ms_ = delta_ms;
    if (seconds_ >= 5.0) {
        // Diagnostic only: delta is not a CPU+GPU/present-time benchmark.
        UtilityFunctions::print("A0_FRAMES samples=", frame_count_,
            " delta_max_ms=", worst_delta_ms_);
        seconds_ = 0.0;
        frame_count_ = 0;
        worst_delta_ms_ = 0.0;
    }
}

} // namespace godot
