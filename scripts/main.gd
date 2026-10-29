extends Control

const POSITIONS = {"G1":Vector2(80,95),"G2":Vector2(170,220),"A1":Vector2(590,100),"A2":Vector2(440,220),"N1":Vector2(300,300),"N2":Vector2(455,395),"N3":Vector2(145,440),"N4":Vector2(600,380)}
var game := Campaign.new()
var selected := "N1"
var title: Label
var ledger: Label
var details: Label
var notice: Label
var log_view: RichTextLabel
var map: Control
var nodes: Dictionary = {}
var move_origin := ""
var target_action := "move"
var extra_picker: OptionButton
var group_selection: Array = []
var action_buttons: Dictionary = {}
var recruit_picker: OptionButton
var battle_window: Window
var battle_cells: Array[Button] = []
var battle_status: Label
var battle_log: RichTextLabel
var selected_unit := -1
var phase_button: Button
var ai_mode: OptionButton
var ai_paused := false
var ai_elapsed := 0.0
var ai_pause_buttons: Array[CheckButton] = []
var tactical_buttons: Array[Button] = []
var extra_button: Button

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",24)
	margin.add_theme_constant_override("margin_right",24)
	margin.add_theme_constant_override("margin_top",20)
	margin.add_theme_constant_override("margin_bottom",20)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	title = Label.new()
	title.add_theme_font_size_override("font_size",28)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "EL DORADO  /  TWO-PLAYER CAMPAIGN PROTOTYPE  /  RULES v0.1"
	subtitle.modulate = Color("d1b36d")
	root.add_child(subtitle)
	var control_row := HBoxContainer.new()
	root.add_child(control_row)
	ai_mode = OptionButton.new()
	for mode in ["Play Gulf · Alliance AI","Play Alliance · Gulf AI","Hotseat · both human","Watch · both AI"]: ai_mode.add_item(mode)
	ai_mode.item_selected.connect(change_ai_mode)
	control_row.add_child(ai_mode)
	add_ai_pause(control_row)
	ledger = Label.new()
	ledger.add_theme_font_size_override("font_size",15)
	root.add_child(ledger)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	map = Control.new()
	map.custom_minimum_size = Vector2(780,550)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(map)
	map.draw.connect(draw_map)
	for id in POSITIONS:
		var button := Button.new()
		button.position = POSITIONS[id]
		button.custom_minimum_size = Vector2(125,70)
		button.pressed.connect(select_province.bind(id))
		map.add_child(button)
		nodes[id] = button
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 400
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.x = 380
	scroll.add_child(panel)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.y = 150
	panel.add_child(details)
	for entry in [["Place influence", "place"],["Contest rival influence", "contest"],["Client agreement", "client"],["Annex · 2 AP + 4 gold", "annex"]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(take_action.bind(entry[1]))
		panel.add_child(button)
		action_buttons[entry[1]] = button
	recruit_picker = OptionButton.new()
	for unit in ["infantry","cavalry","artillery","bow","skirmisher","jaguar","eagle","crossbow","shot","ship","cube"]:
		recruit_picker.add_item(unit + (" · 3 gold" if unit == "cube" else " · %d gold (provisional)" % game.profiles[unit].price))
	panel.add_child(recruit_picker)
	var buy_button := Button.new()
	buy_button.text = "Buy at selected province"
	buy_button.pressed.connect(buy_recruit)
	panel.add_child(buy_button)
	action_buttons["buy"] = buy_button
	var move_button := Button.new()
	move_button.text = "Move / attack from selected province"
	move_button.pressed.connect(arm_move)
	panel.add_child(move_button)
	action_buttons["move"] = move_button
	extra_picker = OptionButton.new()
	for option in ["Build city","Build wall","Build port","Build institution","Build road","Transport army","Split army","Relocate influence","Fortify","Suppress","Destroy institution","Prepare siege","Assault","Sortie","Spend devotion","Observe","Offer at temple","Relocate seat","Propose / accept truce","Break truce","Other income player","Save campaign","Load campaign"]: extra_picker.add_item(option)
	panel.add_child(extra_picker)
	extra_button = Button.new()
	extra_button.text = "Apply selected action"
	extra_button.pressed.connect(extra_action)
	panel.add_child(extra_button)
	var next := Button.new()
	phase_button = next
	next.text = "Next phase / Pass"
	next.pressed.connect(next_phase)
	panel.add_child(next)
	var reset := Button.new()
	reset.text = "Restart scenario"
	reset.pressed.connect(restart)
	panel.add_child(reset)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size = Vector2(380,75)
	panel.add_child(notice)
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size.y = 180
	log_view.scroll_following = true
	panel.add_child(log_view)
	var scope := Label.new()
	scope.text = "PROVISIONAL: unit and construction prices, starting composition. Two-player test scenario.\nUse the action menu for construction, transports, sieges, religion, treaties and saving. See README for rule coverage."
	root.add_child(scope)
	build_battle_window()
	refresh()

func draw_map() -> void:
	for border in Campaign.BORDERS:
		map.draw_line(POSITIONS[border[0]] + Vector2(62,35), POSITIONS[border[1]] + Vector2(62,35), Color("53676c"), 3, true)
	map.draw_string(ThemeDB.fallback_font,Vector2(30,40),"S1 · GULF     G1 is an island; no land border to G2",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("7fb5c9"))

func select_province(id: String) -> void:
	selected = id
	if not move_origin.is_empty() and human_campaign_turn():
		match target_action:
			"transport": notice.text = NavalRules.transport(game,move_origin,id)
			"road": notice.text = CampaignRules.project(game,move_origin,"road",id)
			"relocate": notice.text = game.relocate(move_origin,id)
			_: notice.text = game.move_army(move_origin,id)
		move_origin = ""
		if game.battle != null:
			selected_unit = -1
			refresh_battle()
			battle_window.popup_centered()
	refresh()

func take_action(action: String) -> void:
	if not human_campaign_turn(): return
	notice.text = game.contest(selected) if action == "contest" else game.act(selected,action)
	refresh()

func next_phase() -> void:
	if not human_campaign_turn(): return
	game.advance()
	move_origin = ""
	notice.text = "Phase: %s. %s" % [Campaign.PHASES[game.phase], "Pass ends this faction’s participation." if game.phase in [1,2,3] else "Continue to resolve this phase."]
	refresh()

func restart() -> void:
	var controllers := game.ai_players.duplicate()
	game = Campaign.new()
	game.ai_players = controllers
	ai_elapsed = 0.0
	move_origin = ""
	battle_window.hide()
	notice.text = "New campaign with provisional unit values."
	refresh()

func refresh() -> void:
	if game.phase == 5 and game.battle == null and game.ai_players[game.active] and not game.ai_players[1-game.active]: game.active = 1-game.active
	title.text = "Round %d / 6 · %s · %s" % [game.round_number, Campaign.PHASES[game.phase], "Complete" if game.finished else game.factions[game.active].name + (" · AI" if game.ai_players[game.active] else " · Human")]
	ledger.text = ""
	for i in range(2):
		var f: Dictionary = game.factions[i]
		ledger.text += "%s: %d gold · debt %d · stability %d · manpower %d/%d · cubes %d · AP %d · CP %d · income %d\n" % [f.name,f.gold,f.arrears,f.stability,Logistics.committed(game,i),game.capacity(i),f.pool,f.ap,f.cp,game.income(i)]
	for id in nodes:
		var p: Dictionary = game.provinces[id]
		var count := 0
		for army in game.armies:
			if army.province == id: count += army.units.size()
		nodes[id].text = "%s · %s\nG%d / A%d · E%d\n%d troops · plague %d" % [id,p.status,p.cubes[0],p.cubes[1],game.effective_population(id),count,p.plague]
		nodes[id].modulate = Color("8fc9e3") if p.owner == 0 else (Color("e6be72") if p.owner == 1 else Color("c5d0c5"))
	var p: Dictionary = game.provinces[selected]
	details.text = "%s  /  %s\nOwner: %s\nPopulation: %d · printed tax: %d\nInfluence: Gulf %d / Alliance %d\nLand borders: %s" % [selected,p.status,"Independent" if p.owner < 0 else game.factions[p.owner].name,p.population,p.population*2,p.cubes[0],p.cubes[1],", ".join(game.neighbors(selected))]
	var army_text := ""
	for army in game.armies:
		if army.province == selected:
			army_text += "\n%s: %d units · %s · %s" % [game.factions[army.owner].name,army.units.size(),"supplied" if Logistics.supplied(game,selected,army.owner) else "UNSUPPLIED","spent" if army.spent else "ready"]
	details.text += army_text + "\nQueued recruits: %d" % game.orders.size()
	for key in action_buttons:
		var required := 1 if key == "buy" else (3 if key == "move" else 2)
		action_buttons[key].disabled = not human_campaign_turn() or game.phase != required
	phase_button.disabled = not human_campaign_turn()
	extra_button.disabled = game.battle != null or (game.phase in [1,2,3] and game.ai_players[game.active])
	var mode_index := 3 if game.ai_players == [true,true] else (0 if game.ai_players == [false,true] else (1 if game.ai_players == [true,false] else 2))
	ai_mode.select(mode_index)
	phase_button.text = "Pass %s turn" % Campaign.PHASES[game.phase] if game.phase in [1,2,3] else "Resolve %s → continue" % Campaign.PHASES[game.phase]
	log_view.text = "\n".join(game.history)
	map.queue_redraw()

func buy_recruit() -> void:
	if not human_campaign_turn(): return
	var units := ["infantry","cavalry","artillery","bow","skirmisher","jaguar","eagle","crossbow","shot","ship","cube"]
	notice.text = game.buy(selected,units[recruit_picker.selected])
	refresh()

func arm_move() -> void:
	if not human_campaign_turn(): return
	move_origin = selected
	target_action = "move"
	notice.text = "Choose an adjacent destination for the army at %s. Select another phase to cancel." % selected

func build_battle_window() -> void:
	battle_window = Window.new()
	battle_window.title = "El Dorado · tactical battle · provisional profiles"
	battle_window.size = Vector2i(1040,730)
	battle_window.unresizable = true
	battle_window.exclusive = true
	battle_window.close_requested.connect(func(): battle_status.text += "\nResolve or withdraw to return to the campaign.")
	add_child(battle_window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	battle_window.add_child(margin)
	var body := HBoxContainer.new()
	margin.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 12
	body.add_child(grid)
	for y in range(12):
		for x in range(12):
			var button := Button.new()
			button.custom_minimum_size = Vector2(46,50)
			button.add_theme_font_size_override("font_size",14)
			button.pressed.connect(battle_cell_pressed.bind(Vector2i(x,y)))
			grid.add_child(button)
			battle_cells.append(button)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 370
	body.add_child(panel)
	battle_status = Label.new()
	battle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(battle_status)
	add_ai_pause(panel)
	var instructions := Label.new()
	instructions.text = "Select your unit, then an empty cell.\nI = infantry · C = cavalry · A = artillery\n★ = general · arrow = facing\nTurn consumes this unit's movement.\nEnd half-round resolves shooting / melee.\nOpen terrain · automatic deployment / targets\nGroup: add units, then choose a destination."
	panel.add_child(instructions)
	for entry in [["Arrange / confirm deployment", "deploy"],["Begin shooting", "shoot"],["Use Scouts", "scouts"],["Use Discipline", "discipline"],["Toggle skirmisher / eagle flee", "flee"],["Rotate selected unit", "turn"],["Add selected to group", "group"],["Clear group", "clear_group"],["End half-round: shoot & fight", "end"],["Withdraw active side", "withdraw"]]:
		var button := Button.new()
		button.text = entry[0]
		tactical_buttons.append(button)
		button.pressed.connect(tactical_action.bind(entry[1]))
		panel.add_child(button)
	battle_log = RichTextLabel.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_log.scroll_following = true
	panel.add_child(battle_log)

func battle_cell_pressed(cell: Vector2i) -> void:
	if game.battle == null or CampaignAI.controls_turn(game): return
	var occupant := game.battle.at(cell)
	if occupant >= 0 and game.battle.shooting_stage and game.battle.units[occupant].side != game.battle.active:
		notice.text = game.battle.choose_shot(selected_unit,occupant)
	elif occupant >= 0 and game.battle.units[occupant].side == game.battle.active:
		selected_unit = occupant
	else:
		if game.battle.deployment:
			notice.text = game.battle.deployment_move(selected_unit,cell)
		elif group_selection.size() > 1 and selected_unit >= 0:
			notice.text = game.battle.move_group(group_selection,cell-game.battle.units[selected_unit].cell)
		else: notice.text = game.battle.move(selected_unit,cell)
	refresh_battle()

func tactical_action(action: String) -> void:
	if game.battle == null or CampaignAI.controls_turn(game): return
	match action:
		"deploy":
			if game.battle.half_round == 0 and not game.battle.deployment_done and not game.battle.shooting_stage and not game.battle.units.any(func(u): return u.moved):
				if not game.battle.deployment: game.battle.deployment = true; game.battle.active = 0
				else: notice.text = game.battle.confirm_deployment()
		"shoot":
			if not game.battle.deployment: game.battle.shooting_stage = true
		"scouts": notice.text = game.battle.use_tradition("Scouts")
		"discipline": notice.text = game.battle.use_tradition("Discipline")
		"flee": game.battle.flee_enabled[game.battle.active] = not game.battle.flee_enabled[game.battle.active]
		"group":
			if selected_unit >= 0 and selected_unit not in group_selection: group_selection.append(selected_unit)
		"clear_group": group_selection.clear()
		"turn": notice.text = game.battle.turn(selected_unit)
		"end":
			game.battle.end_half_round()
			group_selection.clear()
			selected_unit = -1
		"withdraw": game.battle.withdraw()
	if game.battle.finished:
		game.finish_battle()
		battle_window.hide()
		notice.text = game.history.back()
		refresh()
	else: refresh_battle()

func refresh_battle() -> void:
	var battle := game.battle
	if battle == null: return
	var player: int = game.battle_context.attacker if battle.active == 0 else 1-game.battle_context.attacker
	battle_status.text = "%s\nBattle round %d / 12 · %d command points\n%s" % [game.factions[player].name + (" · AI" if game.ai_players[player] else " · Human"),1+int(battle.half_round/2.0),battle.command,notice.text]
	for button in tactical_buttons: button.disabled = CampaignAI.controls_turn(game)
	for cell_button in battle_cells: cell_button.disabled = CampaignAI.controls_turn(game)
	for y in range(12):
		for x in range(12):
			var index := battle.at(Vector2i(x,y))
			var button: Button = battle_cells[y*12+x]
			button.text = "%s%d" % [char(65+x),y+1]
			button.modulate = Color("789399")
			if battle.terrain.has(Vector2i(x,y)): button.modulate = Color("4b7450") if battle.terrain[Vector2i(x,y)] == "rough" else Color("806c50")
			if index >= 0 and (not battle.deployment or battle.units[index].side == battle.active):
				var unit: Dictionary = battle.units[index]
				var arrow := "↓" if unit.facing == Vector2i.DOWN else ("↑" if unit.facing == Vector2i.UP else ("→" if unit.facing == Vector2i.RIGHT else "←"))
				button.text = unit.type.substr(0,1).to_upper() + arrow + ("★" if unit.general else "")
				var owner: int = game.battle_context.attacker if unit.side == 0 else 1-game.battle_context.attacker
				button.modulate = Color("8fc9e3") if owner == 0 else Color("e6be72")
				if unit.moved: button.modulate = button.modulate.darkened(0.25)
				if index in group_selection: button.modulate = Color("b1ed9c")
				if index == selected_unit: button.modulate = Color.WHITE
	battle_log.text = "\n".join(battle.messages)

func extra_action() -> void:
	var action := extra_picker.get_item_text(extra_picker.selected)
	if game.battle != null: return
	if action not in ["Save campaign","Load campaign","Other income player"] and (not human_campaign_turn() or game.ai_players[game.active]): return
	match action:
		"Build city","Build wall","Build port","Build institution": notice.text = CampaignRules.project(game,selected,action.trim_prefix("Build "))
		"Build road","Transport army","Relocate influence":
			move_origin = selected
			target_action = "road" if action == "Build road" else ("transport" if action == "Transport army" else "relocate")
			notice.text = "Choose the destination province for " + action.to_lower() + "."
		"Split army": notice.text = game.split_army(selected)
		"Fortify","Suppress","Destroy institution": notice.text = game.army_action(selected,action.to_lower())
		"Prepare siege": notice.text = game.army_action(selected,"prepare")
		"Assault": notice.text = game.army_action(selected,"assault")
		"Sortie": notice.text = game.sortie(selected)
		"Spend devotion": notice.text = game.policy("devotion",selected)
		"Observe": notice.text = game.policy("observe",selected)
		"Offer at temple": notice.text = game.policy("offer",selected)
		"Relocate seat": notice.text = game.policy("seat",selected)
		"Propose / accept truce": notice.text = game.policy("truce",selected)
		"Break truce": notice.text = game.policy("break",selected)
		"Other income player":
			if game.phase == 5 and not game.ai_players[1-game.active]: game.active = 1-game.active
		"Save campaign": notice.text = game.save_campaign()
		"Load campaign": notice.text = game.load_campaign()
	if game.battle != null:
		selected_unit = -1
		group_selection.clear()
		refresh_battle()
		battle_window.popup_centered()
	refresh()

func human_campaign_turn() -> bool:
	return not game.finished and game.battle == null and (game.phase in [0,4,5] or not game.ai_players[game.active])

func change_ai_mode(index: int) -> void:
	game.ai_players = [[false,true],[true,false],[false,false],[true,true]][index].duplicate()
	move_origin = ""
	ai_elapsed = 0.0
	if game.phase == 5 and game.ai_players[game.active] and not game.ai_players[1-game.active]: game.active = 1-game.active
	refresh()
	if game.battle != null: refresh_battle()

func add_ai_pause(parent: Node) -> void:
	var button := CheckButton.new()
	button.text = "Pause AI"
	button.toggled.connect(set_ai_paused)
	parent.add_child(button)
	ai_pause_buttons.append(button)

func set_ai_paused(value: bool) -> void:
	ai_paused = value
	for button in ai_pause_buttons: button.set_pressed_no_signal(value)

func _process(delta: float) -> void:
	if ai_paused or game.finished: return
	ai_elapsed += delta
	if ai_elapsed < 0.35: return
	ai_elapsed = 0.0
	run_ai_step()

func run_ai_step() -> bool:
	if ai_paused: return false
	var previous_battle := game.battle
	var previous_side := -1 if previous_battle == null else previous_battle.active
	if not CampaignAI.step(game): return false
	move_origin = ""
	if game.battle != previous_battle or game.battle != null and game.battle.active != previous_side:
		selected_unit = -1
		group_selection.clear()
	if game.battle != null:
		refresh_battle()
		if not battle_window.visible: battle_window.popup_centered()
	else: battle_window.hide()
	if not game.history.is_empty(): notice.text = game.history.back()
	# Income choices are shared; leave the visible controls with the human.
	if game.phase == 5 and game.battle == null and game.ai_players[game.active] and not game.ai_players[1-game.active]: game.active = 1-game.active
	refresh()
	return true
