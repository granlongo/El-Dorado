extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL AI: "+message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var g := Campaign.new()
	check(g.ai_players == [false,true],"default is human Gulf versus AI Alliance")
	g.phase = 2
	var state: String = JSON.stringify(g.provinces)
	check(not CampaignAI.step(g) and JSON.stringify(g.provinces) == state,"AI never takes a human action")
	g.active = 1
	var before: int = g.factions[1].ap
	check(CampaignAI.step(g) and g.factions[1].ap == before-1,"AI spends an influence action through the rules")
	check(g.active == 0,"influence action hands control to the human")
	g = Campaign.new()
	g.phase = 1
	g.active = 1
	g.passed[0] = true
	var gold: int = g.factions[1].gold
	for n in range(10):
		if g.active != 1 or g.phase != 1: break
		CampaignAI.step(g)
	check(g.factions[1].gold < gold and not g.orders.is_empty(),"AI recruits")
	check(Logistics.committed(g,1) <= g.capacity(1),"AI never exceeds recruitment capacity")
	check(g.factions[1].gold >= CampaignAI.upkeep_reserve(g,1),"AI keeps an upkeep reserve")
	check(g.active == 0 and g.phase == 2,"AI purchase pass advances after both passed")
	g = Campaign.new()
	g.phase = 1
	g.active = 1
	g.factions[1].gold = 0
	g.factions[1].arrears = 20
	CampaignAI.step(g)
	check(g.orders.is_empty() and g.factions[1].gold == 0 and g.passed[1],"bankrupt AI passes without inventing resources")
	g = Campaign.new()
	g.phase = 2
	g.active = 1
	g.provinces.N1.cubes = [0,3]
	g.provinces.N1.owner = 1
	g.provinces.N1.status = "client"
	g.provinces.N1.client_round = 0
	CampaignAI.step(g)
	check(g.provinces.N1.status == "annexed" and g.factions[1].gold == 56,"AI prioritizes legal annexation")
	g = Campaign.new()
	g.phase = 3
	g.active = 1
	CampaignAI.step(g)
	check(g.battle != null and g.factions[1].cp == 3,"AI initiates a legal attack")
	check(CampaignAI.actor(g) == 1,"AI controls its attacking tactical side")
	var b: TacticalBattle = g.battle
	var steps := 0
	while CampaignAI.controls_turn(g) and g.battle != null and steps < 20:
		CampaignAI.step(g)
		steps += 1
	check(g.battle != null and g.battle.active == 1,"AI finishes its tactical half-round")
	check(CampaignAI.actor(g) == 0 and not CampaignAI.step(g),"human controls neutral militia against AI attacker")
	g = Campaign.new()
	g.phase = 3
	g.move_army("G2","N1")
	g.battle.end_half_round()
	check(CampaignAI.actor(g) == 1 and CampaignAI.controls_turn(g),"AI controls militia against human attacker")
	g.battle.deployment = true
	g.battle.active = 1
	CampaignAI.step(g)
	check(not g.battle.deployment,"AI confirms its hidden deployment without deadlock")
	g = Campaign.new()
	g.phase = 5
	g.armies[1].province = "A1"
	g.advance()
	check(g.armies[1].units.size() == 7,"AI makes its temple offering before income resolution")
	g = Campaign.new()
	g.ai_players = [true,false]
	check(g.save_campaign("user://ai-test.save").contains("saved"),"save AI selection")
	g.ai_players = [false,false]
	check(g.load_campaign("user://ai-test.save").contains("loaded") and g.ai_players == [true,false],"load restores AI selection")
	var file := FileAccess.open("user://ai-test.save",FileAccess.READ)
	var data: Dictionary = file.get_var(false); file.close()
	data.erase("ai_players")
	file = FileAccess.open("user://ai-legacy.save",FileAccess.WRITE); file.store_var(data); file.close()
	check(g.load_campaign("user://ai-legacy.save").contains("loaded") and g.ai_players == [false,false],"legacy saves remain hotseat")
	var first_digest := ""
	for seed_value in [17,23,41,17]:
		g = Campaign.new()
		g.ai_players = [true,true]
		g.random.seed = seed_value
		steps = 0
		var tactical_steps := 0
		while not g.finished and steps < 10000:
			if g.battle != null: tactical_steps += 1
			if not CampaignAI.step(g): break
			steps += 1
		check(g.finished and g.round_number <= 6,"AI vs AI finishes for seed %d in %d steps" % [seed_value,steps])
		check(tactical_steps > 0,"simulation exercises tactical battles")
		check(g.factions.all(func(f): return f.gold >= 0 and f.ap >= 0 and f.cp >= 0),"simulation preserves nonnegative resources")
		var digest := JSON.stringify([g.provinces,g.factions,g.armies,g.history])
		if seed_value == 17:
			if first_digest.is_empty(): first_digest = digest
			else: check(digest == first_digest,"same seed reproduces the same complete game")
		print("Seed %d: %d steps, %d tactical steps, round %d" % [seed_value,steps,tactical_steps,g.round_number])
	await test_ui()
	print("AI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func test_ui() -> void:
	var ui = load("res://scenes/main.tscn").instantiate()
	root.add_child(ui)
	await process_frame
	ui.set_process(false) # Drive the same tick directly for deterministic tests.
	ui.game.phase = 2
	ui.game.active = 1
	ui.refresh()
	check(ui.action_buttons.place.disabled and ui.phase_button.disabled,"human buttons disabled during AI action")
	var before: int = ui.game.factions[1].ap
	ui.take_action("place")
	ui.next_phase()
	check(ui.game.factions[1].ap == before and ui.game.active == 1,"handler guards prevent acting for AI")
	ui.set_ai_paused(true)
	check(not ui.run_ai_step() and ui.game.active == 1,"pause stops AI")
	ui.set_ai_paused(false)
	check(ui.run_ai_step() and ui.game.active == 0,"tick hands back control")
	ui.change_ai_mode(1)
	check(ui.game.ai_players == [true,false],"can play Alliance with Gulf AI")
	ui.restart()
	check(ui.game.ai_players == [true,false],"restart preserves controller selection")
	ui.game.phase = 3
	ui.game.active = 0
	ui.run_ai_step()
	check(ui.game.battle != null and ui.battle_window.visible,"AI-started battle opens the window")
	check(ui.tactical_buttons.all(func(button): return button.disabled),"human tactical commands disabled on AI side")
	var cp: int = ui.game.battle.command
	ui.tactical_action("end")
	check(ui.game.battle.command == cp and ui.game.battle.active == 0,"tactical handler cannot skip AI turn")
	for n in range(20):
		if ui.game.battle == null or ui.game.battle.active == 1: break
		ui.run_ai_step()
	check(ui.game.battle != null and ui.game.battle.active == 1 and not ui.tactical_buttons[0].disabled,"tactical controls return to the human")
	ui.tactical_action("withdraw")
	check(ui.game.battle == null and not ui.battle_window.visible,"human withdrawal returns from AI battle")
	ui.change_ai_mode(2)
	check(ui.game.ai_players == [false,false] and not ui.run_ai_step(),"hotseat disables automation")
	ui.queue_free()
	await process_frame
