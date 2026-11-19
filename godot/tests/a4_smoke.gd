extends SceneTree
# Two separate processes: native VoxelInstancer static removal to rigid body,
# save via terrain SQLite + sidecar; reopen validates identity/state/instances.
const TEST_AREA := Vector3(0, 7, 0)
const REMOVE_RADIUS := 28.0
const MAX_WAIT_MS := 60000

func _initialize() -> void:
    call_deferred("_verify")

func _fail(msg: String) -> void:
    push_error("A4_SMOKE_FAIL " + msg)
    quit(1)

func _phase() -> String:
    for arg in OS.get_cmdline_user_args():
        if arg == "--phase=write":
            return "write"
        if arg == "--phase=reopen":
            return "reopen"
    return ""

func _report(phase: String, values: Dictionary) -> void:
    var target := OS.get_environment("A4_RESULTS_DIR")
    if target.is_empty():
        return
    var f := FileAccess.open(target.path_join("a4_%s.json" % phase), FileAccess.WRITE)
    if f == null:
        push_error("A4_REPORT_WRITE_FAIL")
        return
    values["phase"] = phase
    values["visual_130_gate"] = "NOT_QUALIFIED"
    values["physics_terrain_collision_gate"] = "NOT_QUALIFIED"
    values["cpu_gpu_frame_gate"] = "NOT_QUALIFIED"
    f.store_string(JSON.stringify(values, "  "))
    f.close()

func _verify() -> void:
    var phase := _phase()
    if phase.is_empty() or OS.get_environment("A3_SAVE_PATH").is_empty() or OS.get_environment("A4_ROCK_STATE_PATH").is_empty():
        _fail("isolated save paths and phase required")
        return
    var world: Node3D = load("res://scenes/main.tscn").instantiate()
    root.add_child(world)
    await process_frame
    var terrain: VoxelLodTerrain = world.get_node("Terrain")
    var instancer: VoxelInstancer = world.get_node("Terrain/RockInstancer")
    var manager: Node3D = world.get_node("RockManager")
    var player: Node3D = world.get_node("Player")
    if instancer == null or not instancer.library is VoxelInstanceLibrary or manager == null:
        _fail("instancer/manager/library unavailable")
        return
    var item = instancer.library.get_item(100)
    if item == null or not item.persistent or item.lod_index != 2:
        _fail("rock item persistence or LOD is wrong")
        return
    player.global_position = Vector3(0, 21, 8)
    var limit := Time.get_ticks_msec() + MAX_WAIT_MS
    var static_count := 0
    while Time.get_ticks_msec() < limit:
        await process_frame
        static_count = int(instancer.debug_get_instance_counts().get(100, 0))
        if static_count >= 20:
            break
    if static_count < 20:
        _fail("native rocks did not load: " + str(static_count))
        return
    # Let the streamer stabilize for a fixed interval, no favorable snapshots.
    var settle := Time.get_ticks_msec() + 1000
    while Time.get_ticks_msec() < settle:
        await process_frame
    static_count = int(instancer.debug_get_instance_counts().get(100, 0))
    if phase == "write":
        instancer.remove_instances_in_sphere(instancer.to_local(TEST_AREA), REMOVE_RADIUS)
        var promotion_limit := Time.get_ticks_msec() + 10000
        while int(manager.call("persisted_body_count")) <= 0 and Time.get_ticks_msec() < promotion_limit:
            await process_frame
        var promoted := int(manager.call("persisted_body_count"))
        if promoted <= 0:
            _fail("native promotion did not create RigidBody3D")
            return
        # The original source-rock transform must survive removal_scene
        # instantiation. A repeated origin (0,0,0) is a hard failure.
        var identities: Dictionary = {}
        for child in manager.get_children():
            if not (child is RigidBody3D):
                continue
            var body_id := String(child.get("rock_id"))
            if identities.has(body_id):
                _fail("duplicated promoted identity: " + body_id)
                return
            identities[body_id] = true
            if child.global_position.distance_to(TEST_AREA) > REMOVE_RADIUS + 4.0:
                _fail("promoted body lost its source transform: " + str(child.global_position))
                return
        if identities.size() != promoted:
            _fail("unregistered/missing promoted bodies: registered=%d children=%d" % [promoted, identities.size()])
            return
        if int(manager.call("active_body_count")) > 24:
            _fail("dynamic body budget exceeded")
            return
        var after_count := int(instancer.debug_get_instance_counts().get(100, 0))
        if after_count >= static_count:
            _fail("static count did not decrease after promotion")
            return
        if promoted < static_count - after_count:
            _fail("lost promoted bodies: removed=%d spawned=%d" % [static_count-after_count, promoted])
            return
        # Ensure no more dynamic bodies are created from exactly the same
        # selection; removed native instances must not be duplicated.
        instancer.remove_instances_in_sphere(instancer.to_local(TEST_AREA), REMOVE_RADIUS)
        await process_frame
        await process_frame
        if int(manager.call("persisted_body_count")) != promoted:
            _fail("same native rocks promoted twice")
            return
        var tracker: VoxelSaveCompletionTracker = terrain.save_modified_blocks()
        if tracker == null:
            _fail("terrain/instance save tracker absent")
            return
        var save_limit := Time.get_ticks_msec() + 60000
        while not tracker.is_complete() and not tracker.is_aborted():
            if Time.get_ticks_msec() > save_limit:
                _fail("native save tracker timed out")
                return
            await process_frame
        if tracker.is_aborted():
            _fail("native save tracker aborted")
            return
        terrain.stream.flush()
        if not bool(manager.call("save_states")):
            _fail("sidecar failed to write")
            return
        if not FileAccess.file_exists(OS.get_environment("A3_SAVE_PATH")) or not FileAccess.file_exists(OS.get_environment("A4_ROCK_STATE_PATH")):
            _fail("SQLite or JSON missing")
            return
        _report(phase, {
            "static_count_before": static_count,
            "static_count_after": after_count,
            "promoted_count": promoted,
            "active_count": int(manager.call("active_body_count")),
            "native_blocks": instancer.debug_get_block_count()
        })
        print("A4_PROMOTION_SAVE_PASS before=", static_count, " after=", after_count, " bodies=", promoted)
    else:
        var loaded_bodies := int(manager.call("persisted_body_count"))
        if loaded_bodies <= 0 or loaded_bodies != int(manager.call("get_report").get("restored_bodies", 0)):
            _fail("promoted bodies not restored from sidecar")
            return
        if int(manager.call("active_body_count")) > 24:
            _fail("body budget exceeded on reopen")
            return
        # On reopen, native VoxelStreamSQLite must still have instancing
        # removals. Cross-process report compares live counts on same route.
        _report(phase, {
            "static_count_reopened": static_count,
            "promoted_count_reopened": loaded_bodies,
            "active_count": int(manager.call("active_body_count")),
            "native_blocks": instancer.debug_get_block_count()
        })
        print("A4_REOPEN_PASS static=", static_count, " restored_bodies=", loaded_bodies)
    world.queue_free()
    quit(0)
