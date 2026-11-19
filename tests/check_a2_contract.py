"""A2 static contract guards; runtime correctness also requires CI GDScript tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for rel in ("godot/tests/a2_routes.gd", "godot/tests/a2_runtime.gd",
            "godot/tests/a2_benchmark.gd", "godot/tests/a2_smoke.gd",
            "scripts/a2-benchmark-windows.ps1", "scripts/a2-smoke-windows.ps1"):
    assert (root / rel).is_file(), rel
routes = (root / "godot/tests/a2_routes.gd").read_text(encoding="utf-8")
runtime = (root / "godot/tests/a2_runtime.gd").read_text(encoding="utf-8")
for name in ("stationary_180s","straight_18mps_600s","turns_18mps_300s",
             "out_and_back_18mps_300s"):
    assert name in routes, name
assert "SPEED_MPS := 18.0" in routes
assert "Time.get_ticks_usec()" in runtime
assert 'get_statistics()' in runtime and "debug_get_mesh_block_count()" in runtime
assert "is_area_meshed" in runtime
assert "Performance.TIME_PROCESS" in runtime
assert "frame_interval_ms_p99" in runtime and "frame_interval_ms_p999" in runtime
assert '"NOT_QUALIFIED"' in runtime
assert "A2_OUTPUT_DIR" in runtime
assert "VoxelLodTerrain" in (root / "godot/scenes/main.tscn").read_text(encoding="utf-8")
print("A2_STATIC_PASS")
