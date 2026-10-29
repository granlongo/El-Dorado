class_name Logistics
extends RefCounted

# Costs and force composition are deliberately excluded: the supplied tables are missing.
const MANPOWER = {"infantry":1, "artillery":1, "cavalry":2, "ship":1,"bow":1,"skirmisher":1,"slinger":1,"jaguar":1,"eagle":1,"crossbow":1,"shot":1}
const UPKEEP = {"infantry":2, "artillery":2, "cavalry":3, "ship":3,"bow":2,"skirmisher":2,"slinger":2,"jaguar":2,"eagle":2,"crossbow":2,"shot":2}
const COASTS = ["G1", "G2", "N2"]

static func occupied(game: RefCounted, id: String, player: int) -> bool:
	for army in game.armies:
		if army.province == id and army.owner != player and not army.units.is_empty(): return true
	return false

static func military_control(game: RefCounted, id: String, player: int) -> bool:
	for army in game.armies:
		if army.province == id and army.owner == player and not army.units.is_empty(): return true
	return false

static func qualifies(game: RefCounted, id: String, player: int) -> bool:
	var p: Dictionary = game.provinces[id]
	return not occupied(game,id,player) and (p.owner == player or p.cubes[player] > 0 or military_control(game,id,player))

static func hostile_wall(game: RefCounted, id: String, player: int) -> bool:
	var p: Dictionary = game.provinces[id]
	return p.wall and p.city and p.owner >= 0 and p.owner != player

static func source(game: RefCounted, id: String, player: int) -> bool:
	var p: Dictionary = game.provinces[id]
	return p.owner == player and p.cubes[player] > 0 and not p.siege and not occupied(game,id,player) and (p.city or game.factions[player].seat == id)

static func sea_open(game: RefCounted, player: int) -> bool:
	var own := false
	for fleet in game.fleets:
		if fleet.ships > 0:
			if fleet.owner != player:
				if game.truce_until < game.round_number: return false
				continue
			own = true
	return own

static func supplied(game: RefCounted, origin: String, player: int) -> bool:
	if not qualifies(game,origin,player): return false
	var pending: Array[String] = [origin]
	var visited: Array[String] = []
	while not pending.is_empty():
		var id: String = pending.pop_front()
		if id in visited: continue
		visited.append(id)
		if source(game,id,player): return true
		# Besiegers may trace out of their own province, but cannot transit hostile walls.
		if id != origin and hostile_wall(game,id,player): continue
		var adjacent: Array[String] = game.neighbors(id)
		if id in COASTS and sea_open(game,player):
			for coast in COASTS:
				# One endpoint must be a functioning owned port.
				if port(game,id,player) or port(game,coast,player):
					if coast not in adjacent: adjacent.append(coast)
		for next in adjacent:
			if next not in visited and qualifies(game,next,player): pending.append(next)
	return false

static func port(game: RefCounted, id: String, player: int) -> bool:
	var p: Dictionary = game.provinces[id]
	return p.port and p.owner == player and p.cubes[player] > 0 and not p.siege and not occupied(game,id,player)

static func fleet_supplied(game: RefCounted, player: int) -> bool:
	if not sea_open(game,player): return false
	for coast in COASTS:
		if port(game,coast,player): return true
	return false

static func committed(game: RefCounted, player: int, queued := true) -> int:
	var total := 0
	for army in game.armies:
		if army.owner != player: continue
		for unit in army.units: total += MANPOWER[unit]
	for p in game.provinces.values():
		if p.owner == player:
			for unit in p.get("garrison",[]): total += MANPOWER[unit]
	for fleet in game.fleets:
		if fleet.owner == player: total += int(fleet.ships)
	if queued:
		for order in game.orders:
			if order.owner == player: total += MANPOWER[order.unit]
	return total

static func maintenance(game: RefCounted) -> void:
	# Snapshot bills, supply losses and old arrears before mutating any force.
	var bills := [0,0]
	var desert := [false,false]
	var army_losses: Array[int] = []
	var fleet_losses: Array[int] = []
	var garrison_losses: Dictionary = {}
	for id in game.provinces:
		var p: Dictionary = game.provinces[id]
		if p.siege and p.owner >= 0: garrison_losses[id] = 0 if siege_supplied(game,id,p.owner) else ceili(p.garrison.size()/4.0)
	for player in range(2):
		var base := 0
		for army in game.armies:
			if army.owner == player:
				for unit in army.units: base += UPKEEP[unit]
		for p in game.provinces.values():
			if p.owner == player:
				for unit in p.get("garrison",[]): base += UPKEEP[unit]
		for fleet in game.fleets:
			if fleet.owner == player: base += int(fleet.ships) * 3
		var capacity: int = game.capacity(player)
		var excess := maxi(0,committed(game,player) - capacity)
		bills[player] = base + ceili(float(base * excess) / maxi(1,capacity))
		desert[player] = game.factions[player].arrears > 0
	for army in game.armies:
		army_losses.append(0 if supplied(game,army.province,army.owner) else ceili(army.units.size()/4.0))
	for fleet in game.fleets:
		fleet_losses.append(0 if fleet_supplied(game,fleet.owner) else ceili(fleet.ships/4.0))
	for player in range(2):
		var f: Dictionary = game.factions[player]
		var paid := mini(f.gold,bills[player])
		f.gold -= paid
		var unpaid: int = bills[player] - paid
		f.arrears += unpaid
		if unpaid > 0: f.stability = maxi(0,f.stability - 1)
		game.history.append("%s upkeep %d; paid %d; arrears %d." % [f.name,bills[player],paid,f.arrears])
	for i in range(game.armies.size()):
		var army: Dictionary = game.armies[i]
		var losses: int = army_losses[i] + int(desert[army.owner])
		if losses > 0:
			game.history.append("%s at %s loses %d units (attrition/desertion)." % [game.factions[army.owner].name,army.province,mini(losses,army.units.size())])
		# Automatic casualty choice for this prototype: desert non-artillery first;
		# then choose attrition losses from the end of the army's unit list.
		if desert[army.owner] and not army.units.is_empty():
			var deserter := 0
			for index in range(army.units.size()):
				if army.units[index] != "artillery":
					deserter = index
					break
			army.units.remove_at(deserter)
		for loss in range(army_losses[i]):
			if not army.units.is_empty(): army.units.pop_back()
	for i in range(game.fleets.size()):
		var fleet: Dictionary = game.fleets[i]
		fleet.ships = maxi(0,fleet.ships - fleet_losses[i] - int(desert[fleet.owner]))
	for id in garrison_losses:
		var p: Dictionary = game.provinces[id]
		for n in range(garrison_losses[id]+int(desert[p.owner])):
			if not p.garrison.is_empty(): p.garrison.pop_back()
		if p.garrison.is_empty():
			for a in game.armies:
				if a.province == id and a.owner != p.owner:
					p.siege = false
					game.conquer(id,a.owner)
					break
	game.armies = game.armies.filter(func(a): return not a.units.is_empty())
	game.fleets = game.fleets.filter(func(f): return f.ships > 0)

static func deploy(game: RefCounted) -> void:
	var deployed: Dictionary = {}
	for order in game.orders:
		var p: Dictionary = game.provinces[order.province]
		var player: int = order.owner
		var key := "%s:%d" % [order.province,player]
		var valid: bool = p.owner == player and p.status == "annexed" and p.held_since < game.round_number and not p.siege and supplied(game,order.province,player)
		valid = valid and committed(game,player,false) + MANPOWER[order.unit] <= game.capacity(player)
		valid = valid and deployed.get(key,0) + MANPOWER[order.unit] <= game.effective_population(order.province)
		if order.unit == "ship":
			valid = valid and NavalRules.deploy(game,order)
			if valid: deployed[key] = deployed.get(key,0)+1
			game.history.append(("Deployed ship at " if valid else "Canceled ship at ")+order.province)
			continue
		var army: Dictionary = {}
		for candidate in game.armies:
			if candidate.owner == player and candidate.province == order.province and candidate.units.size() < 10:
				army = candidate
				break
		var local_count := 0
		for candidate in game.armies:
			if candidate.province == order.province and candidate.owner == player: local_count += 1
		valid = valid and (not army.is_empty() or local_count < 2)
		if valid:
			if army.is_empty():
				army = {"owner":player,"province":order.province,"units":[],"spent":true}
				game.armies.append(army)
			army.units.append(order.unit)
			# Recruitment is after the military phase; no further offensive action this round.
			deployed[key] = deployed.get(key,0) + MANPOWER[order.unit]
		game.history.append("%s %s at %s." % ["Deployed" if valid else "Canceled without refund",order.unit,order.province])
	game.orders.clear()

static func siege_supplied(game: RefCounted, id: String, player: int) -> bool:
	if not game.provinces[id].port or not sea_open(game,player): return false
	for coast in COASTS:
		if coast != id and port(game,coast,player) and supplied(game,coast,player): return true
	return false
