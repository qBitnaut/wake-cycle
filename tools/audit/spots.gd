## Every required vertical climb and long jump of Rooms 1-4 and the test room, as
## human_sweep.gd spots (see there for the format). Coordinates are the builders'
## (tools/build_room*.gd): 32 px tiles, a column c starts at x = 32 c, a row r's
## surface is at y = 32 r. Each spot lists the intended move (>= 90% of the human
## sweep), the ways that must stay impossible (0%), and measured-only extras.
##
## A gap's landing box starts 10 px before the far lip: the cat stands on a lip with its
## centre up to half its width (11 px) short of the edge, and it drifts on while it drops
## to the floor, so the audited reach is a little more than reach.gd's crossing distance.
##
## Single jump heights (reach.gd): plain 95 px, plain double 171 px, Spring single
## 211 px, Spring double 287 px; the tallest a plain cat can do is 171 px = 5.3 tiles.
extends RefCounted

const T := 32.0

## Moves of a Spring climb: Spring's single jump is the intended move.
const SPRING_CLIMB := [[2, "single", true], [2, "patterns", true], [2, "double", true], [0, "single", false], [0, "double", false],
	[0, "patterns", false], [1, "single", false], [1, "double", false]]
## A climb out of a narrow pit: a single press is the intended move; a Spring double jump overshoots the
## pillar by geometry and lands in the sibling pit (which has a Spring pad of its own: never a trap), so
## the double jump and the patterns are measured, not asserted.
const SPRING_PIT := [[2, "single", true], [2, "patterns", null], [2, "double", null], [0, "single", false], [0, "double", false],
	[0, "patterns", false], [1, "single", false], [1, "double", false]]
## Moves nothing may manage (a skip that must not exist).
const NO_SKIP := [[0, "single", false], [0, "double", false], [1, "single", false], [1, "double", false],
	[2, "single", false], [2, "double", false], [2, "patterns", false]]
## A plain hop: the plain single jump.
const PLAIN_HOP := [[0, "single", true]]


static func for_room(room_id: String) -> Array:
	match room_id:
		"room1":
			return room1()
		"room2":
			return room2()
		"room3":
			return room3()
		"room4":
			return room4()
		"test_room":
			return test_room()
	return []


static func room1() -> Array:
	## Room 1 needs no power: the plain single jump must do every required hop. The key
	## deck (1, 2, 3 tiles of steps) is on the way to the brass door; the catwalk and the
	## crate stairs of beat B are a bonus route (the floor below is open), measured only.
	var g := 320.0
	return [
		# The one-tile crates are 32 px wide: a held direction overshoots them, so those two
		# steps are measured, not asserted (a player lets go).
		{"name": "R1 key deck step 1 (floor -> 1 tile)", "sx": 92.0 * T - 120.0, "sy": g, "d": 1.0, "edge": 93.0 * T, "kind": "wall",
			"tx0": 93.0 * T + 8.0, "tx1": 94.0 * T - 8.0, "ty": g - 32.0, "moves": [[0, "single", null]]},
		{"name": "R1 key deck step 2 (1 -> 2 tiles)", "sx": 93.0 * T + 16.0, "sy": g - 32.0, "d": 1.0, "edge": 94.0 * T, "kind": "wall",
			"tx0": 94.0 * T + 8.0, "tx1": 95.0 * T - 8.0, "ty": g - 64.0, "offsets": [12.0, 16.0, 20.0], "moves": [[0, "single", null]]},
		{"name": "R1 key deck step 3 (2 tiles -> the deck, 3 tiles)", "sx": 94.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 95.0 * T, "kind": "wall",
			"tx0": 95.0 * T + 8.0, "tx1": 99.0 * T, "ty": g - 96.0, "offsets": [12.0, 16.0, 20.0], "moves": PLAIN_HOP},
		{"name": "R1 bonus catwalk gap (3 tiles)", "sx": 22.0 * T, "sy": g - 96.0, "d": 1.0, "edge": 28.0 * T, "kind": "gap",
			"tx0": 31.0 * T - 10.0, "tx1": 35.0 * T, "ty": g - 96.0, "moves": [[0, "single", null]]},
		{"name": "R1 bonus letter T perch (3 tiles up from the crates)", "sx": 128.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 130.0 * T, "kind": "wall",
			"tx0": 130.0 * T + 8.0, "tx1": 132.0 * T - 8.0, "ty": g - 160.0, "offsets": [12.0, 16.0, 20.0, 24.0, 28.0, 32.0],
			"moves": [[0, "double", null]]},
	]


static func room2() -> Array:
	var g := 320.0
	return [
		{"name": "R2 Surge gap (9 tiles)", "sx": 2064.0, "sy": g, "d": 1.0, "edge": 70.0 * T, "kind": "gap",
			"tx0": 79.0 * T - 10.0, "tx1": 90.0 * T, "ty": g,
			"moves": [[1, "double", true], [0, "single", false], [0, "double", false], [1, "single", false], [2, "single", null], [2, "double", null]]},
		{"name": "R2 pit (5 tiles)", "sx": 165.0 * T + 20.0, "sy": g, "d": 1.0, "edge": 169.0 * T, "kind": "gap",
			"tx0": 174.0 * T - 10.0, "tx1": 190.0 * T, "ty": g,
			"moves": [[0, "double", true], [0, "single", false], [1, "single", null], [1, "double", null], [2, "single", null], [2, "double", null]]},
		{"name": "R2 crate steps (floor -> 1 tile -> 2 tiles)", "sx": 5000.0, "sy": g, "d": 1.0, "edge": 161.0 * T, "kind": "wall",
			"tx0": 161.0 * T + 8.0, "tx1": 165.0 * T - 8.0, "ty": g - 32.0, "moves": [[0, "single", null]]},
	]


static func room3() -> Array:
	## The Stacks (rows: yard 44, shed 38, ledge and pit floors 32, long roof and the corridor 26,
	## gallery 20, roof and bay 14, tower tops and the exit roof 8). Every wall here is 6 tiles.
	var G := 1408.0
	var R1 := 1216.0
	var R2 := 1024.0
	var R3 := 832.0
	var R5 := 448.0
	var R6 := 256.0
	return [
		{"name": "R3 H1 wall (shed, 6 tiles)", "sx": 980.0, "sy": G, "d": 1.0, "edge": 1088.0, "kind": "wall",
			"tx0": 1100.0, "tx1": 1700.0, "ty": R1, "moves": SPRING_CLIMB},
		{"name": "R3 H2 shed roof -> floating ledge (6 tiles)", "sx": 1312.0, "sy": R1, "d": 1.0, "edge": 1440.0, "kind": "wall",
			"tx0": 1450.0, "tx1": 1625.0, "ty": R2, "moves": SPRING_CLIMB},
		{"name": "R3 H3 ledge -> long roof (6 tiles, 1 across)", "sx": 1500.0, "sy": R2, "d": 1.0, "edge": 1696.0, "kind": "gap",
			"tx0": 1735.0, "tx1": 2100.0, "ty": R3, "moves": SPRING_CLIMB},
		{"name": "R3 P1 out of the first pit (6 tiles)", "sx": 2800.0, "sy": R2, "d": 1.0, "edge": 2976.0, "kind": "wall",
			"tx0": 2984.0, "tx1": 3240.0, "ty": R3, "moves": SPRING_CLIMB},
		{"name": "R3 P2 out of the second pit (6 tiles)", "sx": 3360.0, "sy": R2, "d": 1.0, "edge": 3520.0, "kind": "wall",
			"tx0": 3528.0, "tx1": 3700.0, "ty": R3, "moves": SPRING_CLIMB},
		{"name": "R3 V vent tower pillar (6 tiles)", "sx": 3120.0, "sy": R5, "d": 1.0, "edge": 3200.0, "kind": "wall",
			"tx0": 3208.0, "tx1": 3350.0, "ty": R6, "moves": SPRING_CLIMB,
			"alt": [[3280.0, 3370.0, 192.0], [3072.0, 3584.0, 132.0], [3360.0, 3456.0, 160.0], [3072.0, 3104.0, 160.0]]},   # a Spring double jump may reach the falling platform or the crane deck: a skilled shortcut, the climb is made
		{"name": "R3 X exit tower (6 tiles)", "sx": 4800.0, "sy": R5, "d": 1.0, "edge": 4864.0, "kind": "wall",
			"tx0": 4872.0, "tx1": 5000.0, "ty": R6, "moves": SPRING_CLIMB},
		{"name": "R3 XP out of the exit pit (6 tiles)", "sx": 5160.0, "sy": R5, "d": 1.0, "edge": 5280.0, "kind": "wall",
			"tx0": 5288.0, "tx1": 5500.0, "ty": R6, "moves": SPRING_CLIMB},
		{"name": "R3 U1 undercroft: west pit -> pillar (6 tiles)", "sx": 4296.0, "sy": 1216.0, "d": 1.0, "edge": 4352.0, "kind": "wall",
			"tx0": 4360.0, "tx1": 4470.0, "ty": R2, "offsets": [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0], "moves": SPRING_PIT, "alt": [[4480.0, 4544.0, 1216.0]]},
		{"name": "R3 U2 undercroft: east pit -> pillar (6 tiles)", "sx": 4536.0, "sy": 1216.0, "d": -1.0, "edge": 4480.0, "kind": "wall",
			"tx0": 4362.0, "tx1": 4472.0, "ty": R2, "offsets": [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0], "moves": SPRING_PIT, "alt": [[4288.0, 4352.0, 1216.0]]},
		{"name": "R3 U3 undercroft: pillar -> far landing (6 up, 2 across)", "sx": 4400.0, "sy": R2, "d": 1.0, "edge": 4480.0, "kind": "gap",
			"tx0": 4544.0, "tx1": 4600.0, "ty": R3, "moves": SPRING_CLIMB},
		{"name": "R3 U4 undercroft: pillar -> corridor (6 up, 2 across)", "sx": 4440.0, "sy": R2, "d": -1.0, "edge": 4352.0, "kind": "gap",
			"tx0": 4150.0, "tx1": 4278.0, "ty": R3, "moves": SPRING_CLIMB},
		{"name": "R3 pump house hop (2 tiles)", "sx": 2300.0, "sy": R5, "d": 1.0, "edge": 2432.0, "kind": "wall",
			"tx0": 2440.0, "tx1": 2650.0, "ty": R5 - 64.0, "moves": PLAIN_HOP},
		{"name": "R3 ladder 1 (gallery floor -> girder, 2 tiles)", "sx": 2262.0, "sy": R3 - 192.0, "d": -1.0, "edge": 2208.0, "kind": "gap",
			"tx0": 2146.0, "tx1": 2200.0, "ty": R3 - 252.0, "moves": PLAIN_HOP},
		{"name": "R3 ladder 2 (girder -> girder, 2 tiles)", "sx": 2150.0, "sy": R3 - 252.0, "d": 1.0, "edge": 2208.0, "kind": "gap",
			"tx0": 2200.0, "tx1": 2270.0, "ty": R3 - 316.0, "moves": PLAIN_HOP},
		{"name": "R3 ladder 3 (girder -> the roof, 2 tiles)", "sx": 2216.0, "sy": R3 - 316.0, "d": 1.0, "edge": 2272.0, "kind": "wall",
			"tx0": 2280.0, "tx1": 2400.0, "ty": R5, "moves": PLAIN_HOP},
		{"name": "R3 skip: shed -> long roof direct", "sx": 1650.0, "sy": R1, "d": 1.0, "edge": 1728.0, "kind": "wall",
			"tx0": 1735.0, "tx1": 2100.0, "ty": R3, "moves": NO_SKIP},
		{"name": "R3 skip: long roof -> the roof (past the conduit)", "sx": 2040.0, "sy": R3, "d": 1.0, "edge": 2112.0, "kind": "wall",
			"tx0": 2112.0, "tx1": 3000.0, "ty": R5, "moves": NO_SKIP},
	]


static func room4() -> Array:
	var g := 320.0
	return [
		{"name": "R4 P3 guardhouse roof (6 rows)", "sx": 115.0 * T + 20.0, "sy": g, "d": 1.0, "edge": 118.0 * T, "kind": "wall",
			"tx0": 118.0 * T + 10.0, "tx1": 130.0 * T, "ty": 128.0, "moves": SPRING_CLIMB},
		{"name": "R4 Relay 1 tower (6 rows)", "sx": 220.0 * T + 20.0, "sy": g, "d": 1.0, "edge": 222.0 * T, "kind": "wall",
			"tx0": 222.0 * T + 10.0, "tx1": 229.0 * T, "ty": 128.0, "moves": SPRING_CLIMB},
		{"name": "R4 Impact ledge (2 tiles up)", "sx": 139.0 * T - 60.0, "sy": g, "d": 1.0, "edge": 141.0 * T, "kind": "wall",
			"tx0": 141.0 * T + 8.0, "tx1": 146.0 * T - 8.0, "ty": 8.0 * T, "moves": PLAIN_HOP},
		{"name": "R4 trench stair (2 tiles up)", "sx": 196.0 * T + 8.0, "sy": 19.0 * T, "d": 1.0, "edge": 198.0 * T, "kind": "wall",
			"tx0": 198.0 * T + 8.0, "tx1": 199.0 * T + 24.0, "ty": 17.0 * T, "offsets": [12.0, 18.0, 24.0, 30.0, 36.0, 42.0],
			"moves": PLAIN_HOP},
		{"name": "R4 vault stair, riser 1 (floor -> tread 1, 1 tile)", "sx": 313.0 * T - 120.0, "sy": 14.0 * T, "d": 1.0, "edge": 313.0 * T, "kind": "wall",
			"tx0": 313.0 * T + 8.0, "tx1": 315.0 * T - 8.0, "ty": 13.0 * T, "moves": PLAIN_HOP},
		{"name": "R4 vault stair, riser 2 (tread 1 -> tread 2, 1 tile)", "sx": 313.0 * T + 16.0, "sy": 13.0 * T, "d": 1.0, "edge": 315.0 * T, "kind": "wall",
			"tx0": 315.0 * T + 8.0, "tx1": 317.0 * T - 8.0, "ty": 12.0 * T, "offsets": [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0],
			"moves": PLAIN_HOP},
		{"name": "R4 vault stair, riser 3 (tread 2 -> the surface, 2 tiles)", "sx": 315.0 * T + 16.0, "sy": 12.0 * T, "d": 1.0, "edge": 317.0 * T, "kind": "wall",
			"tx0": 317.0 * T + 8.0, "tx1": 330.0 * T, "ty": g, "offsets": [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0],
			"moves": PLAIN_HOP},
	]


static func test_room() -> Array:
	var g := 320.0
	return [
		{"name": "TEST pit A (5 tiles, double jump)", "sx": 17.0 * T - 200.0, "sy": g, "d": 1.0, "edge": 17.0 * T, "kind": "gap",
			"tx0": 22.0 * T - 10.0, "tx1": 28.0 * T, "ty": g,
			"moves": [[0, "double", true], [1, "single", null], [0, "single", false]]},
		{"name": "TEST wide pit C (8 tiles, Surge)", "sx": 41.0 * T - 200.0, "sy": g, "d": 1.0, "edge": 41.0 * T, "kind": "gap",
			"tx0": 49.0 * T - 10.0, "tx1": 54.0 * T, "ty": g,
			"moves": [[1, "double", true], [0, "single", false], [0, "double", false], [1, "single", false],
				[2, "double", null]]},   # the Spring pad (col 52) is beyond this pit: nothing to skip
		{"name": "TEST tall wall D (6 tiles, Spring)", "sx": 55.0 * T - 200.0, "sy": g, "d": 1.0, "edge": 55.0 * T, "kind": "wall",
			"tx0": 55.0 * T + 10.0, "tx1": 58.0 * T, "ty": g - 6.0 * T, "moves": SPRING_CLIMB},
	]
