# El Dorado — Godot campaign prototype

Open `project.godot` in **Godot 4.6+** and press **F5**. No plugins or external assets are required. New games default to **human Gulf versus AI Triple Alliance**. The selector at the top also offers human Alliance versus AI Gulf, two-human hotseat play, and AI versus AI.

The eight-province Gulf versus Triple Alliance scenario now includes construction, naval transport, sieges, religion, treaties, revolts, victory conditions and saving alongside its economy, recruitment, influence and tactical combat. **The full six-faction ruleset is still in progress.** See [the mechanics coverage table](docs/mechanics-status.md) for precise remaining work.

## Simple AI opponent

Choose your faction using the top selector. The AI automatically handles its purchases, influence actions, army moves and tactical turns, including independent militia when you attack a neutral province. It takes one decision every 0.35 seconds so you can follow play. **Pause AI** is available on both the campaign and battle screens; the mode selector can return the campaign to hotseat control. Human action buttons are locked during AI turns.

In single-player modes you still resolve the shared **Maintenance**, **Deployment** and **Income** phases. The AI makes its own offering/observance choices when Income resolves. In **Watch · both AI**, shared phases also advance automatically. Controller choices survive restart and save/load. Older saves without controller settings load as hotseat games.

The AI uses simple public-state heuristics: preserve gold for upkeep, recruit core infantry/ranged support, finish political integration, occupy weaker targets, hold bridgeheads, use transport where legal, and advance toward enemies in battle. It calls the same rule methods as human players and receives no resource bonuses or privileged dice. It is an introductory opponent, without deep planning, construction strategy or negotiated diplomacy. Only the two currently implemented factions are available.

## Campaign controls

Select a province on the map. The ledger shows gold, debt, stability, manpower, cubes, influence actions, military commands and income. Each round has six phases:

1. Resolve **Maintenance** to pay upkeep before attrition. Over-capacity armies pay a surcharge; unpaid maintenance creates arrears. Prior arrears cause desertion.
2. In **Purchases**, choose a recruit and buy at the selected province. Units reserve manpower immediately and arrive at Deployment. Use the additional-action menu to queue a city, wall, port, institution or road. Road construction asks for a second province. Pass when your purchases are complete.
3. In **Influence**, place or contest cubes, establish clients, or annex. Actions alternate; passing ends your participation. The menu also offers relocation, seat relocation, devotion and bilateral truce proposals. The other player must accept a proposed truce on their turn.
4. In **Military**, select an origin, press **Move / attack**, then select the destination. Legal movement can cross multiple borders through friendly land. The menu offers transport, army splitting, fortification, suppression, institution destruction, siege preparation, assaults and sorties.
5. Resolve **Deployment** to recheck orders against current supply, ownership, national capacity and local quotas. Invalid orders are canceled without refunds.
6. Before resolving **Income**, use observance or temple offerings if desired. **Other income player** changes the player making those choices. Resolving the phase completes construction, advances plague, tests revolts, collects income, pays debt and generates influence. The Alliance loses influence if it made no offering. Victory is checked before advancing the round.

The action menu also saves or loads the campaign. Saves preserve phase, orders, projects and random-generator state. Finish an active tactical battle before saving/loading. Restart resets the session without deleting its save.

## Ships and sieges

Spanish ships are recruited at eligible port cities and use national manpower, the province's deployment quota and a two-ships-per-port purchase limit. Each fleet contains up to four ships; S1 holds up to eight friendly ships.

To transport troops, select a coastal origin, choose **Transport army**, then a different S1 coastal destination. The departure field must be friendly and clear of hostile fleets. Each ship holds three spaces; cavalry and artillery use two. Use **Split army** if a force cannot fit. Transport spends both the army and fleet's activation, with one command point. Friendly landings complete immediately; hostile landings open combat. Multi-zone naval play and persistent embarked cargo remain unfinished.

A defending force of six or fewer units automatically shelters in its walled city when attacked. The attacker controls the field while the defender retains political ownership. Garrison troops still count for manpower and upkeep and suffer unsupplied attrition. An army with cannon can assault immediately; other armies prepare in an earlier round, with the Engineers exception. Besieged defenders can sortie. Larger forces currently use ordinary field combat until mixed garrison deployment is implemented.

## Tactical controls

The board is 12×12. `I`, `C`, `A` denote infantry, cavalry and artillery; other profiles use their first letter. An arrow shows facing and a star identifies a general. Blue is Gulf and gold is Alliance. The opposing player controls independent militia.

Select a friendly unit and then an empty destination. Movement respects allowance, blocking units, terrain and enemy contact. Rotating uses its movement order; disengaging moves one cell backward for two commands. Add edge-connected units to a group and choose a destination relative to the selected unit to move the rigid formation for one command point.

**Arrange / confirm deployment** allows each player to rearrange their starting rows privately before movement. Click it to enter arrangement, then confirm each side; at least two units must remain in the front row. Default deployment is available if skipped.

**Begin shooting** closes movement. Select a shooter, then an enemy target to resolve a legal shot. **End half-round** resolves remaining eligible shooting and melee automatically. Units cannot fight as a principal or supporter more than once in that half-round. Defeats cause recoil, destruction or routing. Skirmisher/eagle flight can be toggled. Scouts and Discipline buttons are available when the army has those traditions. Withdrawal is legal only at the start of the active side's half-round.

One-third losses break a force; routed troops generally survive campaign retreat. After twelve full rounds, the defender wins. Native close-combat captures, Spanish early shock, cavalry pursuit, fortification, wall bonuses, and victory traditions are implemented with the limitations in the coverage table.

## Provisional values

The uploaded rulebook refers to unit and event tables absent from its plain text. The user approved provisional values. Unit prices, factors and starting forces are in `data/provisional_units.json`; construction prices are in `CampaignRules.PROJECT_COSTS`. Starting composition is seven Gulf infantry at G2 with two S1 ships, versus eight Alliance infantry at A2. Province terrain remains open in the current scenario; the battle engine supports additional terrain but a complete scenario table and placement interface remain outstanding. No invented event table is silently applied.

The unchanged supplied rulebook is in `docs/rulebook-v0.1.txt`. The prototype does not yet implement all six factions, full cultural recruitment/cohesion, every manual casualty/retreat choice, or all naval rules.

## Development

- `scripts/campaign.gd`: phase sequence, campaign actions, battle integration, persistence.
- `scripts/campaign_ai.gd`: bounded campaign and tactical AI decisions.
- `scripts/campaign_rules.gd`: construction, religion, unrest and victory.
- `scripts/naval_rules.gd`: ship recruitment, deployment, transport and encounter model.
- `scripts/logistics.gd`: supply, maintenance, manpower, deployment and garrison attrition.
- `scripts/tactical_battle.gd`: tactical model, orders, fire, combat and traditions.
- `scripts/main.gd`: campaign and tactical interface.

Run:

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --script tests/campaign_test.gd
godot --headless --path . --script tests/extended_test.gd
godot --headless --path . --script tests/ui_test.gd
godot --headless --path . --script tests/ai_test.gd
godot --headless --path . --quit-after 10
```

In the cloud shell, use `./scripts/godot-cloud.sh` instead of `godot --path .`; the wrapper supplies writable data/config/cache folders outside the checkout. The suites currently cover 70 campaign/tactical checks, 39 extended checks, 45 AI checks and the interface smoke flow. AI checks include seeded complete games, neutral-militia handoffs, resource limits, pause/control guards and backward-compatible save loading. They validate current behavior, not completeness or game balance.

Use the existing checkout in each isolated task. The `.godot/` cache is ignored; `.uid` files are source metadata. Development and tests do not publish the cloud environment.
