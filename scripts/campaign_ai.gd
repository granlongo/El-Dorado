class_name CampaignAI
extends RefCounted

# A bounded, deterministic heuristic player. Every decision goes through the
# same rule methods as the UI; it gets no additional resources or dice rerolls.
static func actor(g: Campaign) -> int:
	if g.battle != null:
		return g.battle_context.attacker if g.battle.active == 0 else 1-g.battle_context.attacker
	return g.active

static func controls_turn(g: Campaign) -> bool:
	return not g.finished and g.ai_players[actor(g)]

static func step(g: Campaign) -> bool:
	if g.finished: return false
	if g.battle != null:
		if not controls_turn(g): return false
		tactical_step(g)
		return true
	if g.phase in [0,4,5]:
		# Shared phase resolution belongs to the human, unless watching AI vs AI.
		if not g.ai_players.all(func(value): return value): return false
		g.advance()
		return true
	if not controls_turn(g): return false
	match g.phase:
		1: purchase(g)
		2: influence(g)
		3: military(g)
	return true

static func note(g: Campaign, player: int, message: String) -> void:
	g.history.append("AI · %s: %s" % [g.factions[player].name,message])

static func upkeep_reserve(g: Campaign, player: int) -> int:
	var base := 0
	for army in g.armies:
		if army.owner == player:
			for unit in army.units: base += Logistics.UPKEEP[unit]
	for fleet in g.fleets:
		if fleet.owner == player: base += int(fleet.ships)*3
	for p in g.provinces.values():
		if p.owner == player:
			for unit in p.garrison: base += Logistics.UPKEEP[unit]
	for order in g.orders:
		if order.owner == player: base += Logistics.UPKEEP[order.unit]
	var cap := g.capacity(player)
	var excess := maxi(0,Logistics.committed(g,player)-cap)
	return base+ceili(float(base*excess)/maxi(1,cap))+6

static func purchase(g: Campaign) -> void:
	var player := g.active
	var f: Dictionary = g.factions[player]
	var reserve := upkeep_reserve(g,player)
	if f.arrears == 0 and f.gold >= reserve+3 and f.pool < 4 and f.bought_cubes < 3:
		var before: int = f.gold
		g.buy(f.seat,"cube")
		if f.gold < before:
			note(g,player,"bought influence.")
			return
	if f.arrears == 0 and Logistics.committed(g,player) < g.capacity(player):
		var destinations: Array = g.provinces.keys()
		destinations.sort_custom(func(a,b): return army_size(g,b,player) < army_size(g,a,player))
		for id in destinations:
			# Buy inexpensive core troops; mix in ranged support at occupied sites.
			var unit := "infantry"
			if army_size(g,id,player) >= 4:
				var has_ranged := false
				for a in g.armies:
					if a.owner == player and a.province == id:
						for u in a.units:
							if int(g.profiles[u].range) > 0: has_ranged = true
				if not has_ranged: unit = "crossbow" if player == 0 else "bow"
			if f.gold < reserve+int(g.profiles[unit].price)+Logistics.UPKEEP[unit]: continue
			var count := g.orders.size()
			g.buy(id,unit)
			if g.orders.size() > count:
				note(g,player,"recruited %s at %s." % [unit,id])
				return
	note(g,player,"finished purchases; keeping gold for upkeep.")
	g.advance()

static func influence(g: Campaign) -> void:
	var player := g.active
	var f: Dictionary = g.factions[player]
	if f.ap == 0 and f.devotion > 0 and 2 not in f.devotion_used:
		g.policy("devotion",f.seat)
		note(g,player,"spent devotion for influence actions.")
		return
	# Complete integration before starting another claim.
	for action in ["annex","client"]:
		for id in g.provinces:
			var before: int = f.ap
			g.act(id,action)
			if f.ap < before:
				note(g,player,"%s in %s." % [action,id])
				return
	var targets: Array = g.provinces.keys()
	targets.sort_custom(func(a,b): return influence_value(g,a,player) > influence_value(g,b,player))
	for id in targets:
		if influence_value(g,id,player) <= 0: continue
		var before: int = f.ap
		g.act(id,"place")
		if f.ap < before:
			note(g,player,"placed influence in %s." % id)
			return
	for id in targets:
		if not Logistics.military_control(g,id,player) and g.provinces[id].owner != player: continue
		var before: int = f.ap
		g.contest(id)
		if f.ap < before:
			note(g,player,"contested rival influence in %s." % id)
			return
	note(g,player,"passed influence.")
	g.advance()

static func influence_value(g: Campaign, id: String, player: int) -> float:
	var p: Dictionary = g.provinces[id]
	if p.owner != player and p.status == "annexed": return 0
	var missing: int = g.effective_population(id)-p.cubes[player]
	if missing <= 0: return 0
	return 20.0/missing + (15 if Logistics.military_control(g,id,player) else 0) + (10 if p.owner == player else 0)

static func army_size(g: Campaign, id: String, player: int) -> int:
	var count := 0
	for a in g.armies:
		if a.owner == player and a.province == id: count += a.units.size()
	return count

static func military(g: Campaign) -> void:
	var player := g.active
	var f: Dictionary = g.factions[player]
	if f.cp <= 0:
		g.advance()
		return
	for army in g.armies.duplicate():
		if army.owner != player or army.spent: continue
		var origin: String = army.province
		var p: Dictionary = g.provinces[origin]
		if p.siege and p.owner != player:
			var before: int = f.cp
			g.army_action(origin,"assault")
			if f.cp == before: g.army_action(origin,"prepare")
			if f.cp < before:
				note(g,player,"acted on the siege at %s." % origin)
				return
		if p.institution >= 0 and p.institution != player and p.owner != player:
			var before: int = f.cp
			g.army_action(origin,"destroy institution")
			if f.cp < before: note(g,player,"removed hostile institution at %s." % origin); return
		# Hold a new bridgehead until influence can integrate it.
		if p.owner < 0 and p.cubes[player] > 0:
			var before: int = f.cp
			g.army_action(origin,"fortify")
			if f.cp < before: note(g,player,"held the bridgehead at %s." % origin); return
		var targets: Array = g.provinces.keys()
		targets.sort_custom(func(a,b): return military_value(g,army,a) > military_value(g,army,b))
		for target in targets:
			if target == origin or military_value(g,army,target) <= 0: continue
			var before: int = f.cp
			g.move_army(origin,target)
			if f.cp == before and origin in Logistics.COASTS and target in Logistics.COASTS:
				NavalRules.transport(g,origin,target)
			if f.cp < before:
				note(g,player,"moved from %s toward %s." % [origin,target])
				return
		var before: int = f.cp
		g.army_action(origin,"fortify")
		if f.cp < before: note(g,player,"fortified %s." % origin); return
	note(g,player,"passed military actions.")
	g.advance()

static func military_value(g: Campaign, army: Dictionary, target: String) -> float:
	if target == army.province: return -1
	var p: Dictionary = g.provinces[target]
	var defenders := army_size(g,target,1-army.owner)
	if p.owner < 0 and defenders == 0 and not Logistics.military_control(g,target,army.owner): defenders = g.effective_population(target)
	if p.owner != army.owner:
		if g.truce_until >= g.round_number and (p.owner >= 0 or defenders > 0 and Logistics.occupied(g,target,army.owner)): return -1
		if defenders > army.units.size(): return -1
		return 30.0 + (10 if p.city else 0) - defenders*2
	# Move island recruits onto the mainland, or move reserve armies to a frontier.
	if army.province == "G1" and target == "G2": return 20
	if army_size(g,target,army.owner) > 0: return -1
	for next in g.neighbors(target):
		if g.provinces[next].owner != army.owner: return 5
	return -1

static func income_choices(g: Campaign, player: int) -> void:
	var previous := g.active
	g.active = player
	for id in g.provinces:
		if g.factions[player].offered: break
		var message := g.policy("offer",id)
		if g.factions[player].offered: note(g,player,message)
	var f: Dictionary = g.factions[player]
	if not f.hostile and f.devotion < 2 and f.gold >= upkeep_reserve(g,player)+4:
		var before: int = f.devotion
		g.policy("observe",f.seat)
		if f.devotion > before: note(g,player,"observed a peaceful season.")
	g.active = previous

static func tactical_step(g: Campaign) -> void:
	var b: TacticalBattle = g.battle
	if b.finished:
		g.finish_battle()
		return
	if b.deployment:
		# Keep the default legal formation; do not inspect unrevealed opponents.
		b.confirm_deployment()
		return
	if b.command > 0 and not b.shooting_stage:
		for index in range(b.units.size()):
			var u: Dictionary = b.units[index]
			if u.side != b.active or u.state != "field" or u.moved: continue
			var target := nearest_enemy(b,u.cell,u.side)
			if target < 0: continue
			var delta: Vector2i = b.units[target].cell-u.cell
			if b.adjacent_enemy(index):
				# Face an adjacent enemy when possible; fighting itself costs no CP.
				if delta.x*u.facing.x+delta.y*u.facing.y <= 0:
					b.turn(index)
					return
				continue
			var ranged: bool = int(b.profiles[u.type].range) > 0
			if ranged and b.clear_shot(index,target) and not (b.rain and u.type in ["shot","artillery"]): continue
			var choices: Array = []
			var origin: Vector2i = u.cell
			var old_distance := distance(origin,b.units[target].cell)
			for y in range(12):
				for x in range(12):
					var cell := Vector2i(x,y)
					if b.at(cell) >= 0 or distance(origin,cell) > int(b.profiles[u.type].move): continue
					var next_distance := distance(cell,b.units[target].cell)
					if next_distance >= old_distance: continue
					var value: float = old_distance-next_distance
					if ranged and next_distance == 1: value -= 4
					choices.append({"cell":cell,"score":value})
			choices.sort_custom(func(a,c): return a.score > c.score)
			for choice in choices:
				var before: int = b.command
				b.move(index,choice.cell)
				if b.command < before: return
	# No legal useful movement remains. Resolve all fire and melee, then hand over.
	b.end_half_round()
	if b.finished: g.finish_battle()

static func nearest_enemy(b: TacticalBattle, cell: Vector2i, side: int) -> int:
	var best := -1
	var closest := 99
	for i in range(b.units.size()):
		var u: Dictionary = b.units[i]
		if u.side == side or u.state != "field": continue
		var d := distance(cell,u.cell)
		if d < closest: best = i; closest = d
	return best

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x-b.x)+absi(a.y-b.y)
