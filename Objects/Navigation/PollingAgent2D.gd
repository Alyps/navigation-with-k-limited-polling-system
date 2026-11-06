class_name PollingAgent2D
extends Node2D
## Place at the body origin. NavigationAgent2D is a child of this wrapper.
## The body controller must submit velocity and use velocity_computed.
## The controller must clamp each displacement to the returned waypoint.

signal velocity_computed(safe_velocity: Vector2)

enum State { NAVIGATING, APPROACHING_QUEUE, WAITING, ENTERING, CROSSING }

@export var navigator: NavigationAgent2D

var target_position: Vector2:
	set(value):
		target_position = value
		_has_target = true
		_target_dirty = true

var velocity: Vector2:
	set(value):
		velocity = value
		if is_instance_valid(navigator):
			navigator.velocity = Vector2.ZERO if _holding else value

var state: State = State.NAVIGATING
var _link: PollingLink2D
var _side: int = -1
var _waiting_position: Vector2
var _registered: bool = false
var _has_target: bool = false
var _target_dirty: bool = false
var _holding: bool = true
var _last_frame: int = -1
var _next_position: Vector2
var _normal_target_distance: float
var _aligned_with_entry: bool = false


func _ready() -> void:
	if navigator == null:
		navigator = NavigationAgent2D.new()
		add_child(navigator)
	navigator.path_metadata_flags = NavigationPathQueryParameters2D.PATH_METADATA_INCLUDE_ALL
	_normal_target_distance = navigator.target_desired_distance
	navigator.velocity_computed.connect(_on_velocity_computed)


func get_navigation_map() -> RID:
	return navigator.get_navigation_map()


func is_navigation_finished() -> bool:
	return not _has_target or (
		state == State.NAVIGATING and not _target_dirty and navigator.is_navigation_finished())


func get_next_path_position() -> Vector2:
	var frame := Engine.get_physics_frames()
	if _last_frame == frame:
		return _next_position
	_last_frame = frame
	_next_position = _update_navigation()
	_holding = _next_position.is_equal_approx(global_position)
	if not navigator.avoidance_enabled:
		# Match the asynchronous avoidance callback after the caller sets velocity.
		_emit_unavoided_velocity.call_deferred()
	return _next_position


func _update_navigation() -> Vector2:
	if not _has_target or NavigationServer2D.map_get_iteration_id(get_navigation_map()) == 0:
		return global_position
	_observe_crossing()
	if _target_dirty and state != State.CROSSING:
		if is_instance_valid(_link):
			_link.cancel(self)
		_link = null
		_registered = false
		state = State.NAVIGATING
		navigator.target_desired_distance = _normal_target_distance
		navigator.target_position = target_position
		_target_dirty = false
	if state == State.ENTERING:
		var approach := _link.entry_position(_side) - _link.travel_direction(_side) * (
			_link.agent_radius + _link.clearance + 12.0)
		if not _aligned_with_entry:
			if global_position.distance_to(approach) > _link.arrival_tolerance:
				return approach
			_aligned_with_entry = true
		# The entry boundary is deliberately crossed before reporting an entry.
		return _link.entry_position(_side) + _link.travel_direction(_side) * _link.agent_radius
	if state == State.CROSSING:
		return _link.exit_position(_side) + _link.travel_direction(_side) * (
			_link.agent_radius + _link.clearance)
	if state == State.APPROACHING_QUEUE or state == State.WAITING:
		if global_position.distance_to(_waiting_position) <= _link.arrival_tolerance:
			if not _registered:
				_link.register_arrival(self, _side)
				_registered = true
			state = State.WAITING
			return global_position
		state = State.APPROACHING_QUEUE
		return navigator.get_next_path_position()
	var next := navigator.get_next_path_position()
	var result := navigator.get_current_navigation_result()
	for index in range(navigator.get_current_navigation_path_index(), result.path.size()):
		if result.path_types[index] != NavigationPathQueryResult2D.PATH_SEGMENT_TYPE_LINK:
			continue
		var owner := instance_from_id(result.path_owner_ids[index]) as PollingLink2D
		if owner == null:
			continue
		_link = owner
		_side = PollingLink2D.Side.LEFT
		if result.path[index].distance_squared_to(owner.entry_position(1)) < result.path[index].distance_squared_to(owner.entry_position(0)):
			_side = PollingLink2D.Side.RIGHT
		if not owner.request(self, _side):
			_link = null
			return global_position
		state = State.APPROACHING_QUEUE
		return global_position
	return next


func assign_waiting_position(position: Vector2) -> void:
	_waiting_position = position
	navigator.target_desired_distance = minf(navigator.target_desired_distance, _link.arrival_tolerance)
	navigator.target_position = position


func is_ready_for_entry() -> bool:
	return _registered and global_position.distance_to(_waiting_position) <= _link.arrival_tolerance


func grant_entry() -> void:
	_aligned_with_entry = false
	state = State.ENTERING


func _observe_crossing() -> void:
	if not is_instance_valid(_link):
		return
	var direction := _link.travel_direction(_side)
	if state == State.ENTERING and _aligned_with_entry:
		var progress := (global_position - _link.entry_position(_side)).dot(direction)
		if progress >= -_link.agent_radius:
			_link.confirm_entry(self)
			state = State.CROSSING
	if state == State.CROSSING:
		var progress := (global_position - _link.exit_position(_side)).dot(direction)
		if progress >= _link.agent_radius:
			_link.confirm_exit(self)
			_link = null
			_registered = false
			state = State.NAVIGATING
			_target_dirty = true


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity_computed.emit(Vector2.ZERO if _holding else safe_velocity)


func _emit_unavoided_velocity() -> void:
	_on_velocity_computed(velocity)


func _exit_tree() -> void:
	if is_instance_valid(_link):
		# Removing the body is an explicit removal from the physical passage.
		_link.confirm_exit(self)
		_link.cancel(self)
