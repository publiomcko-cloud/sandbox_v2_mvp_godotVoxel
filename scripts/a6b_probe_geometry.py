"""Explain the 128 m (32 voxels * 2^2) LOD2 cell-edge pattern.

These positions were extracted from the user-supplied 12-run A6 graphical ZIP.
This is a geometry audit of the AABB detector, not rendered-pixel evidence.
"""
from __future__ import annotations
import json
import math

SITES = [
    ("t007", 7.004, 126.07),
    ("t064", 64.001, 1152.01),
    ("t135", 135.005, 2430.08),
    ("t236", 236.009, 1151.84),
    ("t250", 250.016, 899.72),
]
RADIUS = 130.0
AABB_HALF = 2.0
BLOCK_LOD2_32 = 32 * (2**2)


def crossed_directions(x: float, grid: float = BLOCK_LOD2_32) -> list[int]:
    result = []
    for i in range(8):
        angle = i * math.tau / 8
        point_x = x + RADIUS * math.cos(angle)
        point_z = 18.0 + RADIUS * math.sin(angle)
        for position in (point_x, point_z):
            lower = math.floor((position - AABB_HALF) / grid)
            upper = math.floor((position + AABB_HALF) / grid)
            if lower != upper:
                result.append(i)
                break
    return result


def main() -> None:
    rows = [
        {
            "site": site, "original_time_s": t, "player_x": x,
            "intersected_128m_edge_probe_directions": crossed_directions(x),
        }
        for site, t, x in SITES
    ]
    assert all(r["intersected_128m_edge_probe_directions"] for r in rows)
    print(json.dumps({"schema": "a6b_geometry_v1",
                      "source": "reportsA6.zip; 6 mesh32 runs each had same five incomplete instants",
                      "not_proof_of": ["which direction failed", "rendered pixel gaps"],
                      "sites": rows}, indent=2))


if __name__ == "__main__":
    main()
