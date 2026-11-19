extends Node3D
# A0 diagnostic free-fly camera, not the final physics character.
const SPEED_MPS := 18.0

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
        position += motion.normalized() * SPEED_MPS * delta
