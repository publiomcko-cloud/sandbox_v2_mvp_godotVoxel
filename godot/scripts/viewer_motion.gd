extends Node3D
# A1 free-flight observer, NOT a physics character. Movement remains 18 m/s.
const SPEED_MPS := 18.0
const MOUSE_SENSITIVITY := 0.0025
var pitch := deg_to_rad(-22.0)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -1.48, 1.48)
        $Camera3D.rotation.x = pitch

func _process(delta: float) -> void:
    var motion := Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        motion.z -= 1.0
    if Input.is_key_pressed(KEY_S):
        motion.z += 1.0
    if Input.is_key_pressed(KEY_A):
        motion.x -= 1.0
    if Input.is_key_pressed(KEY_D):
        motion.x += 1.0
    if Input.is_key_pressed(KEY_E):
        motion.y += 1.0
    if Input.is_key_pressed(KEY_Q):
        motion.y -= 1.0
    if motion != Vector3.ZERO:
        translate(motion.normalized() * SPEED_MPS * delta)
