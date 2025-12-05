extends CharacterBody2D

@export var move_speed: float = 250.0
@export var jump_force: float = 500.0
@export var gravity: float = 1400.0
@export var fast_fall_multiplier: float = 2.0

# Jump Variables 
@export var can_ground_jump: bool = true
@export var max_air_jumps: int = 3 # used as "max non-ground jumps" (air + wall)
@export var can_wall_jump: bool = true
@export var wall_jump_force: float = 500.0
@export var wall_jump_horizontal_force: float = 350.0
@export var wall_slide_gravity_multiplier: float = 0.3
@export var max_wall_slide_speed: float = 200.0
@export var wall_jump_lock_time: float = 0.16
var wall_jump_lock_timer: float = 0.0

# Dash Variables
@export var dash_speed: float = 550.0
@export var dash_duration: float = 0.18
@export var dash_freeze_duration: float = 0.1
@export var dash_cooldown_ground: float = 1
@export var dash_cooldown_air: float = 2

# Attack Variables (placeholder for Light Neutral on ground)
@export var light_attack_total_time: float = 0.3
@export var light_attack_move_lock_time: float = 0.2

var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_move_lock_timer: float = 0.0


# Non-ground jump pool (air + wall)
var remaining_non_ground_jumps: int = 0
var wall_refresh_used: bool = false  # whether the +1 from wall has been used this airtime

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_freeze_timer: float = 0.0
var dash_direction: Vector2 = Vector2.ZERO
var dash_cooldown_timer: float = 0.0

func _physics_process(delta: float) -> void:
	update_dash_timers(delta)
	wall_jump_lock_timer = max(wall_jump_lock_timer - delta, 0.0)
	update_attack_timers(delta)
	handle_dash_input()
	handle_movement(delta)
	move_and_slide()

func update_dash_timers(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
		if dash_cooldown_timer < 0.0:
			dash_cooldown_timer = 0.0

	if is_dashing:
		if dash_freeze_timer > 0.0:
			dash_freeze_timer -= delta
			if dash_freeze_timer < 0.0:
				dash_freeze_timer = 0.0

		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			dash_direction = Vector2.ZERO

func handle_dash_input() -> void:
	if is_dashing:
		return
	if is_attacking:
		return
	if dash_cooldown_timer > 0.0:
		return
		
	if Input.is_action_just_pressed("dash"):
		# Horizontal input
		var horiz := Input.get_axis("move_left", "move_right")
		# Vertical input only while airborne (up = jump, down = move_down)
		var vert := 0.0
		if not is_on_floor():
			if Input.is_action_pressed("move_down"):
				vert = 1.0
			elif Input.is_action_pressed("jump"):
				vert = -1.0

		var input_dir := Vector2(horiz, vert)

		if input_dir == Vector2.ZERO:
			# Neutral dash: full stall
			dash_direction = Vector2.ZERO
			dash_freeze_timer = dash_freeze_duration
			dash_timer = dash_freeze_duration
		else:
			# Omni-directional dash
			dash_direction = input_dir.normalized()
			var dash_vec := dash_direction * dash_speed

			# Apply initial dash velocity (omni-directional)
			velocity.x = dash_vec.x
			# Only override vertical if there is a vertical component
			if abs(dash_direction.y) > 0.0:
				velocity.y = dash_vec.y

			dash_freeze_timer = 0.0
			dash_timer = dash_duration

		is_dashing = true

		var cooldown := dash_cooldown_air
		if is_on_floor():
			cooldown = dash_cooldown_ground

		dash_cooldown_timer = cooldown

func update_attack_timers(delta: float) -> void:
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			is_attacking = false
			attack_timer = 0.0

	if attack_move_lock_timer > 0.0:
		attack_move_lock_timer -= delta
		if attack_move_lock_timer < 0.0:
			attack_move_lock_timer = 0.0


func handle_movement(delta: float) -> void:
	# 1) NEUTRAL DASH STALL: completely frozen for a brief moment
	if is_dashing and dash_direction == Vector2.ZERO and dash_freeze_timer > 0.0:
		velocity.x = 0.0
		velocity.y = 0.0
		return

	# 2) Horizontal control (only if not in dash, wall-jump lock, or attack lock)
	if is_dashing and dash_direction != Vector2.ZERO:
		# During directional dash, we don't change velocity.x from input
		pass
	elif wall_jump_lock_timer > 0.0:
		# During wall-jump lock: keep current velocity.x, ignore input
		pass
	elif attack_move_lock_timer > 0.0:
		# During attack movement lock: keep current velocity.x, ignore input
		pass
	else:
		var dir := Input.get_axis("move_left", "move_right")
		velocity.x = dir * move_speed

	# 3) Gravity + wall slide + fast-fall
	if is_on_floor():
		# Reset non-ground jump pool and wall refresh on landing
		remaining_non_ground_jumps = max_air_jumps
		wall_refresh_used = false
	else:
		var current_gravity := gravity

		var on_wall := is_on_wall() and not is_on_floor()

		# Wall slide: only when pushing into the wall and moving downward
		if on_wall and not is_dashing:
			var wall_normal := get_wall_normal()
			var move_dir := Input.get_axis("move_left", "move_right")
			# Pushing into the wall = input direction opposite wall normal.x
			var pushing_into_wall := move_dir != 0.0 and move_dir * wall_normal.x < 0.0

			if pushing_into_wall and velocity.y >= 0.0:
				# Reduce gravity while sliding on the wall
				current_gravity *= wall_slide_gravity_multiplier

				# Clamp max slide speed
				if velocity.y > max_wall_slide_speed:
					current_gravity = 0.0
		else:
			# Fast-fall (only when not in a dash and not sliding on wall)
			if not is_dashing and Input.is_action_pressed("move_down") and velocity.y > 0.0:
				current_gravity *= fast_fall_multiplier

		velocity.y += current_gravity * delta

	# 4) Jumping (ground, wall, air) with shared non-ground pool
	if Input.is_action_just_pressed("jump"):
		var on_wall := is_on_wall() and not is_on_floor()

		if is_on_floor() and can_ground_jump:
			# Ground jump does NOT consume the non-ground pool
			velocity.y = -jump_force

		elif on_wall and can_wall_jump and remaining_non_ground_jumps > 0:
			# Wall jump: always AWAY from the wall
			var wall_normal := get_wall_normal()

			# Fallbacks in case wall_normal is weird/zero
			if wall_normal == Vector2.ZERO:
				var horiz_input := Input.get_axis("move_left", "move_right")
				if horiz_input > 0.0:
					wall_normal = Vector2(1.0, 0.0)  # wall on the right
				elif horiz_input < 0.0:
					wall_normal = Vector2(-1.0, 0.0) # wall on the left
				elif velocity.x > 0.0:
					wall_normal = Vector2(1.0, 0.0)
				elif velocity.x < 0.0:
					wall_normal = Vector2(-1.0, 0.0)

			if wall_normal != Vector2.ZERO:
				var away_dir := wall_normal.normalized()
				velocity.y = -wall_jump_force
				velocity.x = away_dir.x * wall_jump_horizontal_force
				wall_jump_lock_timer = wall_jump_lock_time

			# Consume one non-ground jump
			remaining_non_ground_jumps -= 1

			# If this was the LAST jump in the pool and we haven't used the wall refresh yet,
			# grant +1 extra jump (max total non-ground jumps this airtime = max_air_jumps + 1)
			if remaining_non_ground_jumps == 0 and not wall_refresh_used:
				remaining_non_ground_jumps += 1
				wall_refresh_used = true

		elif not is_on_floor() and not on_wall and remaining_non_ground_jumps > 0:
			# Normal air jump (but NOT when touching a wall)
			velocity.y = -jump_force
			remaining_non_ground_jumps -= 1
			
	# 5) Ground Light Attack (placeholder)
	if Input.is_action_just_pressed("attack_light") and is_on_floor() and not is_attacking:
		is_attacking = true
		attack_timer = light_attack_total_time
		attack_move_lock_timer = light_attack_move_lock_time
		# Later: play attack animation, enable hitboxes, etc.
