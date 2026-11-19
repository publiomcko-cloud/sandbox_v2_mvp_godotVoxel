extends SceneTree
# A6 graphical factorial: all four profiles run in Vulkan Forward+.
# A2 runtime is reused unchanged across arms apart from extra metadata.
# Headless smoke may execute only CPU arms, and is NOT a performance test.
const Profiles = preload("res://tests/a6_profiles.gd")
const Routes = preload("res://tests/a2_routes.gd")
const Runtime = preload("res://tests/a2_runtime.gd")

func _initialize() -> void:
    call_deferred("_start")

func _arg(name: String, fallback: String) -> String:
    var prefix := "--" + name + "="
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with(prefix):
            return arg.substr(prefix.length())
    return fallback

func _flag(name: String) -> bool:
    return OS.get_cmdline_user_args().has("--" + name)

func _fail(message: String, code: int = 2) -> void:
    push_error("A6_CONFIG_FAIL: " + message)
    quit(code)

func _start() -> void:
    var profile := _arg("profile", "")
    var route := _arg("route", "out_and_back_18mps_300s")
    var duration := float(_arg("duration", str(Routes.duration_for(route))))
    var warmup := float(_arg("warmup", "45"))
    var headless := DisplayServer.get_name() == "headless"
    var ci := _flag("ci-smoke")
    if Profiles.config(profile).is_empty():
        _fail("invalid profile " + profile)
        return
    var nominal := Routes.duration_for(route)
    if nominal <= 0.0 or duration <= 0.0 or duration > nominal or warmup < 0.0 or warmup > 180.0:
        _fail("invalid route/duration/warmup")
        return

    var method := RenderingServer.get_current_rendering_method()
    var driver := RenderingServer.get_current_rendering_driver_name()
    if headless:
        if not ci or bool(Profiles.config(profile)["use_gpu_generation"]):
            _fail("GPU/graphics cannot be qualified headless; cpu-only smoke explicitly allowed", 4)
            return
    else:
        if method != "gl_compatibility" and method != "forward_plus":
            _fail("unsupported rendering method: " + method, 4)
            return
        # ALL graphical arms require the same Vulkan renderer, including CPU.
        if method != "forward_plus" or driver.to_lower() != "vulkan" or RenderingServer.get_rendering_device() == null:
            _fail("graphical A6 requires Forward+ Vulkan (CPU and GPU); got %s/%s" % [method, driver], 4)
            return
    if not headless:
        DisplayServer.window_set_size(Vector2i(1920, 1080))
        root.size = Vector2i(1920, 1080)

    var packed: PackedScene = load("res://scenes/main.tscn")
    if packed == null:
        _fail("cannot load main scene")
        return
    var world := packed.instantiate()
    if not Profiles.apply_to_scene(world, profile):
        _fail("could not apply isolated profile before streaming")
        return
    root.add_child(world)
    var terrain := world.get_node("Terrain") as VoxelLodTerrain
    if terrain.mesh_block_size != int(Profiles.config(profile)["mesh_block_size"]) or terrain.use_gpu_generation != bool(Profiles.config(profile)["use_gpu_generation"]):
        _fail("terrain settings drifted upon tree activation")
        return
    var runner := Runtime.new()
    runner.route = route
    runner.duration_sec = duration
    runner.warmup_sec = warmup
    runner.ci_smoke = ci
    runner.capture_screenshots = _flag("capture")
    runner.a6_profile = profile
    world.add_child(runner)
    print("A6_PROFILE_APPLIED profile=", profile, " mesh_block=", terrain.mesh_block_size,
          " gpu_requested=", terrain.use_gpu_generation, " renderer=", method,
          " driver=", driver, " headless=", headless)
