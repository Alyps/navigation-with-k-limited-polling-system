class_name ResearchLevel
extends Node2D

const AGENT := preload("res://Objects/Agent/Agent.tscn")
@export_range(0, 50) var agent_count := 30
var destinations: Array[Marker2D] = []

func _ready() -> void:
	for point: Marker2D in $Waypoints.get_children():
		destinations.append(point)
	var starts: Array[Vector2] = []
	for region: NavigationRegion2D in $Regions.get_children():
		for y in [48, 109, 170, 231, 292]:
			for x in [56, 158, 260, 362, 464]:
				starts.append(region.to_global(Vector2(x, y)))
	starts.shuffle()
	for i in range(mini(agent_count, starts.size())):
		var agent := AGENT.instantiate() as CharacterBody2D
		agent.position = $Agents.to_local(starts[i])
		$Agents.add_child(agent)

func random_destination(previous: Marker2D) -> Marker2D:
	var candidates := destinations.duplicate()
	candidates.erase(previous)
	return candidates.pick_random() if not candidates.is_empty() else null

func contains_position(point: Vector2) -> bool:
	for region: NavigationRegion2D in $Regions.get_children():
		var closest := NavigationServer2D.region_get_closest_point(region.get_rid(), point)
		if closest.distance_squared_to(point) < 0.0001:
			return true
	return false
