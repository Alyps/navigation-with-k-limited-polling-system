extends Camera2D

@export var pan_speed := 480.0

func _process(delta: float) -> void:
	var direction := Vector2(
		int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
		int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	)
	position += direction.normalized() * pan_speed * delta / zoom
