extends ResearchLevel
## Agents continuously choose random waypoints using ResearchLevel's policy.
## Queue geometry and dispatcher parameters are editable in the scene.

const BODY := preload("res://TestScenes/PollingTestBody.gd")
const LEFT_COLOR := Color("#ffd079")
const RIGHT_COLOR := Color("#70d7f0")

@export var scenario_title: String = ""
@export_range(1.0, 1000.0, 1.0, "or_greater") var agent_speed: float = 205.0:
	set(value):
		agent_speed = maxf(value, 1.0)
		if is_node_ready():
			for body in $Agents.get_children():
				body.speed = agent_speed

var completed: int = 0
var total: int = 0
var elapsed: float = 0.0
var _label: Label
var _smoke: bool = false
var _max_inside: int = 0


func _ready() -> void:
	_smoke = "--polling-smoke" in OS.get_cmdline_user_args()
	if _smoke:
		seed(42)
	for point: Marker2D in $Waypoints.get_children():
		destinations.append(point)
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	overlay.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(_label)
	# Link children have completed _ready before reservations are created.
	for link: PollingLink2D in $Links.get_children():
		for side in [0, 1]:
			var slots: Array[Marker2D] = link.left_slots if side == 0 else link.right_slots
			for slot in slots:
				var body := CharacterBody2D.new()
				body.set_script(BODY)
				body.speed = agent_speed
				body.position = $Agents.to_local(slot.global_position)
				body.destination = random_destination(null)
				body.color = LEFT_COLOR if side == 0 else RIGHT_COLOR
				$Agents.add_child(body)
				total += 1
	queue_redraw()


func agent_completed() -> void:
	completed += 1


func _physics_process(delta: float) -> void:
	elapsed += delta
	var lines: PackedStringArray = [
		scenario_title,
		"Agents %d   Trips %d   Time %.1f s   R: restart   WASD: camera" % [$Agents.get_child_count(), completed, elapsed],
		"Gold / cyan: initial groups   White ring: waiting"]
	for link: PollingLink2D in $Links.get_children():
		_max_inside = maxi(_max_inside, link.inside.size())
		lines.append("%s   Q %d / %d   Pending %d   Permit %d   Inside %d" % [
			link.name, link.queues[0].size(), link.queues[1].size(),
			link.pending.size(), int(link.permitted != null), link.inside.size()])
		for agent in link.inside:
			if agent._side != link.active_side:
				push_error("Opposing directions inside " + str(link.name))
				if _smoke:
					get_tree().quit(1)
	_label.text = "\n".join(lines)
	queue_redraw()
	if _smoke and $Agents.get_child_count() != total:
		push_error("Agent count changed during continuous simulation")
		get_tree().quit(1)
	if _smoke and elapsed >= 120.0:
		var repeating_agents: int = 0
		for body in $Agents.get_children():
			if body.completed_trips >= 2:
				repeating_agents += 1
		if repeating_agents == 0:
			push_error("No agent completed a second trip")
			get_tree().quit(1)
		else:
			print("PASS %s: %d agents retained; %d trips; %d agents completed multiple trips in %.2fs" % [
				name, total, completed, repeating_agents, elapsed])
			get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()


func _draw() -> void:
	for link: PollingLink2D in $Links.get_children():
		var start := to_local(link.entry_position(0))
		var end := to_local(link.entry_position(1))
		draw_line(start, end, Color("#8fba91"), 3.0)
		for side in [0, 1]:
			var slots: Array[Marker2D] = link.left_slots if side == 0 else link.right_slots
			var tint := LEFT_COLOR if side == 0 else RIGHT_COLOR
			for slot in slots:
				draw_arc(to_local(slot.global_position), 9.0, 0, TAU, 24, Color(tint, 0.5), 1.0)
