#!/usr/bin/env python3
"""A6 side-by-side campaign comparator: no automatic candidate promotion.

Only comparable Vulkan Forward+ sessions with matching A2 instrumentation are
summarized. Viewport GPU time and frame-start intervals are NOT full presented
frame duration and do NOT qualify PERF-60, STREAM-18, VIEW-130 or EDIT-100.
"""
from __future__ import annotations
import argparse
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

VARIANTS = ("cpu16", "gpu16", "cpu32", "gpu32")


def compare(root: Path) -> dict:
    records: dict[str, list[dict]] = defaultdict(list)
    skipped: list[str] = []
    for path in sorted(root.rglob("a2_*.json")):
        try:
            d = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError) as exc:
            skipped.append(f"{path}: {exc}")
            continue
        name = d.get("a6_profile")
        if name not in VARIANTS:
            skipped.append(f"{path}: no recognized A6 profile")
            continue
        d["_file"] = str(path)
        records[name].append(d)

    def numbers(xs: list[dict], key: str) -> list[float]:
        return [float(r[key]) for r in xs
                if isinstance(r.get(key), (int, float)) and math.isfinite(float(r[key]))]

    summary: dict[str, dict] = {}
    for name in VARIANTS:
        xs = records[name]
        summary[name] = {
            "runs": len(xs),
            "paths": [x["_file"] for x in xs],
            "frame_interval_p99_ms_median": (
                statistics.median(numbers(xs, "frame_interval_ms_p99"))
                if numbers(xs, "frame_interval_ms_p99") else None),
            "frame_interval_max_ms_worst": (
                max(numbers(xs, "frame_interval_ms_max"))
                if numbers(xs, "frame_interval_ms_max") else None),
            "viewport_render_gpu_p99_ms_median": (
                statistics.median(numbers(xs, "viewport_render_gpu_p99_ms"))
                if numbers(xs, "viewport_render_gpu_p99_ms") else None),
            "viewport_render_cpu_p99_ms_median": (
                statistics.median(numbers(xs, "viewport_render_cpu_p99_ms"))
                if numbers(xs, "viewport_render_cpu_p99_ms") else None),
            "requested_mesh_block_size": 32 if name.endswith("32") else 16,
            "requested_gpu_generation": name.startswith("gpu"),
            "total_frame_intervals": sum(int(x.get("frame_intervals_observed", 0)) for x in xs),
        }

    all_rows = [r for xs in records.values() for r in xs]
    keys = ("route", "duration_sec", "warmup_sec", "view_distance_m",
            "lod_distance_m", "rendering_method_actual",
            "rendering_driver_actual", "screenshots_enabled", "ci_smoke")
    invariants = {k: sorted({str(row.get(k)) for row in all_rows}) for k in keys}
    matching = bool(all_rows) and all(len(v) == 1 for v in invariants.values())
    graphics = (all_rows and
                all(row.get("rendering_method_actual") == "forward_plus" and
                    str(row.get("rendering_driver_actual", "")).lower() == "vulkan" and
                    row.get("ci_smoke") is False and
                    int(row.get("viewport_render_gpu_samples", 0)) > 0 and
                    row.get("view_distance_m") == 192 and
                    row.get("lod_distance_m") == 48
                    for row in all_rows))
    repeats = all(len(records[name]) >= 3 for name in VARIANTS)
    full_route = (all_rows and
                  all(float(r.get("duration_sec", 0)) >= 180 for r in all_rows))
    same_seed = all(r.get("seed") == 20261119 for r in all_rows)
    same_view = all(r.get("view_distance_m") == 192 and r.get("lod_distance_m") == 48 for r in all_rows)

    deltas = {}
    for size in (16, 32):
        c = summary[f"cpu{size}"]["frame_interval_p99_ms_median"]
        g = summary[f"gpu{size}"]["frame_interval_p99_ms_median"]
        deltas[str(size)] = {
            "cpu_p99_ms": c, "gpu_p99_ms": g,
            "gpu_minus_cpu_p99_ms": round(g-c, 4) if c is not None and g is not None else None,
            "gpu_vs_cpu_p99_percent": round((c-g)/c*100, 3) if c and g is not None else None,
        }

    complete = bool(graphics and matching and repeats and full_route and same_seed and same_view)
    return {
        "schema": "a6_comparison_v1",
        "profiles": summary,
        "matched_invariants": invariants,
        "skipped": skipped,
        "cpu_gpu_p99_comparison": deltas,
        "measured_comparison_ready": complete,
        "result": "GRAPHICAL_COMPARISON_READY_FOR_REVIEW" if complete else "INCOMPLETE_OR_NONCOMPARABLE",
        "promoted_profile": None,
        "auto_promotion_policy": "NEVER",
        "strict_perf_60_gate": "NOT_QUALIFIED",
        "view_130_visual_gate": "NOT_QUALIFIED",
        "stream_18_visual_gate": "NOT_QUALIFIED",
        "gpu_dispatch_proven": False,
        "caveats": [
            "frame-start intervals and viewport GPU/CPU render times exclude full present-chain latency",
            "a Vulkan renderer and use_gpu_generation=true do not alone prove shader dispatch",
            "the same A2 instrumentation was applied in every run",
            "pixels, coverage, SDF equivalence and GPU task execution need independent verification",
            "no LOD/view-distance downgrade permitted",
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, help="A6 experiment directory")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args()
    if not args.root.is_dir():
        parser.error("A6 report root does not exist")
    payload = compare(args.root)
    output = args.out or args.root / "a6_comparison.json"
    output.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"A6_COMPARISON={output}")
    print(f"A6_STATUS={payload['result']} NO_AUTOPROMOTION")
    for n in VARIANTS:
        row = payload["profiles"][n]
        print(f"{n}: runs={row['runs']} p99_interval={row['frame_interval_p99_ms_median']} "
              f"gpu_p99={row['viewport_render_gpu_p99_ms_median']}")
    if payload["skipped"]:
        print(f"A6_SKIPPED_FILES={len(payload['skipped'])}")


if __name__ == "__main__":
    main()
