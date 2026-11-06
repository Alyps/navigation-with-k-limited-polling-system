extends CharacterBody2D

@export var speed := 82.0
@onready var navigator: NavigationAgent2D = $NavigationAgent2D
var level: ResearchLevel
var destination: Marker2D

func _ready() -> void:
	var ancestor := get_parent()
	while ancestor and not ancestor is ResearchLevel:
		ancestor = ancestor.get_parent()
	level = ancestor as ResearchLevel
	navigator.velocity_computed.connect(_move)

func _physics_process(_delta: float) -> void:
	if not level:
		return
	var map := navigator.get_navigation_map()
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return
	if not destination:
		if not level.contains_position(global_position):
			return
		_pick_destination()
	elif navigator.is_navigation_finished():
		_pick_destination()
	if destination:
		var next := navigator.get_next_path_position()
		navigator.velocity = global_position.direction_to(next) * speed

func _pick_destination() -> void:
	destination = level.random_destination(destination)
	if destination:
		navigator.target_position = destination.global_position

func _move(safe_velocity: Vector2) -> void:
	if destination:
		velocity = safe_velocity
		move_and_slide()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 8, Color("#172b38"), true, -1, true)
	draw_circle(Vector2.ZERO, 6, Color("#ffd079"), true, -1, true)
