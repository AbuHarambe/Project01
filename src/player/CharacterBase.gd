extends CharacterBody2D

@export var move_speed: float = 250.0
@export var jump_force: float = 500.0
@export var gravity: float = 1400.0

func _physics_process(delta: float) -> void:
	handle_movement(delta)
	move_and_slide()

func handle_movement(delta: float) -> void:
	# Horizontal movement
	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * move_speed

	# Jumping
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = -jump_force
	else:
		# Apply gravity while in the air
		velocity.y += gravity * delta
