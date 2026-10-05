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
const SPRING_CLIMB := [[2, "single", true], [2, "double", null], [0, "single", false], [0, "double", false],
	[1, "single", false], [1, "double", false]]
## Moves nothing may manage (a skip that must not exist).
const NO_SKIP := [[0, "single", false], [0, "double", false], [1, "single", false], [1, "double", false],
	[2, "single", false], [2, "double", false]]
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
	var G := 1152.0
	var S1 := 960.0
	var S2 := 768.0
	var S3 := 576.0
	var S4 := 384.0
	var gallery_roof := 192.0
	return [
		{"name": "R3 H1 wall (shed, 6 tiles)", "sx": 980.0, "sy": G, "d": 1.0, "edge": 1088.0, "kind": "wall",
			"tx0": 1100.0, "tx1": 1700.0, "ty": S1, "moves": SPRING_CLIMB},
		{"name": "R3 H2 shed roof -> floating ledge (6 tiles)", "sx": 1312.0, "sy": S1, "d": 1.0, "edge": 1440.0, "kind": "wall",
			"tx0": 1450.0, "tx1": 1625.0, "ty": S2, "moves": SPRING_CLIMB},
		{"name": "R3 H3 ledge -> long roof (6 tiles, 1 across)", "sx": 1500.0, "sy": S2, "d": 1.0, "edge": 1696.0, "kind": "gap",
			"tx0": 1735.0, "tx1": 2100.0, "ty": S3, "moves": SPRING_CLIMB},
		{"name": "R3 H4 the combine tower (6 tiles)", "sx": 4250.0, "sy": S3, "d": 1.0, "edge": 4416.0, "kind": "wall",
			"tx0": 4430.0, "tx1": 4660.0, "ty": S4, "moves": SPRING_CLIMB},
		{"name": "R3 H5 nine-tile gap", "sx": 4528.0, "sy": S4, "d": 1.0, "edge": 4672.0, "kind": "gap",
			"tx0": 4960.0 - 10.0, "tx1": 5400.0, "ty": S4,
			"moves": [[1, "double", true], [0, "single", false], [0, "double", false], [1, "single", false], [2, "single", false], [2, "double", false]]},
		{"name": "R3 skip: shed -> long roof direct", "sx": 1650.0, "sy": S1, "d": 1.0, "edge": 1728.0, "kind": "wall",
			"tx0": 1735.0, "tx1": 2100.0, "ty": S3, "moves": NO_SKIP},
		{"name": "R3 skip: long roof -> gallery roof", "sx": 1950.0, "sy": S3, "d": 1.0, "edge": 2112.0, "kind": "wall",
			"tx0": 2130.0, "tx1": 2900.0, "ty": gallery_roof, "moves": NO_SKIP},
		{"name": "R3 skip: pit floor -> far tower", "sx": 4850.0, "sy": 704.0, "d": 1.0, "edge": 4960.0, "kind": "wall",
			"tx0": 4968.0, "tx1": 5200.0, "ty": S4, "moves": NO_SKIP},
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
			"moves": [[1, "double", true], [0, "single", false], [0, "double", false], [1, "single", false]]},
		{"name": "TEST tall wall D (6 tiles, Spring)", "sx": 55.0 * T - 200.0, "sy": g, "d": 1.0, "edge": 55.0 * T, "kind": "wall",
			"tx0": 55.0 * T + 10.0, "tx1": 58.0 * T, "ty": g - 6.0 * T, "moves": SPRING_CLIMB},
	]
