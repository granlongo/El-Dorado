extends SceneTree

var failures := 0

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL UI: " + description)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var ui = packed.instantiate()
	ui.game.ai_players = [false,false]
	root.add_child(ui)
	await process_frame
	check(ui.nodes.size() == 8,"map buttons")
	check(ui.battle_cells.size() == 144,"tactical grid")
	check(ui.action_buttons.buy.disabled,"recruitment disabled outside Purchases")
	ui.next_phase()
	check(not ui.action_buttons.buy.disabled,"recruitment enabled in Purchases")
	ui.select_province("G1")
	ui.buy_recruit()
	check(ui.game.orders.size() == 1,"UI queues a recruit at selected province")
	while ui.game.phase != 3: ui.next_phase()
	check(not ui.action_buttons.move.disabled,"military action enabled")
	ui.select_province("G2")
	ui.arm_move()
	ui.select_province("N1")
	check(ui.game.battle != null,"UI move opens battle")
	check(ui.battle_window.visible,"battle window is visible")
	ui.battle_cell_pressed(Vector2i(1,2))
	check(ui.selected_unit == 0,"grid selects attacker")
	ui.game.battle.command = 6
	ui.battle_cell_pressed(Vector2i(1,4))
	check(ui.game.battle.units[0].cell == Vector2i(1,4),"grid moves selected unit")
	ui.tactical_action("end") # Withdrawal is legal only at the start of the next side's half-round.
	ui.tactical_action("withdraw")
	check(ui.game.battle == null and not ui.battle_window.visible,"withdraw returns to campaign")
	ui.restart()
	check(ui.game.round_number == 1 and ui.game.factions[0].gold == 60,"restart restores scenario")
	ui.queue_free()
	await process_frame
	print("UI smoke checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
