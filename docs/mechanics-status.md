# Rulebook implementation status

The playable scenario remains Gulf versus Triple Alliance, eight provinces and S1. Prices and unit factors omitted from the uploaded tables use the user-approved provisional values. This file records actual coverage; the complete six-faction campaign is not implemented yet.

| System | Current behavior | Remaining work |
| --- | --- | --- |
| Phase flow | Shared maintenance, purchases, alternating influence/military actions, deployment and income | Initial first player is fixed; subsequent first player rotates |
| Economy | Taxes, city/seat income, committed and reserved manpower, upkeep surcharge, arrears and desertion | Player-selected casualties and voluntary disbanding |
| Supply | Influence/ownership/occupation routes, hostile blocks, S1 port ships, siege supply, snapshot attrition | Four-zone chains, canoe restrictions, embarked cargo persistence |
| Recruitment | Infantry, cavalry, artillery, ranged and elite profiles; quotas; purchase/deploy validation; ships | Full cultural access and allied-unit cohesion |
| Construction | Cities, walls, ports, institutions, roads; payment now and completion later; destination loss cancels | Native-specific construction restrictions beyond the current two factions |
| Political integration | Placement, contests, clients, annexation, protected institutions, relocation and seat relocation | Full terrain pricing and access treaties |
| Treaties | Truce offer/accept, two-round duration, attack restrictions, breaking costs stability; legal besieger withdrawal | Gold transfers, separate access agreements, permanent Spanish pact in six-player scenario |
| Campaign movement | Up to two borders, three for cavalry, one for artillery; roads and terrain costs; one activation; splitting | Player-selected subset splits/merges and full terrain/culture data |
| Military actions | Fortify, suppress, destroy institution, prepare siege, assault and sortie | Destruction of other structures/road endpoints; choice of garrison subset when more than six defenders |
| Siege | Automatic garrison for forces of six or fewer, preserved owner, field income suppression, garrison upkeep/manpower/attrition, preparation, cannon/Engineers assault, relief/sortie | Port evacuation/surrender choices and mixed field/garrison deployment |
| Naval | Ship purchase/deployment and same-zone transport, capacity per carrier, spent units/fleets; paired encounter resolver | Playable multi-zone fleet movement, naval pairing/retreat UI, carrier-specific cargo loss; native fleets |
| Tactical deployment | Default deployment plus optional private rearrangement/confirmation | Mandatory simultaneous deployment and player terrain placement |
| Tactical orders | Single-unit movement, facing, disengagement, rigid connected groups, contact stops movement | Arbitrary group path selection and facing as part of movement |
| Shooting | Manual target selection after movement, automatic remaining fire, arc/range/obstruction/contact checks, rain and cannon movement restrictions | Player-selected full shot/melee ordering |
| Melee | Opposed factors, general/supply modifiers, side/rear/flank penalties capped at two, single principal/supporter use | Fully explicit supporter selection |
| Outcomes | Recoil, destruction, routing, optional skirmisher/eagle two-cell flight, break threshold, 12-round cap, start-of-half-round withdrawal | Owner-selected overflow/casualty choices; complex mutual retreats |
| Terrain | Rough/hill movement, water/bridges and line-of-sight geometry supported by battle engine | Campaign provinces currently retain open terrain pending full scenario data; terrain-placement UI |
| Combat abilities | Jaguar margin destruction, Spanish early shock, native captures, cavalry pursuit, fortification and wall bonuses | Maya traps, Inca/Maya movement exceptions; more precise cannon nomination UI |
| Traditions | Victory gains/losses, Scouts next-move bonus, Discipline next die reroll, Engineers same-round assault | Reroll decision after seeing the die; persistent general host identity |
| Religion | Temple/mission construction, protected cube, generation, offerings/prisoners, Alliance missed-offering penalty, peaceful observance/devotion | Inca patronage/festivals and other four factions |
| Plague/unrest | Plague spread/progression and influence trimming; stability-based vulnerable-province revolts with withdrawal/losses | Pacification action and event table |
| Victory | Two consecutive qualifying round ends, elimination, six-round scoring and population/gold tiebreaks | Full 12-round, 24-province victory conditions |
| Simple AI | Either current faction can be automated; purchases, integration, military movement, tactical turns, income choices, pause, spectator mode, saved controller settings | Deep planning, construction/diplomacy strategy and the other four factions |
| Persistence | Save/load outside tactical battles, RNG state preserved, structural validation, temporary-file replacement | Mid-battle save and schema migrations |
| Full scenario | Rulebook preserved | Six factions, 24-province map, four sea zones; historical/art presentation |

The encounter resolver and terrain routines are model capabilities, not claims that all corresponding UI workflows exist. Automated choices remain explicit prototype limitations.
