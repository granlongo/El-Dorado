extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + description)

func clean_game() -> Campaign:
	var game := Campaign.new()
	game.random.seed = 42
	game.armies.clear()
	game.fleets.clear()
	for p in game.provinces.values(): p.plague = 0
	return game

func _init() -> void:
	call_deferred("run")

func run() -> void:
	test_scenario()
	test_supply()
	test_maintenance()
	test_recruitment()
	test_diplomacy()
	test_plague_and_rounds()
	test_tactical()
	test_battle_integration()
	print("%d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)

func test_scenario() -> void:
	var game := Campaign.new()
	check(game.provinces.size() == 8,"eight-province scenario")
	check(game.capacity(0) == 10 and game.capacity(1) == 10,"starting capacity")
	check(Logistics.committed(game,0) == 9 and Logistics.committed(game,1) == 8,"starting committed manpower including ships")
	check(game.income(0) == 30 and game.income(1) == 30,"printed taxes, cities and seats")
	check(game.neighbors("G1").is_empty(),"G1 island has no land connection")
	check(game.provinces.G2.plague == 1,"initial outbreak has no initial loss")
	game.advance()
	check(game.phase == 1 and game.factions[0].gold == 40 and game.factions[1].gold == 44,"maintenance charged before purchases")
	check(game.armies[0].units.size() == 7,"supplied army suffers no attrition")
	game.advance()
	check(game.phase == 1,"purchases pass does not charge upkeep again")
	check(game.factions[0].gold == 40,"upkeep charged once")

func test_supply() -> void:
	var game := Campaign.new()
	check(Logistics.supplied(game,"G2",0),"Gulf army supplied over S1 through functioning port")
	game.fleets.clear()
	check(not Logistics.supplied(game,"G2",0),"lost ship chain cuts Gulf supply")
	game = clean_game()
	game.provinces.G2.city = true
	for id in ["N4","N2","N1"]: game.provinces[id].cubes[0] = 1
	game.provinces.N1.owner = 1
	game.provinces.N1.status = "annexed"
	check(Logistics.supplied(game,"N4",0),"own influence permits transit through rival political control")
	game.armies.append({"owner":1,"province":"N1","units":["infantry"],"spent":false})
	check(not Logistics.supplied(game,"N4",0),"hostile field army blocks influence route")
	game.armies.clear()
	game.provinces.N1.city = true
	game.provinces.N1.wall = true
	check(not Logistics.supplied(game,"N4",0),"hostile walled city blocks supply transit")
	game.armies.append({"owner":0,"province":"N1","units":["infantry"],"spent":false})
	check(Logistics.supplied(game,"N1",0),"besieger may trace out of its own province")

func test_maintenance() -> void:
	var game := Campaign.new()
	game.fleets.clear()
	Logistics.maintenance(game)
	check(game.factions[0].gold == 46,"seven infantry owe full 14 upkeep before attrition")
	check(game.armies[0].units.size() == 5,"unsupplied seven-unit army loses ceiling seven/four")
	game = clean_game()
	game.provinces.G2.population = 2
	var force: Array = []
	for i in range(10): force.append("infantry")
	game.armies.append({"owner":0,"province":"G1","units":force,"spent":false})
	Logistics.maintenance(game)
	check(game.factions[0].gold == 37,"20 basic upkeep plus ceiling 20/9 surcharge")
	check(game.armies[0].units.size() == 10,"exceeding manpower never automatically disbands units")
	game = Campaign.new()
	game.factions[1].gold = 0
	Logistics.maintenance(game)
	check(game.factions[1].arrears == 16 and game.factions[1].stability == 1,"unpaid maintenance becomes arrears and lowers stability")
	check(game.armies[1].units.size() == 8,"first unpaid bill does not cause immediate desertion")
	Logistics.maintenance(game)
	check(game.armies[1].units.size() == 7,"prior arrears cause next maintenance desertion")
	game.phase = 1
	game.active = 1
	check(game.buy("A1","infantry").contains("arrears"),"arrears block optional purchases")
	game.phase = 5
	game.advance()
	check(game.factions[1].arrears == 2 and game.factions[1].gold == 0,"income automatically clears debt before becoming spendable")

func test_recruitment() -> void:
	var game := Campaign.new()
	game.phase = 1
	check(game.buy("G1","infantry").contains("queued"),"recruitment creates queued order")
	check(game.factions[0].gold == 56 and Logistics.committed(game,0) == 10,"purchase paid and manpower reserved immediately")
	check(game.buy("G1","infantry").contains("manpower"),"queued purchases block over-cap recruitment")
	Logistics.deploy(game)
	check(game.orders.is_empty() and Logistics.committed(game,0) == 10,"deployment does not double-count reserved manpower")
	check(game.armies.size() == 3 and game.armies[2].spent,"new destination creates a spent army")
	game = Campaign.new()
	game.phase = 1
	game.buy("G1","infantry")
	game.provinces.G2.owner = -1
	Logistics.deploy(game)
	check(Logistics.committed(game,0) == 9 and game.orders.is_empty(),"capacity loss cancels queued purchase, preserves deployed forces")
	check(game.factions[0].gold == 56,"failed deployment gives no refund")
	game = clean_game()
	game.phase = 1
	game.active = 1
	for i in range(3): game.buy("A2","infantry")
	check(game.buy("A2","infantry").contains("quota"),"local population deployment quota enforced")
	game = clean_game()
	game.phase = 1
	for i in range(3): game.buy("G1","cube")
	check(game.buy("G1","cube").contains("limit"),"maximum three influence purchases per round")

func test_diplomacy() -> void:
	var game := clean_game()
	game.fleets.append({"owner":0,"ships":1,"zone":"S1"})
	game.phase = 2
	game.act("N1","place")
	check(game.provinces.N1.cubes[0] == 1 and game.active == 1,"influence actions alternate")
	game.advance()
	game.act("N1","place")
	game.act("N1","client")
	check(game.provinces.N1.status == "client" and game.capacity(0) == 11,"majority establishes client")
	game.factions[0].ap = 4
	game.act("N1","place")
	check(game.act("N1","annex").contains("predate"),"new client cannot annex without an army")
	game.round_number = 2
	game.act("N1","annex")
	check(game.provinces.N1.status == "annexed" and game.capacity(0) == 13,"older full-influence client annexes")
	check(game.factions[0].gold == 56,"annexation costs four gold")
	game = clean_game()
	game.phase = 2
	game.provinces.N1.cubes = [3,0]
	game.armies.append({"owner":0,"province":"N1","units":["infantry"],"spent":false})
	check(game.act("N1","annex").contains("annex in"),"occupying army may directly annex full-influence independent province")
	game = clean_game()
	game.phase = 2
	game.provinces.N4.cubes = [1,2]
	game.active = 1
	game.provinces.N4.institution = 0
	game.provinces.N4.cubes = [1,0]
	check(game.contest("N4").contains("protects"),"institution protects last rival cube")

func test_plague_and_rounds() -> void:
	var game := Campaign.new()
	game.random.seed = 42
	game.progress_plague()
	check(game.provinces.G2.plague == 2 and game.effective_population("G2") == 2,"plague advances and permanently reduces population")
	check(game.provinces.G2.cubes[0] == 2,"influence trimmed to reduced capacity")
	game.progress_plague()
	check(game.provinces.G2.plague == 3,"stage two becomes recovered")
	game.progress_plague()
	check(game.provinces.G2.plague == 3,"recovered province never advances or reinfects")
	game = Campaign.new()
	var limit := 0
	while not game.finished and limit < 100:
		game.advance()
		limit += 1
	check(game.finished and game.round_number == 6,"complete six-round campaign terminates")
	check(limit == 54,"six complete rounds include both players passing shared phases")

func test_tactical() -> void:
	var game := Campaign.new()
	var battle := TacticalBattle.new(["infantry","infantry","infantry"],["infantry","infantry","infantry"],game.profiles,123)
	check(battle.units.size() == 6 and battle.command >= 1,"battle deploys every unit and rolls CP")
	check(battle.units[0].cell.y == 2 and battle.units[3].cell.y == 9,"deployment uses opposing front rows")
	battle.command = 6
	check(battle.move(0,Vector2i(1,4)).contains("moved"),"tactical move respects two-cell allowance")
	check(battle.move(0,Vector2i(1,5)).contains("already"),"unit cannot move twice per half-round")
	check(battle.move(1,Vector2i(1,4)).contains("empty"),"no stacking")
	check(battle.move(1,Vector2i(2,8)).contains("exceeds"),"distant move rejected")
	battle.units[3].cell = Vector2i(1,5)
	battle.units[0].moved = false
	check(battle.move(0,Vector2i(2,4)).contains("disengage"),"contact bars ordinary movement")
	check(battle.move(0,Vector2i(1,3)).contains("moved") and battle.command == 3,"disengagement costs two command points")
	battle.units[0].cell = Vector2i(1,0)
	battle.units[3].cell = Vector2i(1,1)
	battle.recoil(0,3)
	check(battle.units[0].state == "routed" and battle.survivors(0).size() == 3,"off-board recoil routes rather than destroys")
	battle.units[1].cell = Vector2i(3,3)
	battle.units[4].cell = Vector2i(3,4)
	battle.units[2].cell = Vector2i(3,2)
	battle.recoil(1,4)
	check(battle.units[1].state == "destroyed" and battle.survivors(0).size() == 2,"blocked recoil destroys")
	battle.end_half_round()
	check(battle.finished and battle.winner == 1,"routed plus destroyed losses trigger one-third army break")
	battle = TacticalBattle.new(["artillery"],["infantry"],game.profiles,22)
	battle.units[0].cell = Vector2i(3,3)
	battle.units[1].cell = Vector2i(3,6)
	check(battle.clear_shot(0,1),"forward target in cannon range is legal")
	battle.units.append({"side":0,"type":"infantry","cell":Vector2i(3,5),"facing":Vector2i.DOWN,"general":false,"state":"field","moved":false})
	check(not battle.clear_shot(0,1),"intervening unit blocks line of sight")
	battle = TacticalBattle.new(["infantry"],["infantry"],game.profiles,22)
	for i in range(24): battle.end_half_round()
	check(battle.finished and battle.winner == 1,"12 full battle rounds force attacker withdrawal")

func test_battle_integration() -> void:
	var game := Campaign.new()
	game.phase = 3
	check(game.move_army("G2","N1").contains("Battle"),"independent province raises militia and opens tactical battle")
	check(game.battle.units.size() == 10,"seven attackers face three militia")
	game.battle.active = 1
	game.battle.withdraw()
	game.finish_battle()
	check(game.battle == null and game.armies[0].province == "N1","battle victory moves campaign army into province")
	check(game.provinces.N1.owner == -1 and game.provinces.N1.cubes[0] == 1,"conquest grants influence but no political ownership")
	check(game.factions[0].pool == 6 and game.factions[0].cp == 3,"Spanish battle reward and one activation cost")
	check(game.active == 1 and game.armies[0].spent,"military action alternates and attacker remains spent")
	game = Campaign.new()
	game.phase = 3
	game.move_army("G2","N1")
	game.battle.withdraw()
	game.finish_battle()
	check(game.armies[0].province == "G2" and game.provinces.N1.owner == -1,"losing attacker retreats to entry province; militia disperse")
	game = clean_game()
	game.phase = 3
	game.armies.append({"owner":0,"province":"N1","units":["infantry"],"spent":false})
	game.move_army("N1","A2")
	check(game.battle == null and game.provinces.A2.owner == -1,"undefended enemy province is conquered without a fabricated battle")
	check(game.factions[0].pool == 4,"empty province grants no battle reward")
