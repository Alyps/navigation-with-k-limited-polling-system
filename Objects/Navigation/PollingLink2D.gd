class_name PollingLink2D
extends NavigationLink2D
## Dispatcher for a straight passage. Endpoints mark its physical boundaries.
## Queue markers must be ordered from the head and keep the exit lane clear.

enum Side { LEFT, RIGHT }

@export_range(1, 128) var k_max: int = 8
@export var left_slots: Array[Marker2D] = []
@export var right_slots: Array[Marker2D] = []
@export var agent_radius: float = 8.0
@export var clearance: float = 2.0
@export var arrival_tolerance: float = 1.0
@export var minimum_entry_interval: float = 0.0
## Set false if the scene controller detects a blocked exit.
@export var exit_available: bool = true

var queues: Array = [[], []]
var reservations: Array = [[], []]
var pending: Array[Node2D] = []
var permitted: Node2D
var inside: Array[Node2D] = []
var active_side: int = -1
var previous_side: int = -1
var _registration_frames: Dictionary = {}
var _assigned_slots: Dictionary = {}
var _last_entry_time: float = -INF
var _compacted: bool = false
var _simulation_time: float = 0.0


func _ready() -> void:
	process_physics_priority = 100


func entry_position(side: int) -> Vector2:
	return to_global(start_position if side == Side.LEFT else end_position)


func exit_position(side: int) -> Vector2:
	return entry_position(1 - side)


func travel_direction(side: int) -> Vector2:
	return entry_position(side).direction_to(exit_position(side))


func request(agent: Node2D, side: int) -> bool:
	if side != Side.LEFT and side != Side.RIGHT:
		return false
	if side == Side.RIGHT and not bidirectional:
		return false
	if not enabled or reservations[side].size() >= _slots(side).size():
		return false
	if reservations[0].has(agent) or reservations[1].has(agent) or inside.has(agent):
		return false
	var slot_index: int = 0
	var occupied: Array[int] = []
	for other in reservations[side]:
		occupied.append(_assigned_slots[other])
	while occupied.has(slot_index):
		slot_index += 1
	reservations[side].append(agent)
	_assigned_slots[agent] = slot_index
	agent.assign_waiting_position(_slots(side)[slot_index].global_position)
	return true


func register_arrival(agent: Node2D, side: int) -> void:
	if not reservations[side].has(agent) or queues[side].has(agent):
		return
	_registration_frames[agent] = Engine.get_physics_frames()
	queues[side].append(agent)
	queues[side].sort_custom(_registered_before)


func confirm_entry(agent: Node2D) -> void:
	if permitted != agent:
		return
	permitted = null
	queues[active_side].erase(agent)
	reservations[active_side].erase(agent)
	_assigned_slots.erase(agent)
	_registration_frames.erase(agent)
	inside.append(agent)
	_last_entry_time = _now()


func confirm_exit(agent: Node2D) -> void:
	inside.erase(agent)


func cancel(agent: Node2D) -> bool:
	# Entered bodies retain ownership until a confirmed physical exit.
	if inside.has(agent):
		return false
	pending.erase(agent)
	if permitted == agent:
		permitted = null
	for side in [Side.LEFT, Side.RIGHT]:
		queues[side].erase(agent)
		reservations[side].erase(agent)
	_registration_frames.erase(agent)
	_assigned_slots.erase(agent)
	return true


func _physics_process(delta: float) -> void:
	_simulation_time += delta
	if active_side != -1 and pending.is_empty() and permitted == null:
		if not _compacted:
			_reassign(active_side)
			_compacted = true
		if not inside.is_empty():
			return
		previous_side = active_side
		active_side = -1
	if active_side == -1:
		_begin_visit()
	if active_side == -1 or pending.is_empty() or permitted != null:
		return
	var head: Node2D = pending[0]
	if not is_instance_valid(head):
		return
	if exit_available and head.is_ready_for_entry() and _entry_spacing_is_safe():
		permitted = pending.pop_front()
		permitted.grant_entry()


func _begin_visit() -> void:
	if queues[0].is_empty() and queues[1].is_empty():
		return
	if queues[0].is_empty():
		active_side = Side.RIGHT
	elif queues[1].is_empty():
		active_side = Side.LEFT
	elif previous_side != -1:
		active_side = 1 - previous_side
	else:
		var left_frame: int = _registration_frames[queues[0][0]]
		var right_frame: int = _registration_frames[queues[1][0]]
		active_side = Side.LEFT if left_frame <= right_frame else Side.RIGHT
	_reassign(active_side)
	var count: int = queues[active_side].size()
	var total: int = queues[0].size() + queues[1].size()
	var quota := mini(count, 1 + floori(float(maxi(k_max, 1) - 1) * count / total))
	pending.assign(queues[active_side].slice(0, quota))
	_compacted = false
	_last_entry_time = -INF


func _reassign(side: int) -> void:
	var ordered: Array = queues[side].duplicate()
	for agent in reservations[side]:
		if not ordered.has(agent):
			ordered.append(agent)
	reservations[side] = ordered
	for index in range(ordered.size()):
		_assigned_slots[ordered[index]] = index
		ordered[index].assign_waiting_position(_slots(side)[index].global_position)


func _entry_spacing_is_safe() -> bool:
	if _now() - _last_entry_time < minimum_entry_interval:
		return false
	for agent in inside:
		if not is_instance_valid(agent):
			return false
		var progress: float = (agent.global_position - entry_position(active_side)).dot(
			travel_direction(active_side))
		if progress < 2.0 * agent_radius + clearance:
			return false
	return true


func _registered_before(first: Node2D, second: Node2D) -> bool:
	if _registration_frames[first] == _registration_frames[second]:
		return first.get_instance_id() < second.get_instance_id()
	return _registration_frames[first] < _registration_frames[second]


func _slots(side: int) -> Array[Marker2D]:
	return left_slots if side == Side.LEFT else right_slots


func _now() -> float:
	return _simulation_time
