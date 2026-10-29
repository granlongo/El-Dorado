class_name TacticalBattle
extends RefCounted

const SIZE := 12
var units: Array = []
var profiles: Dictionary
var rng := RandomNumberGenerator.new()
var active := 0
var half_round := 0
var command := 0
var initial := [0,0]
var unsupplied := [false,false]
var finished := false
var winner := -1
var rain := false
var messages: Array[String] = []
var terrain: Dictionary = {}
var terrain_type := "open"
var river := false
var wall_defense := false
var entrenched := false
var spanish_side := 0
var shock_enabled := false
var shock_used := false
var captures := [0,0]
var deployment := false
var deployment_done := false
var flee_enabled := [false,false]
var cannon_target := -1
var shooting_stage := false
var shots_done: Array = []
var pressure: Dictionary = {}
var traditions := [[],[]]
var scouts_used := [false,false]
var discipline_used := [false,false]
var scout_order := false
var discipline_order := false

func _init(attacker: Array, defender: Array, data: Dictionary, seed_value: int, attacker_unsupplied := false, defender_unsupplied := false) -> void:
	profiles = data
	rng.seed = seed_value
	unsupplied = [attacker_unsupplied,defender_unsupplied]
	rain = rng.randi_range(1,6) == 1
	for side in range(2):
		var force: Array = attacker if side == 0 else defender
		initial[side] = force.size()
		for i in range(force.size()):
			var row := 2 - int(i / 10.0) if side == 0 else 9 + int(i / 10.0)
			units.append({"side":side,"type":force[i],"cell":Vector2i(1+i%10,row),"deployment_cell":Vector2i(1+i%10,row),"facing":Vector2i.DOWN if side == 0 else Vector2i.UP,"general":i == 0,"state":"field","moved":false})
	messages.append("Open battlefield · %s · automatic deployment." % ("rain; cannon cannot shoot" if rain else "clear weather"))
	start_half_round()

func at(cell: Vector2i) -> int:
	for i in range(units.size()):
		if units[i].state == "field" and units[i].cell == cell: return i
	return -1

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < SIZE and cell.y >= 0 and cell.y < SIZE

func adjacent_enemy(index: int) -> bool:
	var unit: Dictionary = units[index]
	for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var other := at(unit.cell + step)
		if other >= 0 and units[other].side != unit.side: return true
	return false

func start_half_round() -> void:
	cannon_target = -1
	var general := false
	for unit in units:
		if unit.side == active:
			unit.moved = false
			if unit.general and unit.state == "field": general = true
	command = maxi(1,rng.randi_range(1,6) - int(unsupplied[active]) - int(not general))

func move(index: int, destination: Vector2i) -> String:
	if finished or deployment or shooting_stage or index < 0 or index >= units.size(): return "Select a friendly unit during movement."
	var unit: Dictionary = units[index]
	if unit.side != active or unit.state != "field": return "Select the active side's field unit."
	if unit.moved or command < 1: return "Unit already moved or no command points remain."
	if not inside(destination) or at(destination) >= 0 or terrain.get(destination,"") == "water": return "Destination must be an empty board cell."
	if adjacent_enemy(index):
		if command < 2 or destination != unit.cell - unit.facing: return "Engaged units may disengage one cell backward for 2 CP."
		command -= 2
	else:
		var frontier: Array = [[unit.cell,0]]
		var seen: Array[Vector2i] = []
		var legal := false
		var allowance: int = profiles[unit.type].move + int(scout_order)
		while not frontier.is_empty():
			frontier.sort_custom(func(a,b): return a[1] < b[1])
			var item: Array = frontier.pop_front()
			var cell: Vector2i = item[0]
			var distance: int = item[1]
			if cell in seen: continue
			seen.append(cell)
			if cell == destination:
				legal = true
				break
			if distance >= allowance: continue
			var contact := false
			if cell != unit.cell:
				for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
					var other := at(cell + step)
					if other >= 0 and units[other].side != active: contact = true
			if contact: continue
			for step in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				var next: Vector2i = cell + step
				if inside(next) and at(next) < 0 and terrain.get(next,"") != "water" and distance+terrain_cost(next) <= allowance: frontier.append([next,distance+terrain_cost(next)])
		if not legal: return "Destination exceeds movement or its path is blocked."
		command -= 1
	if scout_order:
		scouts_used[active] = true
		scout_order = false
	unit.cell = destination
	unit.moved = true
	return "Unit moved; movement spent for this half-round."

func turn(index: int) -> String:
	if finished or deployment or shooting_stage or index < 0 or index >= units.size(): return "Select a unit during movement."
	var unit: Dictionary = units[index]
	if unit.side != active or unit.state != "field" or unit.moved or command < 1: return "Cannot turn this unit now."
	unit.facing = Vector2i(-unit.facing.y,unit.facing.x)
	unit.moved = true
	command -= 1
	return "Facing rotated; movement spent."

func factor(index: int, opponent: int) -> int:
	var unit: Dictionary = units[index]
	var key := "mounted" if units[opponent].type == "cavalry" else "foot"
	var bonus := 0
	if unit.side == 1 and unit.cell == unit.get("deployment_cell",Vector2i(-1,-1)):
		if wall_defense:
			bonus = 1
			if units.any(func(u): return u.side == 0 and u.state == "field" and u.type == "artillery"):
				if cannon_target == -1: cannon_target = index
				if cannon_target == index: bonus = 0
		elif entrenched and index-initial[0] < 2: bonus = 1
	var delta: Vector2i = units[opponent].cell-unit.cell
	var facing_enemy: int = delta.x*unit.facing.x+delta.y*unit.facing.y
	var distance: int = absi(delta.x)+absi(delta.y)
	var flank := int(facing_enemy <= 0 and distance == 1)
	bonus -= mini(2,flank+pressure.get(index,0))
	return int(profiles[unit.type][key]) + int(unit.general) - int(unsupplied[unit.side]) + bonus

func recoil(index: int, opponent: int) -> void:
	var unit: Dictionary = units[index]
	var delta: Vector2i = unit.cell - units[opponent].cell
	var direction: Vector2i
	if absi(delta.x) > absi(delta.y): direction = Vector2i(signi(delta.x),0)
	elif absi(delta.y) > absi(delta.x): direction = Vector2i(0,signi(delta.y))
	else: direction = -unit.facing
	var destination: Vector2i = unit.cell + direction
	if unit.type in ["skirmisher","eagle"] and flee_enabled[unit.side]:
		var second: Vector2i = destination+direction
		if not inside(destination) or (at(destination) < 0 and terrain.get(destination,"") != "water" and (not inside(second) or at(second) < 0 and terrain.get(second,"") != "water")):
			destination = second
	if not inside(destination): unit.state = "routed"
	elif at(destination) >= 0 or terrain.get(destination,"") == "water": unit.state = "destroyed"
	else: unit.cell = destination

func exchange(a: int, b: int, shooting := false) -> void:
	var attack_die := rng.randi_range(1,6)
	if discipline_order and units[a].side == active:
		attack_die = rng.randi_range(1,6)
		discipline_used[active] = true
		discipline_order = false
	var attack := maxi(1,attack_die + (int(profiles[units[a].type].shoot) + int(units[a].general) - int(unsupplied[units[a].side]) if shooting else factor(a,b)))
	# Every shooter counts as foot, so factor(b,a) is the correct ranged defense.
	var defend := maxi(1,rng.randi_range(1,6) + factor(b,a))
	messages.append("%s %d vs %s %d." % [units[a].type,attack,units[b].type,defend])
	if attack == defend: return
	if attack > defend:
		if attack >= 2*defend or (not shooting and units[a].type == "jaguar" and units[a].cell+units[a].facing == units[b].cell and units[b].type != "cavalry" and attack-defend >= 3):
			units[b].state = "destroyed"
			if not shooting and units[a].side != spanish_side and units[b].type != "cavalry" and captures[units[a].side] < 2 and rng.randi_range(1,6) >= 5: captures[units[a].side] += 1
		else:
			recoil(b,a)
			if shock_enabled and not shock_used and units[a].side == spanish_side and (units[a].type in ["shot","artillery"] and shooting or units[a].type == "cavalry" and not shooting):
				shock_used = true
				if units[b].state == "field":
					recoil(b,a)
					if units[b].state == "destroyed": units[b].state = "routed"
	elif not shooting:
		if defend >= 2*attack or (units[b].type == "jaguar" and units[b].cell+units[b].facing == units[a].cell and units[a].type != "cavalry" and defend-attack >= 3):
			units[a].state = "destroyed"
			if units[b].side != spanish_side and units[a].type != "cavalry" and captures[units[b].side] < 2 and rng.randi_range(1,6) >= 5: captures[units[b].side] += 1
		else: recoil(a,b)

func clear_shot(a: int, b: int) -> bool:
	var shooter: Dictionary = units[a]
	var target: Dictionary = units[b]
	var delta: Vector2i = target.cell - shooter.cell
	if absi(delta.x) + absi(delta.y) > int(profiles[shooter.type].range): return false
	var forward: int = delta.x * shooter.facing.x + delta.y * shooter.facing.y
	var lateral := absi(delta.x * shooter.facing.y - delta.y * shooter.facing.x)
	if forward < 1 or lateral > forward: return false
	if adjacent_enemy(a) or adjacent_enemy(b): return false
	for cell in terrain:
		if cell == target.cell: continue
		if terrain[cell] in ["rough","hill"] and segment_hits_rect(Vector2(shooter.cell),Vector2(target.cell),Rect2(Vector2(cell)-Vector2(0.5,0.5),Vector2.ONE)): return false
	# Segment/closed-cell intersection treats exact edges as blocked.
	for i in range(units.size()):
		if i in [a,b] or units[i].state != "field": continue
		var rect := Rect2(Vector2(units[i].cell)-Vector2(0.50001,0.50001),Vector2(1.00002,1.00002))
		if segment_hits_rect(Vector2(shooter.cell),Vector2(target.cell),rect): return false
	return true

func segment_hits_rect(start: Vector2, finish: Vector2, rect: Rect2) -> bool:
	var delta := finish-start
	var low := 0.0
	var high := 1.0
	for axis in range(2):
		if is_zero_approx(delta[axis]):
			if start[axis] < rect.position[axis] or start[axis] > rect.end[axis]: return false
		else:
			var near := (rect.position[axis]-start[axis])/delta[axis]
			var far := (rect.end[axis]-start[axis])/delta[axis]
			low = maxf(low,minf(near,far))
			high = minf(high,maxf(near,far))
			if low > high: return false
	return true

func end_half_round() -> void:
	if finished or deployment: return
	for i in range(units.size()):
		var unit: Dictionary = units[i]
		if i in shots_done or unit.side != active or unit.state != "field" or int(profiles[unit.type].range) == 0: continue
		if (unit.type in ["artillery","shot"] and rain) or (unit.type == "artillery" and unit.moved): continue
		for j in range(units.size()):
			if units[j].side != active and units[j].state == "field" and clear_shot(i,j):
				exchange(i,j,true)
				break
	var fought: Array[int] = []
	for i in range(units.size()):
		if units[i].side != active or units[i].state != "field" or i in fought: continue
		var candidates: Array[int] = []
		for direction in [units[i].facing,Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var j := at(units[i].cell + direction)
			if j >= 0 and units[j].side != active and j not in fought and j not in candidates: candidates.append(j)
		if not candidates.is_empty():
			fought.append(i)
			fought.append(candidates[0])
			pressure.clear()
			for pair in [[i,candidates[0]],[candidates[0],i]]:
				var principal: int = pair[0]
				var opponent: int = pair[1]
				for support in range(units.size()):
					if support in fought or units[support].state != "field" or units[support].side != units[principal].side: continue
					if units[support].cell+units[support].facing != units[opponent].cell: continue
					if units[opponent].cell+units[opponent].facing == units[support].cell: continue
					var others := false
					for d in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
						var n := at(units[support].cell+d)
						if n >= 0 and n != opponent and units[n].side != units[support].side: others = true
					if not others and pressure.get(opponent,0) < 2:
						pressure[opponent] = pressure.get(opponent,0)+1
						fought.append(support)
			exchange(i,candidates[0])
			pressure.clear()
	var broken := [false,false]
	for side in range(2):
		var losses := 0
		for unit in units:
			if unit.side == side and unit.state != "field": losses += 1
		broken[side] = losses >= ceili(initial[side]/3.0)
	if broken[0] or broken[1]:
		finished = true
		winner = -1 if broken[0] and broken[1] else (1 if broken[0] else 0)
		return
	half_round += 1
	if half_round >= 24:
		finished = true
		winner = 1
		return
	active = 1-active
	shooting_stage = false
	shots_done.clear()
	scout_order = false
	discipline_order = false
	start_half_round()

func withdraw() -> void:
	if finished or shooting_stage or units.any(func(u): return u.side == active and u.moved):
		messages.append("Withdrawal is only legal at the start of your half-round.")
		return
	finished = true
	winner = 1-active

func survivors(side: int) -> Array:
	var result: Array = []
	for unit in units:
		if unit.side == side and unit.state != "destroyed": result.append(unit.type)
	return result

func setup_terrain() -> void:
	terrain.clear()
	if terrain_type in ["forest","jungle","mountain"]:
		for x in [2,3,7,8]:
			for y in [5,6]: terrain[Vector2i(x,y)] = "hill" if terrain_type == "mountain" else "rough"
	if river:
		for x in range(12):
			if x not in [3,8]: terrain[Vector2i(x,6)] = "water"

func terrain_cost(cell: Vector2i) -> int:
	return 2 if terrain.get(cell,"") in ["rough","hill"] else 1

func move_group(indices: Array, displacement: Vector2i) -> String:
	if finished or deployment or shooting_stage or indices.is_empty() or indices.size() > 6 or command < 1: return "Group orders require 1–6 units and one CP."
	var selected: Array = []
	for index in indices:
		if index < 0 or index >= units.size() or index in selected: return "Invalid group."
		var u: Dictionary = units[index]
		if u.side != active or u.state != "field" or u.moved or adjacent_enemy(index) or u.facing != units[indices[0]].facing: return "Group members must be unspent, unengaged and share a facing."
		selected.append(index)
	var connected: Array = [selected[0]]
	for iteration in range(selected.size()):
		for index in selected:
			for other in connected.duplicate():
				var delta: Vector2i = units[index].cell-units[other].cell
				if absi(delta.x)+absi(delta.y) == 1 and index not in connected: connected.append(index)
	if connected.size() != selected.size(): return "Group must be edge-connected."
	# Advance the complete rigid formation together, checking every intermediate cell.
	var steps: Array[Vector2i] = []
	for i in range(absi(displacement.x)): steps.append(Vector2i(signi(displacement.x),0))
	for i in range(absi(displacement.y)): steps.append(Vector2i(0,signi(displacement.y)))
	if steps.is_empty(): return "Choose a displacement."
	var totals: Dictionary = {}
	var offset := Vector2i.ZERO
	for step in steps:
		offset += step
		for index in selected:
			var cell: Vector2i = units[index].cell+offset
			if not inside(cell) or terrain.get(cell,"") == "water": return "Formation crosses an impassable cell."
			var occupant := at(cell)
			if occupant >= 0 and occupant not in selected: return "Formation path is blocked."
			totals[index] = totals.get(index,0)+terrain_cost(cell)
			if totals[index] > int(profiles[units[index].type].move): return "Formation exceeds its slowest unit's movement."
			if offset != displacement:
				for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
					var other := at(cell+dir)
					if other >= 0 and units[other].side != active: return "Formation must stop at enemy contact."
	for index in selected:
		units[index].cell += displacement
		units[index].moved = true
	command -= 1
	return "Group moved for one command point."

func deployment_move(index: int, cell: Vector2i) -> String:
	if half_round > 0 or not deployment: return "Deployment is closed."
	if index < 0 or index >= units.size() or units[index].side != active: return "Select your deployment unit."
	if not inside(cell) or at(cell) >= 0: return "Choose an empty cell."
	if (active == 0 and cell.y > 2) or (active == 1 and cell.y < 9): return "Stay in your deployment rows."
	units[index].cell = cell
	units[index].deployment_cell = cell
	return "Deployment changed."

func confirm_deployment() -> String:
	var front := 0
	for unit in units:
		if unit.side == active and unit.cell.y == (2 if active == 0 else 9): front += 1
	if front < mini(2,initial[active]): return "At least two units must occupy the front deployment row."
	if active == 0: active = 1
	else:
		deployment = false
		deployment_done = true
		active = 0
		start_half_round()
	return "Deployment confirmed. Pass the controls to the other player."

func choose_shot(index: int, target: int) -> String:
	if finished or deployment or not shooting_stage: return "Begin shooting after movement."
	if index < 0 or target < 0 or index >= units.size() or target >= units.size(): return "Select a shooter and enemy target."
	var u: Dictionary = units[index]
	if index in shots_done or u.side != active or units[target].side == active or u.state != "field" or units[target].state != "field": return "Illegal shooter or target."
	if profiles[u.type].range == 0 or not clear_shot(index,target): return "Target is out of range, arc or line of sight."
	if (u.type in ["artillery","shot"] and rain) or (u.type == "artillery" and u.moved): return "Weather or movement prevents this shot."
	exchange(index,target,true)
	shots_done.append(index)
	return "Shot resolved."

func use_tradition(name: String) -> String:
	if deployment or finished or name not in traditions[active]: return "This army does not have that tradition."
	if name == "Scouts" and not scouts_used[active] and not shooting_stage:
		scout_order = true
		return "Scouts: next unit move gains one cell."
	if name == "Discipline" and not discipline_used[active]:
		discipline_order = true
		return "Discipline: next active combat die is rerolled; the new result is kept."
	return "Tradition already used or unavailable in this stage."
