extends SceneTree
# A6B: targeted diagnostic for five reproducible A6 mesh32 probe misses.
# NOT an A/B performance benchmark. Teleports are deliberate; observations
# during warmup are not evidence for continuous 18m/s streaming.
const Profiles = preload("res://tests/a6_profiles.gd")
const SITES := [
    {"name": "t007", "t": 7.004, "x": 126.07, "direction": 1},
    {"name": "t064", "t": 64.001, "x": 1152.01, "direction": 1},
    {"name": "t135", "t": 135.005, "x": 2430.08, "direction": 1},
    {"name": "t236", "t": 236.009, "x": 1151.84, "direction": -1},
    {"name": "t250", "t": 250.016, "x": 899.72, "direction": -1}
]
const PROBE_RADIUS_M := 130.0
const PROBE_Y := -8.0
const PROBE_Y_HEIGHT := 16.0
const GRID_LOD2_BLOCK32_M := 128.0

func _initialize() -> void:
    call_deferred("_verify")

func _arg(key: String, fallback: String) -> String:
    for arg in OS.get_cmdline_user_args():
        var prefix := "--" + key + "="
        if arg.begins_with(prefix):
            return arg.substr(prefix.length())
    return fallback

func _flag(key: String) -> bool:
    return OS.get_cmdline_user_args().has("--" + key)

func _fail(message: String) -> void:
    push_error("A6B_DIAG_FAIL: " + message)
    quit(2)

func _any_lod_meshed(terrain: VoxelLodTerrain, area: AABB) -> bool:
    for lod in range(4):
        if terrain.is_area_meshed(area, lod):
            return true
    return false

func _crosses_grid(area: AABB, pitch: float) -> bool:
    return (
        floori(area.position.x / pitch) != floori((area.position.x + area.size.x) / pitch)
        or floori(area.position.z / pitch) != floori((area.position.z + area.size.z) / pitch)
    )

func _probe(terrain: VoxelLodTerrain, player_x: float) -> Dictionary:
    var rays: Array[Dictionary] = []
    var misses: Array[int] = []
    var mixed_lod_false_negatives: Array[int] = []
    var missing_quadrants: Array[int] = []
    var boundary_misses: Array[int] = []
    for i in range(8):
        var angle := float(i) * TAU / 8.0
        var point := Vector3(player_x + cos(angle) * PROBE_RADIUS_M,
                             0.0, 18.0 + sin(angle) * PROBE_RADIUS_M)
        var area := AABB(Vector3(point.x - 2.0, PROBE_Y, point.z - 2.0),
                         Vector3(4.0, PROBE_Y_HEIGHT, 4.0))
        var full2 := terrain.is_area_meshed(area, 2)
        var full3 := terrain.is_area_meshed(area, 3)
        var original := full2 or full3
        var full_any := _any_lod_meshed(terrain, area)
        var all_quad_23 := true
        var all_quad_any := true
        var quad_info: Array[Dictionary] = []
        # Partition the original AABB exactly; no overlap or gap.
        for dx in range(2):
            for dz in range(2):
                var quarter := AABB(
                    area.position + Vector3(float(dx) * 2.0, 0.0, float(dz) * 2.0),
                    Vector3(2.0, PROBE_Y_HEIGHT, 2.0)
                )
                var qlod2 := terrain.is_area_meshed(quarter, 2)
                var qlod3 := terrain.is_area_meshed(quarter, 3)
                var q23 := qlod2 or qlod3
                var q_any := _any_lod_meshed(terrain, quarter)
                all_quad_23 = all_quad_23 and q23
                all_quad_any = all_quad_any and q_any
                quad_info.append({
                    "index": dx * 2 + dz,
                    "lod23": q23, "any_lod": q_any, "lod2": qlod2,
                    "lod3": qlod3
                })
        var at128 := _crosses_grid(area, GRID_LOD2_BLOCK32_M)
        var row := {
            "direction": i, "world_probe_x": point.x, "world_probe_z": point.z,
            "original_lod23": original,
            "full_any_lod": full_any, "full_lod2": full2, "full_lod3": full3,
            "four_quadrants_lod23": all_quad_23,
            "four_quadrants_any_lod": all_quad_any,
            "crosses_128m_grid": at128, "quarters": quad_info
        }
        rays.append(row)
        if not original:
            misses.append(i)
            if at128:
                boundary_misses.append(i)
            if all_quad_any:
                mixed_lod_false_negatives.append(i)
            else:
                missing_quadrants.append(i)
    return {
        "original_hits_8": 8 - misses.size(),
        "original_missing_directions": misses,
        "missing_directions_crossing_128m_grid": boundary_misses,
        "split_covered_but_original_failed": mixed_lod_false_negatives,
        "split_any_lod_incomplete": missing_quadrants,
        "rays": rays,
        "pixel_coverage_gate": "NOT_QUALIFIED",
        "frame_time_gate": "NOT_QUALIFIED"
    }

func _capture_site(player: Node3D, folder: String, name: String, mesh32: bool) -> int:
    var screenshots := 0
    # Aim at cardinal probe directions, especially outward toward LOD edges.
    for i in [0, 2, 4, 6]:
        var a := float(i) * TAU / 8.0
        var v := Vector3(cos(a), 0.0, sin(a))
        player.rotation.y = atan2(-v.x, -v.z)
        await process_frame
        await process_frame
        var img := get_viewport().get_texture().get_image()
        if img == null or img.is_empty():
            push_error("A6B_CAPTURE_FAIL site=" + name + " dir=" + str(i))
            continue
        var filename := folder.path_join("%s_%s_dir%d.png" % [name, "32" if mesh32 else "16", i])
        if img.save_png(filename) == OK:
            screenshots += 1
    return screenshots

func _verify() -> void:
    var profile := _arg("profile", "")
    var only_site := _arg("site", "all")
    var ci := _flag("ci-smoke")
    var capture := _flag("capture")
    var headless := DisplayServer.get_name() == "headless"
    if profile != "cpu16" and profile != "cpu32":
        _fail("only cpu16/cpu32, fixed CPU generator and exact A6 scene")
        return
    if headless and (not ci or capture):
        _fail("headless allowed only as CPU smoke without screenshots")
        return
    if not headless:
        if RenderingServer.get_current_rendering_method() != "forward_plus" or RenderingServer.get_current_rendering_driver_name().to_lower() != "vulkan":
            _fail("graphical probe must run Forward+ Vulkan as A6 campaign")
            return
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        root.size = Vector2i(1920, 1080)

    var targets: Array[Dictionary] = []
    for site in SITES:
        if only_site == "all" or only_site == site["name"]:
            targets.append(site)
    if targets.is_empty():
        _fail("unknown site: " + only_site)
        return

    var folder := OS.get_environment("A6B_OUTPUT_DIR")
    if folder.is_empty() or DirAccess.make_dir_recursive_absolute(folder) != OK:
        _fail("isolated A6B_OUTPUT_DIR is required")
        return
    var world: Node3D = load("res://scenes/main.tscn").instantiate()
    if not Profiles.apply_to_scene(world, profile):
        _fail("failed to apply A6 mesh block profile before streaming")
        return
    root.add_child(world)
    await process_frame
    var terrain := world.get_node("Terrain") as VoxelLodTerrain
    var player := world.get_node("Player") as Node3D
    player.set_process(false)
    player.set_process_unhandled_input(false)
    player.set_physics_process(false)
    var all_sites: Array[Dictionary] = []
    var settle_ms := 650 if ci else 3000
    for site in targets:
        var x := float(site["x"])
        player.global_position = Vector3(x, 22.0, 18.0)
        await process_frame
        # First sample intentionally measures cold arrival after teleport,
        # then a second sample after the streamer has had time to settle.
        var arrival := _probe(terrain, x)
        var deadline := Time.get_ticks_msec() + settle_ms
        while Time.get_ticks_msec() < deadline:
            await process_frame
        var settled := _probe(terrain, x)
        var count := 0
        if capture and not headless:
            count = await _capture_site(player, folder, String(site["name"]), profile.ends_with("32"))
        all_sites.append({
            "site": site["name"],
            "original_t_s": site["t"],
            "player_x": x, "player_z": 18.0, "heading": site["direction"],
            "arrival": arrival, "settled": settled,
            "screen_images": count,
            "native_terrain_stats_at_settle": terrain.get_statistics(),
            "mesh_blocks_at_settle": terrain.debug_get_mesh_block_count()
        })
        print("A6B_SITE profile=", profile, " site=", site["name"],
              " arrival_hits=", arrival["original_hits_8"],
              " settled_hits=", settled["original_hits_8"],
              " boundary_missing=", settled["missing_directions_crossing_128m_grid"],
              " split_covered=", settled["split_covered_but_original_failed"])
    var document := {
        "schema": "a6b_probe_v1",
        "profile": profile, "mesh_block_size": terrain.mesh_block_size,
        "lod_count": terrain.lod_count, "view_distance_m": terrain.view_distance,
        "lod_distance_m": terrain.lod_distance,
        "gpu_generation": terrain.use_gpu_generation,
        "rendering_method": RenderingServer.get_current_rendering_method(),
        "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
        "headless": headless, "ci_smoke": ci,
        "seed": int(terrain.get("world_seed")),
        "mode": "teleport_then_settle_not_continuous_stream",
        "settle_ms": settle_ms, "sites": all_sites,
        "frame_budget_pass": "NOT_QUALIFIED",
        "pixel_coverage_pass": "NOT_QUALIFIED",
        "candidate_promoted": false
    }
    var report := folder.path_join("a6b_%s.json" % profile)
    var out := FileAccess.open(report, FileAccess.WRITE)
    if out == null:
        _fail("cannot write " + report)
        return
    out.store_string(JSON.stringify(document, "  "))
    out.close()
    print("A6B_PROBE_REPORT_PASS path=", report, " sites=", all_sites.size(),
          " graphical=", not headless, " pixels=NOT_QUALIFIED")
    world.queue_free()
    quit(0)
