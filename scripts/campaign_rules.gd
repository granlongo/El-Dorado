class_name CampaignRules
extends RefCounted

const PROJECT_COSTS = {"city":12,"wall":6,"port":8,"institution":8,"road":4}

static func initialize(g: RefCounted) -> void:
	for f in g.factions:
		f.merge({"devotion":0,"devotion_used":[],"hostile":false,"offered":false,"eliminated":false,"early":0,"original_seat":f.seat})
	for p in g.provinces.values(): p.merge({"terrain":"open","projects":[],"garrison":[],"prepared":0})
	for a in g.armies: decorate_army(a)
	for f in g.fleets: f.merge({"spent":false,"cargo":[]})

static func decorate_army(a: Dictionary) -> void:
	a.merge({"fortified":false,"prisoners":[],"traditions":[],"embarked":false,"motion":0})

static func pay(g: RefCounted, player: int, amount: int) -> bool:
	if g.factions[player].arrears > 0 or g.factions[player].gold < amount: return false
	g.factions[player].gold -= amount
	return true

static func project(g: RefCounted, id: String, kind: String, endpoint := "") -> String:
	if g.finished or g.phase != 1 or kind not in PROJECT_COSTS: return "Build during Purchases."
	var p: Dictionary = g.provinces[id]
	if p.owner != g.active or (p.status != "annexed" and kind != "institution") or p.held_since >= g.round_number or p.siege or not Logistics.supplied(g,id,g.active): return "Construction needs an eligible supplied province held since the round began."
	if not p.projects.is_empty(): return "One project per province each round."
	if kind == "institution":
		if p.institution >= 0 or not Logistics.military_control(g,id,g.active): return "A new institution requires a local army and an empty institution slot."
	elif kind == "road":
		if endpoint not in g.neighbors(id) or g.road_key(id,endpoint) in g.roads: return "Choose an adjacent border without a road."
		var other: Dictionary = g.provinces[endpoint]
		if other.owner != g.active or other.status != "annexed" or other.held_since >= g.round_number or other.siege or not other.projects.is_empty() or not Logistics.supplied(g,endpoint,g.active): return "Both road endpoints must be eligible and have a free project slot."
	else:
		if p[kind]: return "Structure already exists."
		if kind in ["port","wall"] and not p.city: return "Build a city first."
		if kind == "port" and id not in Logistics.COASTS: return "Ports require a coast."
	if not pay(g,g.active,PROJECT_COSTS[kind]): return "Not enough spendable gold."
	var order := {"kind":kind,"owner":g.active,"origin":id,"endpoint":endpoint,"army":[],"motion":[]}
	if kind == "institution":
		for a in g.armies:
			if a.owner == g.active and a.province == id:
				decorate_army(a)
				order.army.append(a)
				order.motion.append(a.motion)
	p.projects.append(order)
	if kind == "road": g.provinces[endpoint].projects.append(order)
	return "Queued %s at %s." % [kind,id]

static func complete_projects(g: RefCounted) -> void:
	for id in g.provinces:
		var p: Dictionary = g.provinces[id]
		for order in p.projects:
			if order.origin != id: continue
			var ok: bool = p.owner == order.owner and p.held_since < g.round_number and not p.siege and Logistics.supplied(g,id,order.owner)
			if order.kind == "institution":
				var present := false
				for i in range(order.army.size()):
					var army: Dictionary = order.army[i]
					if army in g.armies and army.province == id and army.get("motion",0) == order.motion[i]: present = true
				ok = ok and present
			if order.kind == "road":
				var other: Dictionary = g.provinces[order.endpoint]
				ok = ok and other.owner == order.owner and other.held_since < g.round_number and not other.siege and Logistics.supplied(g,order.endpoint,order.owner)
			if ok:
				if order.kind == "institution": p.institution = order.owner
				elif order.kind == "road": g.roads.append(g.road_key(id,order.endpoint))
				else: p[order.kind] = true
			g.history.append(("Completed " if ok else "Canceled without refund: ") + order.kind + " at " + id)
	for p in g.provinces.values(): p.projects.clear()

static func devotion(g: RefCounted) -> String:
	if g.finished or g.phase not in [2,3]: return "Spend devotion in Influence or Military."
	var f: Dictionary = g.factions[g.active]
	if f.devotion < 1 or g.phase in f.devotion_used: return "No unused devotion available for this phase."
	f.devotion -= 1
	f.devotion_used.append(g.phase)
	f["ap" if g.phase == 2 else "cp"] += 2
	return "Devotion adds two action points."

static func observe(g: RefCounted) -> String:
	if g.phase != 5 or g.finished: return "Observe during Income, before resolving it."
	var f: Dictionary = g.factions[g.active]
	if f.hostile or f.devotion >= 2: return "Observance requires a peaceful military phase and room for a token."
	if not pay(g,g.active,4): return "Not enough spendable gold."
	f.devotion += 1
	return "Gained one devotion token."

static func offer(g: RefCounted, id: String) -> String:
	if g.finished or g.phase != 5 or g.active == 0: return "Native offerings occur during Income."
	var p: Dictionary = g.provinces[id]
	if p.institution != g.active or p.owner != g.active or not Logistics.supplied(g,id,g.active): return "Offer at your functioning supplied temple."
	if p.get("offering_round",0) == g.round_number: return "This temple already received its offering this round."
	for army in g.armies:
		if army.owner != g.active or army.province != id: continue
		decorate_army(army)
		var gain := 0
		for n in range(mini(2,army.prisoners.size())): gain += 2 if army.prisoners.pop_back() == 0 else 1
		if gain == 0:
			for i in range(army.units.size()):
				if army.units[i] not in ["cavalry","artillery"]:
					army.units.remove_at(i)
					gain = 1
					break
		if gain > 0:
			g.factions[g.active].pool = mini(12,g.factions[g.active].pool+gain)
			g.factions[g.active].offered = true
			p.offering_round = g.round_number
			g.armies = g.armies.filter(func(a): return not a.units.is_empty())
			return "Offering generated %d influence." % gain
	return "Bring prisoners or an infantry unit to this temple."

static func revolt(g: RefCounted) -> void:
	var revolted: Array = []
	for player in range(g.factions.size()):
		if g.factions[player].stability > 1: continue
		var candidates: Array = []
		for id in g.provinces:
			var p: Dictionary = g.provinces[id]
			if id not in revolted and (p.owner == player or Logistics.military_control(g,id,player)) and p.cubes[player] < g.effective_population(id): candidates.append(id)
		candidates.sort_custom(func(a,b):
			var ar: float = float(g.provinces[a].cubes[player])/g.effective_population(a)
			var br: float = float(g.provinces[b].cubes[player])/g.effective_population(b)
			if not is_equal_approx(ar,br): return ar < br
			if g.provinces[a].population != g.provinces[b].population: return g.provinces[a].population > g.provinces[b].population
			return a < b)
		if candidates.is_empty(): continue
		var id: String = candidates[0]
		var die: int = g.random.randi_range(1,6) + int(Logistics.military_control(g,id,player))
		if die > (4 if g.factions[player].stability == 0 else 2): continue
		var p: Dictionary = g.provinces[id]
		p.owner = -1
		p.status = "independent"
		p.held_since = g.round_number
		p.institution = -1
		p.cubes[player] = 0
		p.projects.clear()
		revolted.append(id)
		for army in g.armies:
			if army.owner != player or army.province != id: continue
			var destination: String = g.retreat_destination(id,player)
			if destination.is_empty():
				for n in range(ceili(army.units.size()/2.0)): army.units.pop_back()
			else: army.province = destination
			army.spent = true
		g.history.append("Revolt in %s removed %s political control." % [id,g.factions[player].name])
	g.armies = g.armies.filter(func(a): return not a.units.is_empty())

static func round_end(g: RefCounted) -> void:
	# Triple Alliance's compulsory offering.
	if not g.factions[1].offered:
		var candidates: Array = []
		for id in g.provinces:
			var p: Dictionary = g.provinces[id]
			if p.owner == 1 and p.cubes[1] > int(p.institution == 1): candidates.append(id)
		candidates.sort_custom(func(a,b): return g.provinces[a].cubes[1] < g.provinces[b].cubes[1] if g.provinces[a].cubes[1] != g.provinces[b].cubes[1] else a < b)
		if candidates.is_empty(): g.factions[1].pool = maxi(0,g.factions[1].pool-1)
		else: g.provinces[candidates[0]].cubes[1] -= 1
		g.history.append("Alliance missed its offering and lost one influence.")
	for player in range(g.factions.size()):
		var owns := false
		var annexed := 0
		for p in g.provinces.values():
			if p.owner == player:
				owns = true
				if p.status == "annexed": annexed += 1
		var troops := false
		for a in g.armies:
			if a.owner == player and not a.units.is_empty(): troops = true
		var ships := false
		for f in g.fleets:
			if f.owner == player and f.ships > 0: ships = true
		if not owns and not troops and (player != 0 or not ships):
			g.factions[player].eliminated = true
			for p in g.provinces.values():
				p.cubes[player] = 0
				if p.institution == player: p.institution = -1
			g.finished = true
			g.history.append("%s eliminated. %s wins." % [g.factions[player].name,g.factions[1-player].name])
		var enemy_seat: String = g.factions[1-player].original_seat
		var own_seat: String = g.factions[player].original_seat
		var early: bool = annexed >= 6 and g.provinces[enemy_seat].owner == player and g.provinces[enemy_seat].status == "annexed" and g.provinces[own_seat].owner == player
		g.factions[player].early = g.factions[player].early+1 if early else 0
		if g.factions[player].early >= 2:
			g.finished = true
			g.history.append("%s wins by sustained territorial control." % g.factions[player].name)

static func ranking(g: RefCounted) -> String:
	var ranks: Array = []
	for player in range(g.factions.size()):
		var population := 0
		for id in g.provinces:
			if g.provinces[id].owner == player and g.provinces[id].status == "annexed": population += g.effective_population(id)
		ranks.append([g.score(player),population,g.factions[player].gold])
	if ranks[0] == ranks[1]: return "Shared victory."
	for i in range(3):
		if ranks[0][i] != ranks[1][i]: return "%s wins (score, annexed population, then gold)." % g.factions[0 if ranks[0][i] > ranks[1][i] else 1].name
	return "Shared victory."
