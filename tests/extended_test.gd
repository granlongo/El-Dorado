extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: "+label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var g := Campaign.new()
	g.phase = 1
	check(CampaignRules.project(g,"G2","city").contains("Queued"),"city queued")
	check(CampaignRules.project(g,"G2","port").contains("One project"),"one project slot")
	g.phase = 5
	CampaignRules.complete_projects(g)
	check(g.provinces.G2.city,"city completes before income")
	g.phase = 1
	check(CampaignRules.project(g,"G2","port").contains("Queued"),"port uses existing city")
	g.provinces.G2.owner = -1
	CampaignRules.complete_projects(g)
	check(not g.provinces.G2.port,"lost destination cancels project")
	g = Campaign.new()
	g.phase = 1
	check(g.buy("G1","ship").contains("queued"),"ship purchase")
	Logistics.deploy(g)
	check(g.fleets[0].ships == 3 and Logistics.committed(g,0) == 10,"ship deploys to fleet and counts manpower")
	g = Campaign.new()
	g.phase = 3
	g.armies[0].province = "G1"
	check(NavalRules.transport(g,"G1","G2").contains("Insufficient"),"seven units exceed two ships")
	check(g.split_army("G1").contains("split"),"split army for transport")
	check(NavalRules.transport(g,"G1","G2").contains("moved"),"transport to mainland")
	check(g.fleets[0].spent and g.armies[1].owner == 1,"transport uses fleet activation without changing enemy army")
	check(g.armies.any(func(a): return a.owner == 0 and a.province == "G2" and a.spent),"landing army is spent")
	g = Campaign.new()
	g.phase = 2
	g.factions[0].devotion = 1
	check(g.policy("devotion","G1").contains("two") and g.factions[0].ap == 6,"devotion grants two actions")
	g.factions[0].devotion = 1
	check(g.policy("devotion","G1").contains("No unused"),"one devotion per phase")
	check(g.policy("truce","G1").contains("proposed") and g.truce_until == 0,"unilateral proposal does not create truce")
	g.active = 1
	check(g.policy("truce","A1").contains("agreed"),"bilateral truce acceptance")
	g.phase = 3
	check(g.move_army("A2","G2").contains("exceeds") or g.truce_until == 2,"truce duration")
	g.phase = 2
	check(g.policy("break","A1").contains("broken") and g.factions[1].stability == 0,"breaking truce loses stability")
	g = Campaign.new()
	g.phase = 5
	g.active = 1
	g.armies[1].province = "A1"
	check(g.policy("offer","A1").contains("Offering") and g.armies[1].units.size() == 7,"temple offering consumes infantry")
	check(g.policy("offer","A1").contains("already"),"offering cannot repeat at same temple")
	g = Campaign.new()
	g.phase = 3
	g.armies[0].province = "N1"
	g.armies[1].units.resize(4)
	g.armies[1].units.fill("infantry")
	g.provinces.A2.city = true
	g.provinces.A2.wall = true
	check(g.move_army("N1","A2").contains("Siege"),"wall garrison establishes siege")
	check(g.provinces.A2.owner == 1 and g.provinces.A2.garrison.size() == 4,"siege preserves political owner and units")
	check(Logistics.committed(g,1) == 4,"garrison counts committed manpower")
	check(g.capacity(1) == 7,"besieged province field yields no manpower")
	Logistics.maintenance(g)
	check(g.provinces.A2.garrison.size() == 3,"unsupplied garrison attrition")
	g.active = 0
	g.armies[0].spent = false
	g.armies[0].units.append("artillery")
	check(g.army_action("A2","assault").contains("assault") and g.battle != null,"cannon permits immediate assault")
	g.battle.active = 1
	g.battle.withdraw()
	g.finish_battle()
	check(not g.provinces.A2.siege and g.provinces.A2.garrison.is_empty() and g.provinces.A2.owner == -1,"successful assault captures city exactly once")
	g = Campaign.new()
	g.phase = 2
	g.factions[0].gold = 33
	var rng_state: int = g.random.state
	check(g.save_campaign("user://test.save").contains("saved"),"save writes state")
	g.factions[0].gold = 99
	check(g.load_campaign("user://test.save").contains("loaded"),"save restores state")
	check(g.factions[0].gold == 33 and g.random.state == rng_state and g.phase == 2,"ledger and RNG restored")
	var f := FileAccess.open("user://bad.save",FileAccess.WRITE)
	f.store_var({"version":99}); f.close()
	check(g.load_campaign("user://bad.save").contains("Unsupported") and g.factions[0].gold == 33,"invalid load leaves state untouched")
	var b := TacticalBattle.new(["infantry","infantry"],["infantry"],g.profiles,42)
	b.command = 6
	check(b.move_group([0,1],Vector2i(0,1)).contains("moved") and b.command == 5,"formation costs one CP")
	check(b.units[0].cell == Vector2i(1,3) and b.units[1].cell == Vector2i(2,3),"formation shape preserved")
	b = TacticalBattle.new(["infantry"],["infantry"],g.profiles,42)
	b.command = 6
	b.terrain[Vector2i(1,3)] = "water"
	check(b.move(0,Vector2i(1,3)).contains("empty"),"water blocks movement")
	b.terrain[Vector2i(1,3)] = "rough"
	check(b.move(0,Vector2i(1,4)).contains("exceeds"),"rough movement cost applies to path")
	b = TacticalBattle.new(["infantry"],["infantry"],g.profiles,42)
	b.deployment = true
	check(b.deployment_move(0,Vector2i(4,8)).contains("rows"),"deployment zone restriction")
	b.confirm_deployment(); b.confirm_deployment()
	check(not b.deployment and b.active == 0,"both players confirm before tactical play")
	g = Campaign.new()
	g.phase = 5
	for id in ["A1","A2","N1","N2"]:
		g.provinces[id].owner = 0
		g.provinces[id].status = "annexed"
	CampaignRules.round_end(g)
	check(not g.finished and g.factions[0].early == 1,"early victory requires consecutive ends")
	CampaignRules.round_end(g)
	check(g.finished,"sustained six-province control wins")
	print("Extended mechanics: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
