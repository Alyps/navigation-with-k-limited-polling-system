extends SceneTree
## Run with Godot --headless --path <project> --script res://Tests/PollingTest.gd

class Client extends Node2D:
	var waiting_position: Vector2
	var grants: int = 0

	func assign_waiting_position(value: Vector2) -> void:
		waiting_position = value

	func is_ready_for_entry() -> bool:
		return true

	func grant_entry() -> void:
		grants += 1


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)


func _run() -> void:
	_test_dispatcher()
	await _test_navigation(false)
	await _test_navigation(true)
	print("PASS: quota, fixed group, cancellation, slot reuse, direction lock, navigation and goal preservation")
	quit()


func _make_slots(link: PollingLink2D, count: int) -> void:
	for index in range(count):
		var left := Marker2D.new()
		var right := Marker2D.new()
		left.position = Vector2(-40 - index * 22, 40)
		right.position = Vector2(140 + index * 22, 40)
		link.add_child(left)
		link.add_child(right)
		link.left_slots.append(left)
		link.right_slots.append(right)


func _test_dispatcher() -> void:
	var link := PollingLink2D.new()
	link.k_max = 3
	link.start_position = Vector2.ZERO
	link.end_position = Vector2(100, 0)
	_make_slots(link, 4)
	root.add_child(link)
	link.set_physics_process(false)
	var first := Client.new()
	var second := Client.new()
	var opposite := Client.new()
	var late := Client.new()
	for client in [first, second, opposite, late]:
		root.add_child(client)
	_check(link.request(first, 0), "First reservation")
	_check(link.request(second, 0), "Second reservation")
	_check(link.request(opposite, 1), "Opposite reservation")
	link.register_arrival(first, 0)
	link.register_arrival(second, 0)
	link.register_arrival(opposite, 1)
	link._physics_process(0)
	_check(link.permitted == first and link.pending == [second], "Adaptive quota must select two")
	_check(link.request(late, 0), "Late reservation")
	link.register_arrival(late, 0)
	_check(not link.pending.has(late), "Late arrival must not expand selected group")
	first.position = Vector2(40, 0)
	link.confirm_entry(first)
	link._physics_process(0)
	_check(link.permitted == second, "Second permit follows first entry")
	link.confirm_exit(first)
	link._physics_process(0)
	_check(link.active_side == 0 and opposite.grants == 0, "Outstanding permit must lock direction")
	_check(link.cancel(second), "Permit cancellation acknowledged by caller")
	link._physics_process(0)
	_check(link.active_side == 1 and link.permitted == opposite, "Switch after cancellation and empty passage")
	_check(late.waiting_position == link.left_slots[0].global_position, "Compaction preserves late request")
	link.cancel(late)
	link.cancel(opposite)
	_check(link.request(first, 0) and link.request(second, 0), "Reserve two slots again")
	link.cancel(first)
	_check(link.request(late, 0), "Reuse a cancelled reservation")
	_check(late.waiting_position == link.left_slots[0].global_position, "Reuse lowest free slot")
	_check(late.waiting_position != second.waiting_position, "Reservations must remain unique")
	link.cancel(late)
	link.cancel(second)
	for client in [first, second, opposite, late]:
		client.free()
	link.free()


func _region(points: PackedVector2Array) -> NavigationRegion2D:
	var polygon := NavigationPolygon.new()
	polygon.vertices = points
	polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var region := NavigationRegion2D.new()
	region.navigation_polygon = polygon
	region.use_edge_connections = false
	root.add_child(region)
	return region


func _test_navigation(reverse: bool) -> void:
	var left := _region(PackedVector2Array([
		Vector2(-250, -100), Vector2(0, -100), Vector2(0, 100), Vector2(-250, 100)]))
	var right := _region(PackedVector2Array([
		Vector2(100, -100), Vector2(350, -100), Vector2(350, 100), Vector2(100, 100)]))
	var link := PollingLink2D.new()
	link.start_position = Vector2(-1, 0)
	link.end_position = Vector2(101, 0)
	_make_slots(link, 4)
	root.add_child(link)
	var agent := PollingAgent2D.new()
	agent.position = Vector2(250, 0) if reverse else Vector2(-180, 0)
	root.add_child(agent)
	var goal := Vector2(-180, 0) if reverse else Vector2(250, 0)
	agent.target_position = goal
	var saw_queue := false
	var saw_crossing := false
	var changed_goal := false
	var completed := false
	for frame in range(1200):
		await physics_frame
		var next := agent.get_next_path_position()
		if agent.state == PollingAgent2D.State.APPROACHING_QUEUE or agent.state == PollingAgent2D.State.WAITING:
			saw_queue = true
			_check(not agent.is_navigation_finished(), "Queue arrival must not finish final navigation")
		if agent.state == PollingAgent2D.State.CROSSING:
			saw_crossing = true
			if not changed_goal:
				goal = Vector2(-200, 30) if reverse else Vector2(280, 30)
				agent.target_position = goal
				changed_goal = true
		_check(agent.target_position == goal, "Public goal must survive temporary navigation")
		agent.position = agent.position.move_toward(next, 2.0)
		if saw_crossing and agent.is_navigation_finished():
			completed = true
			break
	_check(saw_queue and saw_crossing and completed, "Agent must discover, queue, cross and resume")
	_check(link.inside.is_empty() and link.permitted == null, "Completed agent must release passage")
	_check(agent.position.distance_to(goal) <= agent.navigator.target_desired_distance + 2, "Latest goal must be reached")
	agent.free()
	link.free()
	left.free()
	right.free()
