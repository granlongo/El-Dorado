class_name Campaign
extends RefCounted

const BORDERS = [["G2","N1"],["G2","N3"],["A1","A2"],["A2","N1"],["A2","N2"],["A1","N4"],["N1","N2"],["N1","N3"],["N2","N4"]]
const PHASES = ["Maintenance", "Purchases", "Influence", "Military", "Deployment", "Income"]
var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/provisional_units.json"))
var roads: Array = []
var truce_until := 0
var access := false
var treaty_offer := -1
var armies: Array = []
var fleets: Array = []
var orders: Array = []
var battle: TacticalBattle
var battle_context: Dictionary = {}
var random := RandomNumberGenerator.new()
var provinces: Dictionary = {}
var factions: Array = []
var round_number := 1
var phase := 0
var active := 0
var passed := [false, false]
var finished := false
var ai_players: Array = [false,true]
var history: Array[String] = []

func _init() -> void:
	random.randomize()
	factions = [{"name":"Gulf conquistador","gold":60,"pool":4,"ap":4,"seat":"G1"}, {"name":"Triple Alliance","gold":60,"pool":4,"ap":4,"seat":"A1"}]
	for id in ["G1","G2","A1","A2","N1","N2","N3","N4"]:
		var owner := -1
		if id.begins_with("G"): owner = 0
		if id.begins_with("A"): owner = 1
		var population := 7 if id in ["G1","A1"] else 3
		var cubes := [0,0]
		if owner >= 0: cubes[owner] = population
		provinces[id] = {"owner":owner,"status":"annexed" if owner >= 0 else "independent","population":population,"cubes":cubes,"city":id in ["G1","A1"],"client_round":0,"held_since":0,"plague":1 if id == "G2" else 0,"wall":false,"siege":false,"port":id == "G1","institution":1 if id == "A1" else -1,"militia_round":0}
	for i in range(2):
		factions[i].merge({"arrears":0,"stability":2,"cp":4,"bought_cubes":0})
		var setup: Dictionary = profiles.starting_forces.gulf if i == 0 else profiles.starting_forces.alliance
		var units: Array = []
		for n in range(int(setup.infantry)): units.append("infantry")
		armies.append({"owner":i,"province":setup.province,"units":units,"spent":false})
		if setup.ships > 0: fleets.append({"owner":i,"ships":int(setup.ships),"zone":"S1"})
	CampaignRules.initialize(self)
	history.append("Provisional unit profiles, prices and force composition enabled. See data/provisional_units.json.")

func neighbors(id: String) -> Array[String]:
	var result: Array[String] = []
	for border in BORDERS:
		if border[0] == id: result.append(border[1])
		elif border[1] == id: result.append(border[0])
	return result

func reachable(id: String) -> bool:
	var p: Dictionary = provinces[id]
	if p.owner == active or p.cubes[active] > 0 or Logistics.military_control(self,id,active): return true
	for adjacent in neighbors(id):
		if provinces[adjacent].cubes[active] > 0: return true
	if id in Logistics.COASTS and Logistics.sea_open(self,active):
		for coast in Logistics.COASTS:
			if provinces[coast].cubes[active] > 0 and (Logistics.port(self,id,active) or Logistics.port(self,coast,active)): return true
	return false

func act(id: String, action: String) -> String:
	if finished or battle != null or phase != 2: return "Influence actions are available only in phase 3."
	var p: Dictionary = provinces[id]
	var f: Dictionary = factions[active]
	if Logistics.hostile_wall(self,id,active): return "A hostile walled city bars influence actions."
	if Logistics.occupied(self,id,active): return "A hostile army bars peaceful influence actions."
	var cost := 1
	if action == "annex": cost = 2
	if f.ap < cost: return "Not enough influence action points."
	match action:
		"place":
			if not reachable(id) or not influence_connected(id,active): return "Target must be reachable from your influence or ownership."
			if p.cubes[0] + p.cubes[1] >= effective_population(id): return "All influence slots are occupied."
			if f.pool < 1: return "No available influence cubes."
			p.cubes[active] += 1
			f.pool -= 1
		"client":
			if p.status == "annexed": return "Annexed ownership cannot switch through diplomacy."
			if p.institution >= 0 and p.institution != active: return "A hostile institution prevents a client agreement."
			if p.owner == active: return "Already your client."
			if p.cubes[active] * 2 <= effective_population(id): return "A strict majority of influence is required."
			p.owner = active
			p.status = "client"
			p.client_round = round_number
		"annex":
			if p.status == "annexed": return "Province is already annexed."
			if p.institution >= 0 and p.institution != active: return "A hostile institution prevents annexation."
			if not Logistics.military_control(self,id,active) and not (p.owner == active and p.status == "client" and p.client_round < round_number): return "Without an army, a client must predate this round."
			if p.cubes[active] != effective_population(id): return "Fill every influence slot first."
			if f.arrears > 0: return "Clear maintenance arrears before optional spending."
			if f.gold < 4: return "Annexation requires 4 gold."
			f.gold -= 4
			p.owner = active
			p.status = "annexed"
			p.held_since = round_number
		_: return "Unknown action."
	f.ap -= cost
	var message := "%s: %s in %s." % [f.name, action, id]
	history.append(message)
	active = 1 - active
	if passed[active]: active = 1 - active
	return message

func effective_population(id: String) -> int:
	var p: Dictionary = provinces[id]
	return maxi(1,p.population - int(p.plague >= 2))

func capacity(player: int) -> int:
	var total := 0
	for id in provinces:
		var p: Dictionary = provinces[id]
		if p.owner == player and not Logistics.occupied(self,id,player):
			total += effective_population(id) if p.status == "annexed" else int(p.cubes[player] > 0)
	return total

func income(player: int) -> int:
	var total := 0
	for id in provinces:
		var p: Dictionary = provinces[id]
		if p.owner != player or p.cubes[player] == 0 or p.siege or Logistics.occupied(self,id,player): continue
		if p.status == "client": total += 1
		else: total += floori(float(2 * p.population * p.cubes[player]) / effective_population(id))
		if p.city: total += 2
	if provinces[factions[player].seat].owner == player: total += 8
	return total

func buy(id: String, unit: String) -> String:
	if finished or phase != 1: return "Recruit only in Purchases."
	if unit == "ship": return NavalRules.recruit(self,id)
	var f: Dictionary = factions[active]
	var p: Dictionary = provinces[id]
	if f.arrears > 0: return "Clear arrears before buying."
	if unit == "cube":
		if f.bought_cubes >= 3 or f.pool >= 12: return "Influence purchase limit reached."
		if f.gold < 3: return "Not enough gold."
		f.gold -= 3
		f.pool += 1
		f.bought_cubes += 1
		return "Bought one influence cube."
	if unit not in Logistics.MANPOWER: return "Unknown recruit."
	if active == 1 and unit in ["artillery","cavalry","shot","crossbow"]: return "Spanish equipment is unavailable to native recruitment."
	if active == 0 and unit in ["bow","skirmisher","slinger","jaguar","eagle"]: return "Native allied recruitment is not available at this site."
	if p.owner != active or p.status != "annexed" or p.held_since >= round_number or p.siege or not Logistics.supplied(self,id,active):
		return "Recruitment needs a supplied annexed province held since the round began."
	if active == 0 and id != f.seat and not (p.city and p.port): return "Spanish core troops require the seat or an annexed port city."
	var manpower: int = Logistics.MANPOWER[unit]
	if Logistics.committed(self,active) + manpower > capacity(active): return "Recruitment exceeds national manpower."
	var local := 0
	for order in orders:
		if order.province == id: local += Logistics.MANPOWER[order.unit]
	if local + manpower > effective_population(id): return "Local deployment quota reached."
	var price: int = profiles[unit].price
	if f.gold < price: return "Not enough gold."
	f.gold -= price
	orders.append({"owner":active,"province":id,"unit":unit})
	history.append("%s queued %s at %s for %d gold." % [f.name,unit,id,price])
	return "Recruit queued; manpower reserved until deployment."

func influence_connected(id: String, player: int) -> bool:
	var pending: Array[String] = [id]
	var seen: Array[String] = []
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if current in seen: continue
		seen.append(current)
		var p: Dictionary = provinces[current]
		if Logistics.military_control(self,current,player): return true
		if p.owner == player and (current == factions[player].seat or p.institution == player): return true
		var adjacent_ids := neighbors(current)
		if current in Logistics.COASTS and Logistics.sea_open(self,player):
			for coast in Logistics.COASTS:
				if Logistics.port(self,current,player) or Logistics.port(self,coast,player): adjacent_ids.append(coast)
		for adjacent in adjacent_ids:
			var target: Dictionary = provinces[adjacent]
			if target.cubes[player] > 0 or target.owner == player:
				pending.append(adjacent)
	return false

func contest(id: String) -> String:
	if finished or phase != 2 or battle != null: return "Contest during Influence."
	var p: Dictionary = provinces[id]
	var rival := 1 - active
	if factions[active].ap < 1: return "Not enough action points."
	if not reachable(id) or not influence_connected(id,active): return "No connected influence route."
	if Logistics.occupied(self,id,active) and p.cubes[active] == 0: return "Need existing influence to contest under hostile occupation."
	if p.cubes[rival] == 0: return "No rival influence."
	if p.cubes[rival] == 1 and p.institution == rival: return "The institution protects its last cube."
	var attack := random.randi_range(1,6) + int(p.owner == active) + int(Logistics.military_control(self,id,active))
	var defend := random.randi_range(1,6) + int(p.owner == rival) + int(Logistics.military_control(self,id,rival))
	if attack > defend: p.cubes[rival] -= 1
	factions[active].ap -= 1
	var result := "Contest %d vs %d: %s." % [attack,defend,"rival cube removed" if attack > defend else "no change"]
	history.append(result)
	active = 1 - active
	if passed[active]: active = 1 - active
	return result

func move_army(origin: String, target: String, amphibious := false) -> String:
	if finished or phase != 3 or battle != null: return "Move armies during Military."
	if factions[active].cp < 1: return "No command points."
	if not amphibious and target not in neighbors(origin) and not can_march(origin,target): return "Destination exceeds legal campaign movement."
	if truce_until >= round_number and (provinces[target].owner == 1-active or Logistics.occupied(self,target,active)): return "The truce forbids this attack."
	var army: Dictionary = {}
	for candidate in armies:
		if candidate.owner == active and candidate.province == origin and not candidate.spent:
			army = candidate
			break
	if army.is_empty(): return "No unspent friendly army at the origin."
	CampaignRules.decorate_army(army)
	var local_units := 0
	var local_armies := 0
	for candidate in armies:
		if candidate.owner == active and candidate.province == target:
			local_units += candidate.units.size()
			local_armies += 1
	if local_units + army.units.size() > 20 or local_armies >= 2: return "Destination army capacity exceeded."
	army.spent = true
	army.motion += 1
	army.fortified = false
	factions[active].cp -= 1
	var defender_units: Array = []
	var defenders: Array = []
	for candidate in armies:
		if candidate.owner != active and candidate.province == target:
			defenders.append(candidate)
			defender_units.append_array(candidate.units)
	if provinces[target].owner != active or not defenders.is_empty(): factions[active].hostile = true
	var independent: bool = provinces[target].owner < 0 and defenders.is_empty() and not Logistics.military_control(self,target,active)
	if independent:
		if provinces[target].militia_round != round_number:
			for i in range(effective_population(target)): defender_units.append("infantry")
			provinces[target].militia_round = round_number
	if provinces[target].wall and provinces[target].city and provinces[target].owner == 1-active and not defender_units.is_empty():
		if defender_units.size() <= 6:
			provinces[target].garrison = defender_units.duplicate()
			for defender in defenders: armies.erase(defender)
			provinces[target].siege = true
			army.province = target
			next_military_player()
			return "Defenders withdrew inside the walled city. Siege established."
	if not defender_units.is_empty():
		battle_context = {"army":army,"defenders":defenders,"origin":origin,"target":target,"attacker":active,"militia":independent,"defender_spent":false if defenders.is_empty() else defenders[0].spent}
		battle = TacticalBattle.new(army.units,defender_units,profiles,random.randi(),not Logistics.supplied(self,origin,active),false if independent else not Logistics.supplied(self,target,1-active))
		battle.traditions[0] = army.get("traditions",[]).duplicate()
		if not defenders.is_empty(): battle.traditions[1] = defenders[0].get("traditions",[]).duplicate()
		battle.spanish_side = 0 if active == 0 else 1
		battle.shock_enabled = round_number <= 4
		battle.terrain_type = provinces[target].terrain
		battle.setup_terrain()
		for defender in defenders:
			if defender.get("fortified",false): battle.entrenched = true; defender.fortified = false
		return "Battle begins at %s. Alternate tactical half-rounds." % target
	army.province = target
	if provinces[target].owner != active: conquer(target,active)
	history.append("%s moved %s → %s." % [factions[active].name,origin,target])
	next_military_player()
	return "Army moved one border; activation spent."

func next_military_player() -> void:
	active = 1 - active
	if passed[active]: active = 1 - active

func finish_battle() -> void:
	if battle == null or not battle.finished: return
	var context := battle_context
	var attacker: int = context.attacker
	var was_siege: bool = provinces[context.target].siege
	var army: Dictionary = context.army
	army.units = battle.survivors(0)
	# Restore each defending army separately, preserving its original activation status.
	var defending_units: Array = battle.units.filter(func(u): return u.side == 1)
	var offset := 0
	for defender in context.defenders:
		var survivors: Array = []
		for i in range(offset,offset + defender.units.size()):
			if defending_units[i].state != "destroyed": survivors.append(defending_units[i].type)
		offset += defender.units.size()
		defender.units = survivors
		defender.spent = defender.spent or battle.winner != 1
		if defender.units.is_empty(): armies.erase(defender)

	if context.get("assault",false):
		provinces[context.target].garrison = battle.survivors(1)
		if battle.winner == 0:
			provinces[context.target].garrison.clear()
			provinces[context.target].siege = false
	if battle.winner == 0:
		# Retreat surviving field defenders before occupation; annihilate only if no legal route exists.
		for defender in armies.duplicate():
			if defender.owner == attacker or defender.province != context.target: continue
			var escaped := false
			for destination in neighbors(context.target):
				if destination == context.origin: continue
				if Logistics.qualifies(self,destination,defender.owner):
					var count := 0
					var groups := 0
					for other in armies:
						if other.owner == defender.owner and other.province == destination:
							count += other.units.size()
							groups += 1
					if count + defender.units.size() <= 20 and groups < 2:
						defender.province = destination
						escaped = true
						break
			if not escaped: armies.erase(defender)
		army.province = context.target
		conquer(context.target,attacker)
		factions[attacker].pool = mini(12,factions[attacker].pool + (2 if attacker == 0 else 1))
	elif battle.winner == 1:
		factions[1-attacker].pool = mini(12,factions[1-attacker].pool + (2 if attacker == 1 else 1))
		# The attacker retreats to its entry province; its location was not changed at battle entry.
		if not context.get("assault",false): provinces[context.target].cubes[attacker] -= floori(provinces[context.target].cubes[attacker]/2.0)
	if battle.winner == -1:
		# Both armies withdrew: defender must leave the contested field too.
		for defender in armies.duplicate():
			if defender.owner == attacker or defender.province != context.target: continue
			var escaped := false
			for destination in neighbors(context.target):
				if destination != context.origin and Logistics.qualifies(self,destination,defender.owner):
					defender.province = destination
					escaped = true
					break
			if not escaped: armies.erase(defender)
	if context.get("sortie",false) and battle.winner != 0:
		provinces[context.target].garrison = army.units.duplicate()
		armies.erase(army)
	elif was_siege and battle.winner == 0 and provinces[context.target].owner == attacker:
		provinces[context.target].siege = false
		provinces[context.target].prepared = 0
	armies = armies.filter(func(a): return not a.units.is_empty())
	history.append("Battle at %s: %s." % [context.target,"attacker wins" if battle.winner == 0 else ("defender wins" if battle.winner == 1 else "mutual withdrawal")])
	if battle.winner >= 0:
		var victorious: Dictionary = army if battle.winner == 0 else (context.defenders[0] if not context.defenders.is_empty() else {})
		if not victorious.is_empty() and victorious in armies:
			CampaignRules.decorate_army(victorious)
			var losers: Array = context.defenders if battle.winner == 0 else [army]
			var cavalry := mini(2,victorious.units.count("cavalry"))
			if not battle.rain and provinces[context.target].terrain not in ["forest","jungle","mountain"] and not context.get("assault",false):
				for n in range(cavalry):
					if random.randi_range(1,6) >= 5:
						for loser in losers:
							if loser in armies and not loser.units.is_empty(): loser.units.pop_back(); break
			if battle.initial[1-battle.winner] >= 3 and victorious.traditions.size() < 2:
				var tradition: String = ["Scouts","Discipline","Engineers"][random.randi_range(0,2)]
				if tradition not in victorious.traditions: victorious.traditions.append(tradition)
			for n in range(battle.captures[battle.winner]):
				if victorious.prisoners.size() < 4: victorious.prisoners.append(1-victorious.owner)
		for defeated in ([army] if battle.winner == 1 else context.defenders):
			CampaignRules.decorate_army(defeated)
			defeated.prisoners.clear()
			if not defeated.traditions.is_empty(): defeated.traditions.remove_at(random.randi_range(0,defeated.traditions.size()-1))
	armies = armies.filter(func(a): return not a.units.is_empty())
	battle = null
	battle_context = {}
	next_military_player()

func conquer(id: String, player: int) -> void:
	var p: Dictionary = provinces[id]
	var loser: int = 1-player
	p.cubes[loser] -= floori(p.cubes[loser]/2.0)
	if p.owner != player:
		p.owner = -1
		p.status = "independent"
		p.held_since = round_number
	if p.cubes[0] + p.cubes[1] >= effective_population(id):
		if p.cubes[loser] > int(p.institution == loser): p.cubes[loser] -= 1
	if p.cubes[0] + p.cubes[1] < effective_population(id): p.cubes[player] += 1

func progress_plague() -> void:
	var infected: Array[String] = []
	for id in provinces:
		var p: Dictionary = provinces[id]
		if p.plague not in [1,2]: continue
		var targets: Array[String] = []
		for adjacent in neighbors(id):
			if provinces[adjacent].plague == 0: targets.append(adjacent)
		targets.sort_custom(func(a,b): return effective_population(a) > effective_population(b) if effective_population(a) != effective_population(b) else a < b)
		if not targets.is_empty() and random.randi_range(1,6) >= 4: infected.append(targets[0])
		p.plague += 1
	for id in infected: provinces[id].plague = 1
	for id in provinces:
		var p: Dictionary = provinces[id]
		while p.cubes[0] + p.cubes[1] > effective_population(id):
			var owner := (round_number-1)%2 if p.cubes[0] == p.cubes[1] else (0 if p.cubes[0] > p.cubes[1] else 1)
			if p.cubes[owner] == 1 and p.institution == owner: owner = 1-owner
			p.cubes[owner] -= 1

func advance() -> void:
	if finished or battle != null: return
	if phase in [1,2,3]:
		passed[active] = true
		history.append("%s passes %s." % [factions[active].name,PHASES[phase]])
		if not (passed[0] and passed[1]):
			active = 1 - active
			return
	if phase == 0: Logistics.maintenance(self)
	if phase == 2:
		var seen: Array[String] = []
		for army in armies:
			var id: String = army.province
			if id in seen or Logistics.hostile_wall(self,id,army.owner): continue
			seen.append(id)
			var p: Dictionary = provinces[id]
			var rival: int = 1-army.owner
			if p.cubes[0] + p.cubes[1] >= effective_population(id):
				if p.cubes[rival] > int(p.institution == rival): p.cubes[rival] -= 1
			if p.cubes[0] + p.cubes[1] < effective_population(id): p.cubes[army.owner] += 1
	if phase == 4: Logistics.deploy(self)
	if phase == 5:
		for player in range(factions.size()):
			if ai_players[player]: CampaignAI.income_choices(self,player)
		CampaignRules.complete_projects(self)
		progress_plague()
		CampaignRules.revolt(self)
		for i in range(2):
			var f: Dictionary = factions[i]
			var revenue := income(i)
			var debt_payment := mini(revenue,f.arrears)
			f.arrears -= debt_payment
			f.gold += revenue - debt_payment
			var generation := 0
			if Logistics.source(self,f.seat,i): generation += 2
			for id in provinces:
				var p: Dictionary = provinces[id]
				if p.institution == i and p.owner == i and p.cubes[i] > 0 and Logistics.supplied(self,id,i): generation += 2
			if i == 0 and Logistics.fleet_supplied(self,i):
				var ships := 0
				for fleet in fleets:
					if fleet.owner == i: ships += int(fleet.ships)
				generation += mini(2,ships)
			f.pool = mini(12,f.pool + generation)
			history.append("%s income %d; debt payment %d; generated %d influence." % [f.name,revenue,debt_payment,generation])
		CampaignRules.round_end(self)
		if finished: return
		if round_number == 6:
			finished = true
			history.append("Six-round campaign complete. Scores: Gulf %d / Alliance %d. %s" % [score(0),score(1),CampaignRules.ranking(self)])
			return
		round_number += 1
		for army in armies: army.spent = false
		for f in factions:
			f.bought_cubes = 0
			f.devotion_used.clear()
			f.hostile = false
			f.offered = false
		for fleet in fleets: fleet.spent = false
	phase = (phase + 1) % 6
	passed = [false,false]
	active = (round_number - 1) % 2
	if phase == 2:
		for f in factions: f.ap = 4
	if phase == 3:
		for f in factions: f.cp = 4

func score(player: int) -> int:
	var total := mini(5, int(factions[player].gold / 10.0)) - ceili(factions[player].arrears/10.0)
	var enemy_seat: String = factions[1-player].original_seat
	if provinces[enemy_seat].owner == player and provinces[enemy_seat].status == "annexed": total += 3
	for p in provinces.values():
		if p.owner == player: total += 2 if p.status == "annexed" else 1
	return total

func road_key(a: String, b: String) -> String:
	return a + ":" + b if a < b else b + ":" + a

func can_march(origin: String, destination: String) -> bool:
	var allowance := 2
	for army in armies:
		if army.owner == active and army.province == origin and not army.spent:
			if "artillery" in army.units: allowance = 1
			elif army.units.all(func(u): return u == "cavalry"): allowance = 3
	var pending: Array = [[origin,0]]
	var costs := {origin:0}
	while not pending.is_empty():
		var item: Array = pending.pop_front()
		var current: String = item[0]
		if current == destination: return true
		if current != origin and (Logistics.occupied(self,current,active) or provinces[current].owner != active): continue
		for next in neighbors(current):
			var step := 1 if provinces[next].terrain == "open" or road_key(current,next) in roads else 2
			if active == 1 and provinces[next].terrain == "desert": step = 1
			var cost: int = item[1]+step
			if cost <= allowance and cost < costs.get(next,99):
				costs[next] = cost
				pending.append([next,cost])
	return false

func retreat_destination(origin: String, player: int) -> String:
	for id in neighbors(origin):
		if not Logistics.qualifies(self,id,player): continue
		var groups := 0
		for a in armies:
			if a.owner == player and a.province == id: groups += 1
		if groups < 2: return id
	return ""

func policy(action: String, id: String) -> String:
	if finished or battle != null: return "Finish the battle first."
	var f: Dictionary = factions[active]
	if action == "devotion": return CampaignRules.devotion(self)
	if action == "observe": return CampaignRules.observe(self)
	if action == "offer": return CampaignRules.offer(self,id)
	if phase != 2 and not (phase == 3 and action == "break"): return "Political actions occur during Influence; truces may also be broken before military actions."
	match action:
		"seat":
			if provinces[f.seat].owner == active: return "Your original seat is still held."
			if provinces[id].owner != active or not provinces[id].city or not Logistics.supplied(self,id,active) or f.ap < 2: return "Choose an owned supplied city; costs two actions."
			if not CampaignRules.pay(self,active,8): return "Not enough spendable gold."
			f.seat = id
			f.ap -= 2
		"truce":
			if treaty_offer == -1:
				treaty_offer = active
				return "Truce proposed. The other player must accept on their turn."
			if treaty_offer == active: return "Await the other player's acceptance."
			var withdrawals: Array = []
			for province in provinces:
				var p: Dictionary = provinces[province]
				if not p.siege: continue
				for army in armies:
					if army.province != province or army.owner == p.owner: continue
					var destination := retreat_destination(province,army.owner)
					if destination.is_empty(): return "Truce impossible: a besieger has no legal withdrawal."
					withdrawals.append([army,destination])
			for withdrawal in withdrawals:
				var p: Dictionary = provinces[withdrawal[0].province]
				withdrawal[0].province = withdrawal[1]
				withdrawal[0].spent = true
				p.siege = false
				p.prepared = 0
			truce_until = round_number+1
			treaty_offer = -1
			return "Both players agreed: truce through the end of next round."
		"break":
			if truce_until < round_number: return "No active truce."
			truce_until = 0
			f.stability = maxi(0,f.stability-2)
			return "Truce broken; lost two stability."
		_: return "Unknown political action."
	next_military_player()
	return "Political action resolved."

func army_action(id: String, action: String) -> String:
	if finished or phase != 3 or battle != null: return "Army actions occur during Military."
	var army: Dictionary = {}
	for a in armies:
		if a.owner == active and a.province == id and (not a.spent or action == "assault" and "Engineers" in a.get("traditions",[]) and a.get("prepared_round",0) == round_number): army = a; break
	if army.is_empty() or factions[active].cp < 1: return "Need an unspent army and a command point."
	CampaignRules.decorate_army(army)
	var p: Dictionary = provinces[id]
	if action != "fortify" and truce_until >= round_number: return "Hostile actions are forbidden during a truce."
	match action:
		"fortify": army.fortified = true
		"suppress":
			if p.cubes[1-active] <= int(p.institution == 1-active): return "No unprotected rival cube."
			p.cubes[1-active] -= 1
		"destroy institution":
			if p.siege or p.institution < 0: return "No accessible institution."
			p.institution = -1
		"prepare":
			if not p.siege or p.owner == active: return "No hostile siege here."
			p.prepared = round_number
			army.prepared_round = round_number
		"assault":
			if not p.siege or p.owner == active or p.garrison.is_empty(): return "No enemy garrison to assault."
			if "artillery" not in army.units and (p.prepared == 0 or p.prepared >= round_number and "Engineers" not in army.traditions): return "Prepare the siege in an earlier round or bring cannon."
			battle_context = {"army":army,"defenders":[],"origin":id,"target":id,"attacker":active,"militia":false,"assault":true}
			battle = TacticalBattle.new(army.units,p.garrison,profiles,random.randi(),not Logistics.supplied(self,id,active),not Logistics.siege_supplied(self,id,1-active))
			battle.wall_defense = true
			battle.spanish_side = 0 if active == 0 else 1
			battle.shock_enabled = round_number <= 4
		_: return "Unknown army action."
	army.spent = true
	factions[active].cp -= 1
	if action != "fortify": factions[active].hostile = true
	if battle == null: next_military_player()
	return "Army action: " + action

func split_army(id: String) -> String:
	if phase != 3 or battle != null: return "Split at the start of a military activation."
	var local: Array = armies.filter(func(a): return a.owner == active and a.province == id)
	if local.size() != 1 or local[0].units.size() < 2 or local[0].spent: return "Need one unspent army with at least two units and space for a second army."
	var first: Dictionary = local[0]
	var count := int(first.units.size()/2.0)
	var second: Dictionary = first.duplicate(true)
	second.units = first.units.slice(count)
	first.units = first.units.slice(0,count)
	second.traditions = []
	second.prisoners = []
	armies.append(second)
	return "Army split; activation status preserved."

func relocate(origin: String, target: String) -> String:
	if finished or phase != 2 or battle != null: return "Relocate during Influence."
	var source: Dictionary = provinces[origin]
	var dest: Dictionary = provinces[target]
	var cost := 3 if dest.terrain == "jungle" else 2
	if origin == target or source.cubes[active] <= int(source.institution == active) or factions[active].ap < cost: return "Need an unprotected source cube and enough action points."
	if dest.cubes[0]+dest.cubes[1] >= effective_population(target) or Logistics.occupied(self,target,active) or Logistics.hostile_wall(self,target,active): return "Target cannot accept influence."
	source.cubes[active] -= 1
	if not reachable(target) or not influence_connected(target,active):
		source.cubes[active] += 1
		return "Relocation would sever the target's reachability."
	dest.cubes[active] += 1
	factions[active].ap -= cost
	next_military_player()
	return "Relocated one influence cube."

func save_campaign(path := "user://campaign.save") -> String:
	if battle != null: return "Finish the tactical battle before saving."
	var data := {"version":1,"ai_players":ai_players,"provinces":provinces.duplicate(true),"factions":factions,"armies":armies,"fleets":fleets,"orders":orders,"roads":roads,"round":round_number,"phase":phase,"active":active,"passed":passed,"finished":finished,"history":history,"rng":random.state,"truce":truce_until,"offer":treaty_offer}
	for p in data.provinces.values():
		for order in p.projects:
			var indices: Array = []
			for a in order.army: indices.append(armies.find(a))
			order.army = indices
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return "Could not open save file."
	file.store_var(data,false)
	file.close()
	var err := DirAccess.rename_absolute(path+".tmp",path)
	return "Campaign saved." if err == OK else "Could not replace save file."

func load_campaign(path := "user://campaign.save") -> String:
	if battle != null: return "Finish the battle before loading."
	if not FileAccess.file_exists(path): return "No saved campaign."
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 8388608: return "Invalid save file."
	var data = file.get_var(false)
	file.close()
	if not data is Dictionary or data.get("version",0) != 1: return "Unsupported save file."
	for key in ["provinces","factions","armies","fleets","orders","roads","round","phase","active","passed","finished","history","rng","truce","offer"]:
		if not data.has(key): return "Incomplete save file."
	if not data.provinces is Dictionary or data.provinces.keys().size() != provinces.size() or not data.factions is Array or data.factions.size() != 2: return "Invalid scenario data."
	if not data.armies is Array or not data.fleets is Array or not data.orders is Array or not data.history is Array: return "Invalid collections."
	if data.phase not in range(6) or data.active not in range(2) or data.round not in range(1,7): return "Invalid turn state."
	var saved_ai = data.get("ai_players",[false,false])
	if not saved_ai is Array or saved_ai.size() != 2 or not saved_ai.all(func(v): return v is bool): return "Invalid AI settings."
	var baseline := Campaign.new()
	for id in baseline.provinces:
		if not data.provinces.has(id) or not data.provinces[id] is Dictionary: return "Invalid provinces."
		for key in baseline.provinces[id]:
			if not data.provinces[id].has(key) or typeof(data.provinces[id][key]) != typeof(baseline.provinces[id][key]): return "Invalid province fields."
	for a in data.armies:
		if not a is Dictionary or not a.has_all(["owner","province","units","spent"]) or a.owner not in range(2) or a.province not in provinces or not a.units is Array: return "Invalid army."
		for u in a.units:
			if u not in Logistics.MANPOWER or u == "ship": return "Invalid unit profile."
	for i in range(2):
		if not data.factions[i] is Dictionary: return "Invalid factions."
		for key in factions[i]:
			if not data.factions[i].has(key) or typeof(data.factions[i][key]) != typeof(factions[i][key]): return "Invalid faction fields."
	if not data.passed is Array or data.passed.size() != 2 or not data.roads is Array or not data.finished is bool or not data.rng is int: return "Invalid phase data."
	for entry in data.history:
		if not entry is String: return "Invalid history."
	for fleet in data.fleets:
		if not fleet is Dictionary or not fleet.has_all(["owner","ships","zone"]) or fleet.owner not in range(2) or not fleet.ships is int or fleet.ships not in range(1,5) or fleet.zone != "S1": return "Invalid fleet."
	for order in data.orders:
		if not order is Dictionary or not order.has_all(["owner","province","unit"]) or order.owner not in range(2) or order.province not in provinces or order.unit not in Logistics.MANPOWER: return "Invalid recruit order."
	for p in data.provinces.values():
		if p.owner not in [-1,0,1] or p.cubes.size() != 2 or p.population not in [3,5,7] or p.plague not in range(4): return "Invalid province values."
		for n in p.cubes:
			if not n is int or n < 0 or n > p.population: return "Invalid influence."
		for order in p.projects:
			if not order is Dictionary or not order.has_all(["kind","army","origin","owner","endpoint"]) or not order.army is Array: return "Invalid project."
			var refs: Array = []
			for index in order.army:
				if index not in range(data.armies.size()): return "Missing project army."
				refs.append(data.armies[index])
			order.army = refs
	ai_players = saved_ai.duplicate()
	provinces = data.provinces
	factions = data.factions
	armies = data.armies
	fleets = data.fleets
	orders = data.orders
	roads = data.roads
	round_number = data.round
	phase = data.phase
	active = data.active
	passed = data.passed
	finished = data.finished
	history.assign(data.history)
	random.state = data.rng
	truce_until = data.truce
	treaty_offer = data.offer
	return "Campaign loaded."

func sortie(id: String) -> String:
	if phase != 3 or finished or battle != null: return "Sortie during Military."
	var p: Dictionary = provinces[id]
	if not p.siege or p.owner != active or p.garrison.is_empty() or p.get("sortie_round",0) == round_number: return "No unspent besieged garrison here."
	if factions[active].cp < 1: return "No command points."
	var army := {"owner":active,"province":id,"units":p.garrison.duplicate(),"spent":false}
	CampaignRules.decorate_army(army)
	armies.append(army)
	var result := move_army(id,id,true)
	if battle != null:
		battle_context.sortie = true
		p.garrison.clear()
		p.sortie_round = round_number
	else: armies.erase(army)
	return result
