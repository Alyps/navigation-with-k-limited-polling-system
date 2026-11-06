extends CharacterBody2D
## Physical controller that continuously visits random level waypoints.

var navigator: PollingAgent2D
@export_range(1.0, 1000.0, 1.0, "or_greater") var speed: float = 205.0:
	set(value):
		speed = maxf(value, 1.0)
		if is_instance_valid(navigator) and is_instance_valid(navigator.navigator):
			navigator.navigator.max_speed = speed
var destination: Marker2D
var completed_trips: int = 0
var color: Color
var _next: Vector2
var _step: float


func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)
	navigator = PollingAgent2D.new()
	var navigation := NavigationAgent2D.new()
	navigation.radius = 8.0
	navigation.path_desired_distance = 2.0
	navigation.target_desired_distance = 2.0
	navigation.avoidance_enabled = true
	navigation.neighbor_distance = 60.0
	navigation.time_horizon_agents = 0.5
	navigation.max_speed = speed
	navigator.navigator = navigation
	navigator.add_child(navigation)
	add_child(navigator)
	navigator.velocity_computed.connect(_move)
	navigator.target_position = destination.global_position


func _physics_process(delta: float) -> void:
	_step = delta
	_next = navigator.get_next_path_position()
	if navigator.is_navigation_finished():
		completed_trips += 1
		get_parent().get_parent().agent_completed()
		destination = get_parent().get_parent().random_destination(destination)
		navigator.target_position = destination.global_position
		# The wrapper updates its route once per physics frame.
		_next = global_position
		navigator.velocity = Vector2.ZERO
		return
	var offset := _next - global_position
	navigator.velocity = offset.limit_length(speed * delta) / delta
	queue_redraw()


func _move(safe_velocity: Vector2) -> void:
	if _step <= 0.0:
		return
	velocity = safe_velocity.limit_length(global_position.distance_to(_next) / _step)
	move_and_slide()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 8.0, Color("#172b38"))
	draw_circle(Vector2.ZERO, 6.0, color)
	if navigator != null and navigator.state == PollingAgent2D.State.WAITING:
		draw_arc(Vector2.ZERO, 10.0, 0, TAU, 24, Color.WHITE, 1.0)
