"""A6B source-grounded 128m AABB boundary audit and isolated probe smoke."""
from pathlib import Path
import importlib.util
root = Path(__file__).resolve().parents[1]
for path in (
    "godot/tests/a6b_probe_diagnostic.gd",
    "scripts/a6b-run-windows.ps1",
    "scripts/a6b_probe_geometry.py",
    "docs/A6B_DIAGNOSTICO.md"
):
    assert (root/path).is_file(), path
s=(root/"godot/tests/a6b_probe_diagnostic.gd").read_text(encoding="utf-8")
w=(root/"scripts/a6b-run-windows.ps1").read_text(encoding="utf-8")
for token in ("t007","t064","t135","t236","t250","128.0",
              "is_area_meshed","range(4)","four_quadrants_any_lod",
              "split_covered_but_original_failed",
              "original_lod23","pixel_coverage_gate",
              "candidate_promoted"):
    assert token in s, token
assert "Profiles.apply_to_scene(world, profile)" in s
assert s.index("Profiles.apply_to_scene(world, profile)") < s.index("root.add_child(world)")
assert "headless" in s and "forward_plus" in s and "vulkan" in s
assert "cpu16" in w and "cpu32" in w
assert "A6B_BASELINE_RETAINED" in w and "--rendering-method','forward_plus'" in w
spec=importlib.util.spec_from_file_location("a6b_geom",root/"scripts/a6b_probe_geometry.py")
module=importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
assert module.BLOCK_LOD2_32 == 128
assert [x[0] for x in module.SITES] == ["t007","t064","t135","t236","t250"]
assert all(module.crossed_directions(x) for _,_,x in module.SITES)
# Crossing a grid boundary is a correlation only, not proof of a visible gap.
assert len(module.crossed_directions(899.72)) == 1
print("A6B_STATIC_PROBE_GEOMETRY_PASS")
