"""A6: no renderer confounding, no profile data corruption, no silent promotion."""
from pathlib import Path
import importlib.util
import json
import tempfile
ROOT = Path(__file__).resolve().parents[1]
required = (
    "godot/tests/a6_profiles.gd","godot/tests/a6_benchmark.gd",
    "godot/tests/a2_runtime.gd","scripts/a6-run-windows.ps1",
    "scripts/a6-smoke-windows.ps1","scripts/a6_compare.py",
    "docs/A6_IMPLEMENTACAO.md",
)
for path in required:
    assert (ROOT/path).is_file(), path
prof=(ROOT/"godot/tests/a6_profiles.gd").read_text(encoding="utf-8")
bench=(ROOT/"godot/tests/a6_benchmark.gd").read_text(encoding="utf-8")
runtime=(ROOT/"godot/tests/a2_runtime.gd").read_text(encoding="utf-8")
shell=(ROOT/"scripts/a6-run-windows.ps1").read_text(encoding="utf-8")
scene=(ROOT/"godot/scenes/main.tscn").read_text(encoding="utf-8")
for name in ("cpu16", "gpu16", "cpu32", "gpu32"):
    assert name in prof and name in shell
assert "VIEW_DISTANCE_M := 192" in prof and "LOD_COUNT := 4" in prof
assert "LOD_DISTANCE_M := 48.0" in prof
assert "terrain.use_gpu_generation" in prof
assert "terrain.mesh_block_size" in prof
assert "root.add_child(world)" in bench and "Profiles.apply_to_scene(world, profile)" in bench
assert bench.index("Profiles.apply_to_scene(world, profile)") < bench.index("root.add_child(world)")
assert '"forward_plus"' in bench and '"vulkan"' in bench
assert "get_rendering_device()" in bench and "not ci" in bench
assert "Runner" not in bench
assert "Runtime.new()" in bench and "runner.a6_profile" in bench
assert "viewport_set_measure_render_time" in runtime
assert "viewport_get_measured_render_time_gpu" in runtime
assert "VoxelEngine.get_stats()" in runtime
assert "frame_interval_ms_p99" in runtime
assert 'A6_NO_AUTOPROMOTION' in shell
assert "ci_smoke" in runtime and "frame_interval_ms_p999" in runtime
assert "view_distance = 192" in scene and "mesh_block_size = 16" in scene
assert (ROOT/"godot/project.godot").read_text(encoding="utf-8").count('gl_compatibility') >= 1
# Compare a fabricated CPU-only smoke result. It MUST remain incomplete.
spec=importlib.util.spec_from_file_location("a6cmp", ROOT/"scripts/a6_compare.py")
module=importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as td:
    p=Path(td)/"a2_cpu16.json"
    p.write_text(json.dumps({
        "a6_profile":"cpu16","frame_interval_ms_p99":16.7,
        "rendering_method_actual":"gl_compatibility", "ci_smoke":True,
        "duration_sec":2,"seed":20261119
    }),encoding="utf-8")
    data=module.compare(Path(td))
    assert not data["measured_comparison_ready"]
    assert data["promoted_profile"] is None
    assert data["strict_perf_60_gate"] == "NOT_QUALIFIED"
print("A6_STATIC_AND_FAIL_CLOSED_COMPARISON_PASS")
