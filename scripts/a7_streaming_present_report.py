"""A7 experimental ETW presentation analysis; NEVER auto-qualifies strict gates."""
from __future__ import annotations
import csv
import datetime as dt
import json
import math
import sys
import time
from pathlib import Path

NUMERIC_COLUMNS = [
    "DisplayLatency", "MsBetweenDisplayChange", "MsBetweenPresents",
    "MsCPUBusy", "MsGPUTime", "MsUntilDisplayed", "MsRenderPresentLatency",
]
def percentile(values, q):
    if not values:
        return None
    sorted_values = sorted(values)
    return round(sorted_values[min(len(sorted_values)-1, math.ceil((len(sorted_values)-1)*q))], 5)

def number(value):
    try:
        n = float(str(value).strip())
        if math.isfinite(n):
            return n
    except (ValueError, TypeError):
        pass
    return None

def epoch(value):
    if not value or str(value).strip().upper() in ("NA", "N/A"):
        return None
    v = str(value).strip().replace("Z", "+00:00")
    try:
        d = dt.datetime.fromisoformat(v)
        if d.tzinfo is not None:
            return d.timestamp()
        # PresentMon date_time uses the local Windows host time.
        return time.mktime(d.timetuple()) + d.microsecond/1e6
    except (ValueError, OverflowError):
        return None

def analyze_run(folder: Path) -> dict:
    summary_path = folder / "a7_route.json"
    data = json.loads(summary_path.read_text(encoding="utf-8-sig"))
    start = number(data.get("measurement_epoch_begin_s"))
    end = number(data.get("measurement_epoch_end_s"))
    result = {
        "schema": "a7_present_etw_run_v1",
        "route": data["route"], "seed": data["seed"],
        "measurement_duration_s": data["duration_s"],
        "measurement_epoch_begin_s": start,
        "measurement_epoch_end_s": end,
        "frame_start_p99_ms": data["frame_start_p99_ms"],
        "frame_start_max_ms": data["frame_start_max_ms"],
        "voxel_threads_requested": data["voxel_threads_requested"],
        "voxel_threads_actual": data["voxel_threads_actual"],
        "vsync_mode_actual": data["vsync_mode_actual"],
        "min_radial_probe_hits_8": data["min_radial_probe_hits_8"],
        "frame_intervals_over_33_ms": data["frame_intervals_over_33_ms"],
        "presentation_status": "NOT_MEASURED",
        "presentmon_rows_total": 0,
        "presentmon_rows_in_window": 0,
        "presentmon_displayed_rows": 0,
        "presentmon_dropped_rows": 0,
        "window_coverage_s": 0.0,
        "display_latency_p99_ms": None,
        "display_change_p99_ms": None,
        "present_interval_p99_ms": None,
        "gpu_work_p99_ms": None,
        "reason": None,
        "strict_acceptance": "NOT_QUALIFIED",
    }
    status_file = folder / "a7_presentmon_status.json"
    csv_file = folder / "a7_presentmon.csv"
    if not status_file.exists() or not csv_file.exists():
        result["reason"] = "PresentMon status or CSV missing"
        return result
    status = json.loads(status_file.read_text(encoding="utf-8-sig"))
    if not status.get("collection_started") or status.get("exit_code") != 0:
        result["reason"] = f"PresentMon collector error: {status.get('capture_error')}, exit={status.get('exit_code')}"
        return result
    if start is None or end is None or start >= end:
        result["reason"] = "Missing reliable Godot measurement time-window"
        return result
    samples = {k: [] for k in NUMERIC_COLUMNS}
    first = last = None
    seen_time = False
    with csv_file.open("r", encoding="utf-8-sig", errors="replace", newline="") as f:
        reader = csv.DictReader(f)
        headers = set(reader.fieldnames or [])
        if "CPUStartDateTime" not in headers:
            result["reason"] = "PresentMon CSV lacks CPUStartDateTime; cannot align measurement window"
            return result
        if not ("DisplayLatency" in headers and ("MsBetweenDisplayChange" in headers or "DisplayedTime" in headers)):
            result["reason"] = "PresentMon CSV lacks usable display-time metrics"
            return result
        for row in reader:
            result["presentmon_rows_total"] += 1
            stamp = epoch(row.get("CPUStartDateTime"))
            if stamp is None:
                continue
            seen_time = True
            if stamp < start or stamp > end:
                continue
            result["presentmon_rows_in_window"] += 1
            if first is None: first = stamp
            last = stamp
            displayed = number(row.get("DisplayLatency")) is not None
            if not displayed:
                result["presentmon_dropped_rows"] += 1
                continue
            result["presentmon_displayed_rows"] += 1
            for key in NUMERIC_COLUMNS:
                v = number(row.get(key))
                if v is not None and v >= 0:
                    samples[key].append(v)
    if not seen_time:
        result["reason"] = "PresentMon date-time values could not be parsed"
        return result
    result["window_coverage_s"] = round((last-first) if first is not None and last is not None else 0, 3)
    result["display_latency_p99_ms"] = percentile(samples["DisplayLatency"], .99)
    result["display_change_p99_ms"] = percentile(samples["MsBetweenDisplayChange"], .99)
    result["present_interval_p99_ms"] = percentile(samples["MsBetweenPresents"], .99)
    result["gpu_work_p99_ms"] = percentile(samples["MsGPUTime"], .99)
    if result["presentmon_displayed_rows"] < 100 or result["window_coverage_s"] < .85 * (end-start):
        result["presentation_status"] = "ETW_INCOMPLETE"
        result["reason"] = "Insufficient displayed frames or under 85% timestamp coverage"
        return result
    result["presentation_status"] = "ETW_ALIGNED"
    result["reason"] = "Per-process ETW displayed frame metrics aligned to Godot measurement window"
    return result

def summarize(campaign: Path):
    manifest = json.loads((campaign / "streaming_manifest.json").read_text(encoding="utf-8-sig"))
    results = []
    for run in manifest["runs"]:
        folder = campaign / run["directory"]
        result = analyze_run(folder)
        result.update({"profile":run["profile"], "sequence":run["sequence"],
                       "directory":run["directory"]})
        (folder / "a7_present_analysis.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
        results.append(result)
        print("A7_STREAM_PRESENT_RESULT", result["route"], result["profile"],
              "ETW="+result["presentation_status"],
              "display_p99="+str(result["display_latency_p99_ms"]),
              "probes="+str(result["min_radial_probe_hits_8"]), flush=True)
    payload = {
        "schema":"a7_streaming_present_campaign_v1",
        "git_sha":manifest["git_sha"],
        "baseline":manifest["baseline"],
        "presentmon_version":manifest["presentmon_version"],
        "route_count":len(results),
        "etw_aligned_count":sum(1 for r in results if r["presentation_status"]=="ETW_ALIGNED"),
        "strict_acceptance":"NOT_QUALIFIED",
        "warnings":[
            "PresentMon ETW measures software-to-display timing, not camera pixel coverage, HID-to-photon, or actual panel photons.",
            "Results have the same external ETW and process telemetry for both VSync arms.",
            "This is a single-seed diagnostic; do not promote performance settings automatically.",
        ],
        "runs":results,
    }
    (campaign / "streaming_comparison.json").write_text(json.dumps(payload,indent=2),encoding="utf-8")
    with (campaign / "streaming_comparison.csv").open("w",encoding="utf-8",newline="") as f:
        writer=csv.DictWriter(f,fieldnames=list(results[0].keys()))
        writer.writeheader()
        writer.writerows(results)
    return payload

def main():
    if len(sys.argv)!=2: raise SystemExit("usage: python a7_streaming_present_report.py CAMPAIGN_DIR")
    p=Path(sys.argv[1])
    payload=summarize(p)
    print("A7_STREAMING_PRESENT_SUMMARY runs="+str(payload["route_count"]) +
          " etw_aligned="+str(payload["etw_aligned_count"])+
          " strict_acceptance=NOT_QUALIFIED")

if __name__=="__main__":
    main()
