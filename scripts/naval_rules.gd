class_name NavalRules
extends RefCounted

static func recruit(g: RefCounted, id: String) -> String:
	if g.finished or g.phase != 1 or g.active != 0: return "Spanish ships are purchased during Purchases."
	var p: Dictionary = g.provinces[id]
	if p.owner != g.active or p.status != "annexed" or p.held_since >= g.round_number or not p.city or not p.port or not Logistics.supplied(g,id,g.active) or p.siege: return "Ships require an eligible supplied port city."
	var local := 0
	var ships := 0
	for o in g.orders:
		if o.province == id:
			local += Logistics.MANPOWER[o.unit]
			ships += int(o.unit == "ship")
	if ships >= 2 or local >= g.effective_population(id) or Logistics.committed(g,g.active)+1 > g.capacity(g.active): return "Ship purchase exceeds port, population or manpower quota."
	if not CampaignRules.pay(g,g.active,int(g.profiles.ship.price)): return "Not enough spendable gold."
	g.orders.append({"owner":g.active,"province":id,"unit":"ship"})
	return "Ship queued; manpower reserved."

static func deploy(g: RefCounted, order: Dictionary) -> bool:
	var count := 0
	for f in g.fleets:
		if f.owner != order.owner and f.ships > 0: return false
		if f.owner == order.owner: count += int(f.ships)
	if count >= 8 or not g.provinces[order.province].port: return false
	for f in g.fleets:
		if f.owner == order.owner and f.ships < 4:
			f.ships += 1
			return true
	g.fleets.append({"owner":order.owner,"ships":1,"zone":"S1","spent":true,"cargo":[]})
	return true

static func transport(g: RefCounted, origin: String, target: String) -> String:
	if g.finished or g.phase != 3 or g.battle != null: return "Transport during Military."
	if origin == target or origin not in Logistics.COASTS or target not in Logistics.COASTS: return "Choose two different S1 coastal provinces."
	if not Logistics.military_control(g,origin,g.active) or Logistics.occupied(g,origin,g.active): return "Control the loading field first."
	var fleet: Dictionary = {}
	for f in g.fleets:
		if f.owner != g.active and f.ships > 0: return "A hostile fleet blocks loading."
		if f.owner == g.active and not f.get("spent",false): fleet = f
	if fleet.is_empty(): return "No unspent transport fleet."
	var army: Dictionary = {}
	for a in g.armies:
		if a.owner == g.active and a.province == origin and not a.spent: army = a; break
	if army.is_empty(): return "No unspent army at the loading province."
	# Assign entire units to individual carriers; large units cannot straddle ships.
	var spaces: Array = []
	for i in range(int(fleet.ships)): spaces.append(3)
	for unit in army.units:
		var size := 2 if unit in ["cavalry","artillery"] else 1
		var carrier := -1
		for i in range(spaces.size()):
			if spaces[i] >= size: carrier = i; break
		if carrier == -1: return "Insufficient carrier space; split the army before loading."
		spaces[carrier] -= size
	var before: int = g.factions[g.active].cp
	var result: String = g.move_army(origin,target,true)
	if g.factions[fleet.owner].cp < before:
		fleet.spent = true
		if g.battle != null: g.battle_context["transport"] = fleet
	return result

# The encounter resolver uses simultaneous pair outcomes. The small map has only
# one sea zone, so a forced withdrawal has no legal sea retreat and loses vessels.
static func encounter(g: RefCounted, attacking: int) -> String:
	var vessels := [0,0]
	for f in g.fleets: vessels[f.owner] += int(f.ships)
	var winner := -1
	for naval_round in range(3):
		var pairs := mini(vessels[0],vessels[1])
		if pairs == 0:
			winner = 0 if vessels[0] > 0 else (1 if vessels[1] > 0 else -1)
			break
		var sunk := [0,0]
		var disengaged := [0,0]
		for i in range(pairs):
			var rolls := [0,0]
			for side in range(2):
				var support := mini(2,maxi(0,vessels[side]-pairs-i*2))
				rolls[side] = maxi(1,g.random.randi_range(1,6)+3+support-int(not Logistics.fleet_supplied(g,side)))
			if rolls[0] == rolls[1]: continue
			var loser := 0 if rolls[0] < rolls[1] else 1
			if rolls[1-loser] >= 2*rolls[loser]: sunk[loser] += 1
			else: disengaged[loser] += 1
		for side in range(2): vessels[side] -= sunk[side]
		if vessels[0] == 0 or vessels[1] == 0: continue
		var retreat := [disengaged[0] == vessels[0],disengaged[1] == vessels[1]]
		if retreat[0] or retreat[1]:
			for side in range(2):
				if retreat[side]: vessels[side] = 0
			break
		if naval_round == 2: vessels[attacking] = 0
	winner = 0 if vessels[0] > 0 and vessels[1] == 0 else (1 if vessels[1] > 0 and vessels[0] == 0 else -1)
	for side in range(2):
		var remaining: int = vessels[side]
		for f in g.fleets:
			if f.owner == side:
				f.ships = mini(int(f.ships),remaining)
				remaining -= int(f.ships)
				f.spent = true
	g.fleets = g.fleets.filter(func(f): return f.ships > 0)
	if winner >= 0: g.factions[winner].pool = mini(12,g.factions[winner].pool+(2 if winner == 0 else 1))
	return "Naval encounter resolved; remaining ships %d / %d." % vessels
