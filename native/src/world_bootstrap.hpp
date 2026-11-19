#pragma once

#include <godot_cpp/classes/node3d.hpp>

namespace godot {

class WorldBootstrap final : public Node3D {
    GDCLASS(WorldBootstrap, Node3D)

    bool voxel_ready_ = false;
    double seconds_ = 0.0;
    double worst_delta_ms_ = 0.0;
    uint64_t frame_count_ = 0;

protected:
    static void _bind_methods();

public:
    void _ready() override;
    void _process(double delta) override;
    bool is_voxel_ready() const { return voxel_ready_; }
};

} // namespace godot
