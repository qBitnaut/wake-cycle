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
	## Room 1 (the tall warehouse) needs no power: the plain single jump does every required hop
	## (rises of 1-2 tiles, gaps of at most 3). Required: the rack steps up to the mezzanine, the
	## mezzanine hole, the service-deck steps, the roof girder gap. Optional but fair: the crate
	## steps, the electric-floor bypass, the machine corridor's crate steps.
	var g := 768.0
	var m := 512.0
	var r := 256.0
	var b := 1056.0
	return [
		{"name": "R1 crate 1 (floor -> 1 tile)", "sx": 13.0 * T - 120.0, "sy": g, "d": 1.0, "edge": 13.0 * T, "kind": "wall",
			"tx0": 13.0 * T + 8.0, "tx1": 14.0 * T - 8.0, "ty": g - 32.0, "moves": [[0, "single", null]]},
		{"name": "R1 crate 2 (crate 1 -> 2 tiles)", "sx": 13.0 * T + 16.0, "sy": g - 32.0, "d": 1.0, "edge": 14.0 * T, "kind": "gap",
			"tx0": 15.0 * T - 10.0, "tx1": 17.0 * T, "ty": g - 64.0, "moves": [[0, "single", null]]},
		{"name": "R1 deck over the bot (crate 2 -> the deck, 3 tiles)", "sx": 15.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 17.0 * T, "kind": "wall",
			"tx0": 17.0 * T + 8.0, "tx1": 27.0 * T, "ty": g - 96.0, "offsets": [12.0, 16.0, 20.0], "moves": PLAIN_HOP},
		{"name": "R1 rack step 1 (floor -> 2 tiles)", "sx": 44.0 * T - 120.0, "sy": g, "d": 1.0, "edge": 44.0 * T, "kind": "wall",
			"tx0": 44.0 * T + 8.0, "tx1": 47.0 * T - 8.0, "ty": g - 64.0, "moves": PLAIN_HOP},
		{"name": "R1 rack step 2 (step 1 -> step 2)", "sx": 44.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 47.0 * T, "kind": "gap",
			"tx0": 48.0 * T - 10.0, "tx1": 51.0 * T, "ty": g - 128.0, "moves": PLAIN_HOP},
		{"name": "R1 rack step 3 (step 2 -> step 3)", "sx": 48.0 * T + 16.0, "sy": g - 128.0, "d": 1.0, "edge": 51.0 * T, "kind": "gap",
			"tx0": 52.0 * T - 10.0, "tx1": 55.0 * T, "ty": g - 192.0, "moves": PLAIN_HOP},
		{"name": "R1 rack top -> the mezzanine", "sx": 52.0 * T + 16.0, "sy": g - 192.0, "d": 1.0, "edge": 55.0 * T, "kind": "gap",
			"tx0": 55.0 * T - 10.0, "tx1": 58.0 * T, "ty": m, "moves": PLAIN_HOP},
		{"name": "R1 mezzanine hole (3 tiles, walked west)", "sx": 47.0 * T, "sy": m, "d": -1.0, "edge": 44.0 * T, "kind": "gap",
			"tx0": 30.0 * T, "tx1": 41.0 * T + 10.0, "ty": m, "moves": PLAIN_HOP},
		{"name": "R1 service deck step (deck -> the rack of steps)", "sx": 29.0 * T + 4.0, "sy": m + 128.0, "d": 1.0, "edge": 30.0 * T, "kind": "wall",
			"tx0": 30.0 * T + 8.0, "tx1": 33.0 * T - 8.0, "ty": m + 64.0, "offsets": [12.0, 16.0, 20.0], "moves": PLAIN_HOP},
		{"name": "R1 roof girder gap (3 tiles)", "sx": 30.0 * T, "sy": r, "d": 1.0, "edge": 34.0 * T, "kind": "gap",
			"tx0": 37.0 * T - 10.0, "tx1": 44.0 * T, "ty": r, "moves": PLAIN_HOP},
		{"name": "R1 office ledge without a barrel (4 tiles up)", "sx": 2672.0, "sy": r, "d": 1.0, "edge": 86.0 * T, "kind": "wall",
			"tx0": 86.0 * T + 8.0, "tx1": 91.0 * T - 8.0, "ty": 4.0 * T + 4.0, "moves": [[0, "single", false], [0, "double", null]]},
		{"name": "R1 office escape step 1 (floor -> 2 tiles)", "sx": 108.0 * T - 120.0, "sy": 544.0, "d": 1.0, "edge": 108.0 * T, "kind": "wall",
			"tx0": 108.0 * T + 8.0, "tx1": 111.0 * T - 8.0, "ty": 15.0 * T + 4.0, "moves": PLAIN_HOP},
		{"name": "R1 office escape step 2 (west, gap 1)", "sx": 108.0 * T + 16.0, "sy": 15.0 * T + 4.0, "d": -1.0, "edge": 108.0 * T, "kind": "gap",
			"tx0": 104.0 * T, "tx1": 107.0 * T + 10.0, "ty": 13.0 * T + 4.0, "moves": PLAIN_HOP},
		{"name": "R1 office escape step 3 (east, gap 1)", "sx": 104.0 * T + 16.0, "sy": 13.0 * T + 4.0, "d": 1.0, "edge": 107.0 * T, "kind": "gap",
			"tx0": 108.0 * T - 10.0, "tx1": 111.0 * T, "ty": 11.0 * T + 4.0, "moves": PLAIN_HOP},
		{"name": "R1 office escape step 4 (west, gap 1)", "sx": 108.0 * T + 16.0, "sy": 11.0 * T + 4.0, "d": -1.0, "edge": 108.0 * T, "kind": "gap",
			"tx0": 104.0 * T, "tx1": 107.0 * T + 10.0, "ty": 9.0 * T + 4.0, "moves": PLAIN_HOP},
		{"name": "R1 office escape step 5 (up onto the deck)", "sx": 104.0 * T + 16.0, "sy": 9.0 * T + 4.0, "d": -1.0, "edge": 104.0 * T, "kind": "gap",
			"tx0": 96.0 * T, "tx1": 102.0 * T + 10.0, "ty": 8.0 * T + 4.0, "moves": PLAIN_HOP},
		{"name": "R1 drain deck (floor -> 2 tiles)", "sx": 70.0 * T - 120.0, "sy": b, "d": 1.0, "edge": 70.0 * T, "kind": "wall",
			"tx0": 70.0 * T + 8.0, "tx1": 74.0 * T - 8.0, "ty": b - 64.0, "moves": PLAIN_HOP},
		{"name": "R1 electric-floor bypass deck (floor -> 2 tiles)", "sx": 87.0 * T - 120.0, "sy": b, "d": 1.0, "edge": 87.0 * T, "kind": "wall",
			"tx0": 87.0 * T + 8.0, "tx1": 92.0 * T - 8.0, "ty": b - 64.0, "moves": PLAIN_HOP},
		{"name": "R1 machine corridor crate step (crate 2 -> the deck)", "sx": 84.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 85.0 * T, "kind": "wall",
			"tx0": 85.0 * T + 8.0, "tx1": 93.0 * T, "ty": g - 96.0, "offsets": [12.0, 16.0, 20.0], "moves": PLAIN_HOP},
	]


static func room2() -> Array:
	## Rows (surface y): yard floor 768, underpass floor 1024, vault floor 1152, roofs 512. A
	## tread is 3 tiles (96 px): a held-direction hop of 64 px lands 28..82 px past the face.
	var g := 320.0 + 448.0
	var u := 1024.0
	var out := [
		{"name": "R2 Surge gap (9 tiles)", "sx": 2064.0, "sy": g, "d": 1.0, "edge": 70.0 * T, "kind": "gap",
			"tx0": 79.0 * T - 10.0, "tx1": 90.0 * T, "ty": g,
			"moves": [[1, "double", true], [0, "single", false], [0, "double", false], [1, "single", false], [2, "single", null], [2, "double", null]]},
		{"name": "R2 pit (5 tiles)", "sx": 177.0 * T + 8.0, "sy": g, "d": 1.0, "edge": 180.0 * T, "kind": "gap",
			"tx0": 185.0 * T - 10.0, "tx1": 191.0 * T, "ty": g,
			"moves": [[0, "double", true], [0, "single", false], [1, "single", null], [1, "double", null], [2, "single", null], [2, "double", null]]},
		{"name": "R2 crate steps 1 (floor -> 1 tile)", "sx": 5300.0, "sy": g, "d": 1.0, "edge": 172.0 * T, "kind": "wall",
			"tx0": 172.0 * T + 8.0, "tx1": 174.0 * T - 8.0, "ty": g - 32.0, "moves": [[0, "single", null]]},
		{"name": "R2 crate steps 2 (1 tile -> 2 tiles)", "sx": 172.0 * T + 16.0, "sy": g - 32.0, "d": 1.0, "edge": 174.0 * T, "kind": "wall",
			"tx0": 174.0 * T + 8.0, "tx1": 177.0 * T - 8.0, "ty": g - 64.0, "moves": PLAIN_HOP},
		# --- the high route ---
		{"name": "R2 roof stair 1 (floor -> girder, 2 tiles)", "sx": 84.0 * T - 80.0, "sy": g, "d": 1.0, "edge": 84.0 * T, "kind": "wall",
			"tx0": 84.0 * T + 8.0, "tx1": 87.0 * T - 8.0, "ty": g - 64.0, "moves": PLAIN_HOP},
		{"name": "R2 roof stair 2 (girder -> girder, 2 tiles)", "sx": 84.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 87.0 * T, "kind": "wall",
			"tx0": 87.0 * T + 8.0, "tx1": 90.0 * T - 8.0, "ty": g - 128.0, "moves": PLAIN_HOP},
		{"name": "R2 roof stair 3 (girder -> girder, 2 tiles)", "sx": 87.0 * T + 16.0, "sy": g - 128.0, "d": 1.0, "edge": 90.0 * T, "kind": "wall",
			"tx0": 90.0 * T + 8.0, "tx1": 93.0 * T - 8.0, "ty": g - 192.0, "moves": PLAIN_HOP},
		{"name": "R2 roof step (girder -> first roof, 2 tiles)", "sx": 90.0 * T + 16.0, "sy": g - 192.0, "d": 1.0, "edge": 93.0 * T, "kind": "wall",
			"tx0": 93.0 * T + 8.0, "tx1": 101.0 * T, "ty": g - 256.0, "moves": PLAIN_HOP},
		{"name": "R2 roof gap 1 (5 tiles, Surge run or a double jump)", "sx": 98.0 * T + 8.0, "sy": g - 256.0, "d": 1.0, "edge": 102.0 * T, "kind": "gap",
			"tx0": 107.0 * T - 10.0, "tx1": 114.0 * T, "ty": g - 256.0,
			"moves": [[0, "double", true], [1, "single", true], [0, "single", false]]},
		{"name": "R2 roof gap 2 (5 tiles: the hanging bridge fills it, a landing on it counts)", "sx": 108.0 * T, "sy": g - 256.0, "d": 1.0, "edge": 115.0 * T, "kind": "gap",
			"tx0": 115.0 * T + 4.0, "tx1": 126.0 * T, "ty": g - 256.0,
			"moves": [[0, "double", true], [1, "single", true], [0, "single", null]]},
		{"name": "R2 crane stair 1 (roof -> girder, 2 tiles)", "sx": 122.0 * T, "sy": g - 256.0, "d": 1.0, "edge": 127.0 * T, "kind": "wall",
			"tx0": 127.0 * T + 8.0, "tx1": 130.0 * T - 8.0, "ty": g - 320.0, "moves": PLAIN_HOP},
		{"name": "R2 crane stair 2 (girder -> girder, 2 tiles, leftwards)", "sx": 129.0 * T - 8.0, "sy": g - 320.0, "d": -1.0, "edge": 127.0 * T, "kind": "wall",
			"tx0": 124.0 * T + 8.0, "tx1": 127.0 * T - 8.0, "ty": g - 384.0, "moves": PLAIN_HOP},
		{"name": "R2 crane stair 3 (girder -> girder, 2 tiles)", "sx": 124.0 * T + 16.0, "sy": g - 384.0, "d": 1.0, "edge": 127.0 * T, "kind": "wall",
			"tx0": 127.0 * T + 8.0, "tx1": 130.0 * T - 8.0, "ty": g - 448.0, "moves": PLAIN_HOP},
		{"name": "R2 crane cab (girder -> cab floor, 2 tiles)", "sx": 127.0 * T + 16.0, "sy": g - 448.0, "d": 1.0, "edge": 130.0 * T, "kind": "wall",
			"tx0": 130.0 * T + 8.0, "tx1": 134.0 * T, "ty": g - 512.0, "moves": PLAIN_HOP},
		{"name": "R2 dock detour 1 (floor -> girder, 2 tiles)", "sx": 141.0 * T + 20.0, "sy": g, "d": 1.0, "edge": 143.0 * T, "kind": "wall",
			"tx0": 143.0 * T + 8.0, "tx1": 146.0 * T - 8.0, "ty": g - 64.0, "moves": [[0, "single", null]]},
		{"name": "R2 dock detour 2 (girder -> girder, 2 tiles)", "sx": 143.0 * T + 16.0, "sy": g - 64.0, "d": 1.0, "edge": 146.0 * T, "kind": "wall",
			"tx0": 146.0 * T + 8.0, "tx1": 149.0 * T - 8.0, "ty": g - 128.0, "moves": PLAIN_HOP},
		{"name": "R2 dock detour 3 (girder -> canopy roof, 2 tiles)", "sx": 146.0 * T + 16.0, "sy": g - 128.0, "d": 1.0, "edge": 149.0 * T, "kind": "wall",
			"tx0": 149.0 * T + 8.0, "tx1": 154.0 * T, "ty": g - 192.0, "moves": PLAIN_HOP},
		# --- the underpass: the vault (S3), the crawl cache (S1) ---
		{"name": "R2 vault stair 1 (floor -> girder, 1 tile)", "sx": 1500.0, "sy": 1152.0, "d": 1.0, "edge": 49.0 * T, "kind": "wall",
			"tx0": 49.0 * T - 4.0, "tx1": 54.0 * T - 8.0, "ty": 1120.0, "moves": PLAIN_HOP},
		{"name": "R2 vault stair 2 (girder -> girder, 2 tiles)", "sx": 49.0 * T + 16.0, "sy": 1120.0, "d": 1.0, "edge": 51.0 * T, "kind": "wall",
			"tx0": 51.0 * T + 8.0, "tx1": 54.0 * T - 8.0, "ty": 1056.0, "moves": PLAIN_HOP},
		{"name": "R2 vault exit (girder -> the floor, 1 tile)", "sx": 51.0 * T + 16.0, "sy": 1056.0, "d": 1.0, "edge": 54.0 * T, "kind": "wall",
			"tx0": 54.0 * T + 8.0, "tx1": 58.0 * T, "ty": u, "moves": PLAIN_HOP},
		{"name": "R2 crawl cache exit (dip -> the floor, 2 tiles)", "sx": 99.0 * T + 8.0, "sy": 1088.0, "d": -1.0, "edge": 98.0 * T, "kind": "wall",
			"tx0": 94.0 * T, "tx1": 98.0 * T - 8.0, "ty": u, "moves": PLAIN_HOP},
	]
	# The three grate shafts (zigzag rungs, 2 tiles apart, then the flush grate in the yard floor).
	var names := ["west", "dock", "pit"]
	var k := 0
	for c in [83.0, 128.0, 186.0]:
		var n: String = names[k]
		k += 1
		out.append({"name": "R2 %s shaft 1 (floor -> rung, 2 tiles)" % n, "sx": c * T - 90.0, "sy": u, "d": 1.0, "edge": c * T, "kind": "wall",
			"tx0": c * T + 8.0, "tx1": (c + 3.0) * T - 8.0, "ty": u - 64.0, "moves": PLAIN_HOP})
		out.append({"name": "R2 %s shaft 2 (rung -> rung, 2 tiles)" % n, "sx": c * T + 16.0, "sy": u - 64.0, "d": 1.0, "edge": (c + 2.0) * T, "kind": "wall",
			"tx0": (c + 2.0) * T + 8.0, "tx1": (c + 5.0) * T - 8.0, "ty": u - 128.0, "moves": PLAIN_HOP})
		out.append({"name": "R2 %s shaft 3 (rung -> rung, 2 tiles, leftwards)" % n, "sx": (c + 5.0) * T - 16.0, "sy": u - 128.0, "d": -1.0, "edge": (c + 3.0) * T, "kind": "wall",
			"tx0": c * T + 8.0, "tx1": (c + 3.0) * T - 8.0, "ty": u - 192.0, "moves": PLAIN_HOP})
		out.append({"name": "R2 %s shaft 4 (rung -> the grate, 2 tiles)" % n, "sx": c * T + 16.0, "sy": u - 192.0, "d": 1.0, "edge": (c + 3.0) * T, "kind": "wall",
			"tx0": c * T + 8.0, "tx1": (c + 6.0) * T - 8.0, "ty": g, "moves": PLAIN_HOP})
	return out


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
	## Coordinates are tools/build_room4.gd's: the surface is row 12 (y = 384); the floors of L1..L4 are
	## rows 17, 22, 27, 35. Every required step is a plain hop of 2 rows at most; the Spring climbs and the
	## double-jump gap are the intended exceptions.
	var g := 384.0
	var tread := [12.0, 18.0, 24.0, 30.0, 36.0, 42.0, 48.0, 54.0]
	var out := [
		{"name": "R4 P3 guardhouse roof (6 rows)", "sx": 115.0 * T + 20.0, "sy": g, "d": 1.0, "edge": 118.0 * T, "kind": "wall",
			"tx0": 118.0 * T + 10.0, "tx1": 130.0 * T, "ty": 6.0 * T, "moves": SPRING_CLIMB},
		{"name": "R4 catwalk gap (5 tiles, west from the roof)", "sx": 121.0 * T, "sy": 6.0 * T, "d": -1.0, "edge": 118.0 * T, "kind": "gap",
			"tx0": 100.0 * T, "tx1": 113.0 * T + 10.0, "ty": 6.0 * T,
			"moves": [[0, "double", true], [0, "single", false], [1, "single", null], [1, "double", null]]},
		{"name": "R4 Impact ledge (2 tiles up)", "sx": 139.0 * T - 60.0, "sy": g, "d": 1.0, "edge": 141.0 * T, "kind": "wall",
			"tx0": 141.0 * T + 8.0, "tx1": 146.0 * T - 8.0, "ty": 10.0 * T, "moves": PLAIN_HOP},
		{"name": "R4 Relay 1 tower (6 rows, from the second girder)", "sx": 260.0 * T - 4.0, "sy": 8.0 * T, "d": -1.0, "edge": 258.0 * T, "kind": "wall",
			"tx0": 249.0 * T + 8.0, "tx1": 265.0 * T - 8.0, "ty": 2.0 * T, "moves": SPRING_CLIMB},
		{"name": "R4 cistern: hall -> first stone (2 tiles, 1 up)", "sx": 201.0 * T, "sy": 35.0 * T, "d": 1.0, "edge": 205.0 * T, "kind": "gap",
			"tx0": 206.0 * T - 10.0, "tx1": 211.0 * T, "ty": 34.0 * T, "moves": [[0, "single", true]]},
		{"name": "R4 cistern: stone -> stone over acid (2 tiles)", "sx": 206.0 * T + 8.0, "sy": 34.0 * T, "d": 1.0, "edge": 211.0 * T, "kind": "gap",
			"tx0": 213.0 * T - 10.0, "tx1": 217.0 * T, "ty": 34.0 * T, "moves": [[0, "single", true]]},
	]
	# The shaft's ladder: the floor (27) -> girders at rows 25 (right), 23 (left), 21, 19, 17, 15, 13 -> the surface.
	out.append({"name": "R4 ladder 0 (floor -> row 25)", "sx": 226.0 * T, "sy": 27.0 * T, "d": 1.0, "edge": 229.0 * T, "kind": "wall",
		"tx0": 229.0 * T + 8.0, "tx1": 234.0 * T - 8.0, "ty": 25.0 * T, "offsets": tread, "moves": PLAIN_HOP})
	var rows := [25, 23, 21, 19, 17, 15, 13]
	for i in range(1, rows.size()):
		var right: bool = i % 2 == 0     # the target girder is on the right (cols 229-233)
		var from_row: int = rows[i - 1]
		var to_row: int = rows[i]
		if right:
			out.append({"name": "R4 ladder %d (row %d -> %d)" % [i, from_row, to_row], "sx": 227.0 * T + 16.0, "sy": from_row * T, "d": 1.0,
				"edge": 229.0 * T, "kind": "wall", "tx0": 229.0 * T + 8.0, "tx1": (238.0 if to_row == 13 else 234.0) * T - 8.0, "ty": to_row * T, "offsets": tread, "moves": PLAIN_HOP})
		else:
			out.append({"name": "R4 ladder %d (row %d -> %d)" % [i, from_row, to_row], "sx": 231.0 * T + 16.0, "sy": from_row * T, "d": -1.0,
				"edge": 229.0 * T, "kind": "wall", "tx0": 224.0 * T + 8.0, "tx1": 229.0 * T - 8.0, "ty": to_row * T, "offsets": tread, "moves": PLAIN_HOP})
	out.append({"name": "R4 ladder top (row 13 -> the plaza)", "sx": 235.0 * T, "sy": 13.0 * T, "d": 1.0, "edge": 238.0 * T, "kind": "wall",
		"tx0": 238.0 * T + 8.0, "tx1": 244.0 * T, "ty": g, "offsets": tread, "moves": PLAIN_HOP})
	# The vault's stair (floor row 18, treads at rows 17, 16, 15, 14, the surface) and the armoury's (floor 17, treads 16, 15, 14).
	var stair := [["vault", 300.0, 18, 302, [17, 16, 15, 14]], ["armoury", 326.0, 17, 328, [16, 15, 14]]]
	for st in stair:
		var x0: float = st[1] * T
		var edge: float = float(st[3]) * T
		var prev_row: int = st[2]
		var k := 0
		for tr in st[4]:
			if k < st[4].size() - 1:
				prev_row = tr
				edge += 2.0 * T
				k += 1
				continue
			out.append({"name": "R4 %s stair tread %d (row %d -> %d)" % [st[0], k + 1, prev_row, tr], "sx": x0 if k == 0 else edge - 16.0, "sy": prev_row * T,
				"d": 1.0, "edge": edge, "kind": "wall", "tx0": edge + 8.0, "tx1": edge + 2.0 * T - 8.0, "ty": tr * T, "offsets": tread if k > 0 else null,
				"moves": PLAIN_HOP})
			prev_row = tr
			edge += 2.0 * T
			k += 1
		out.append({"name": "R4 %s stair out (row %d -> the surface)" % [st[0], prev_row], "sx": edge - 16.0, "sy": prev_row * T, "d": 1.0, "edge": edge,
			"kind": "wall", "tx0": edge + 8.0, "tx1": edge + 6.0 * T, "ty": g, "offsets": tread, "moves": PLAIN_HOP})
	for sp in out:
		if sp.has("offsets") and sp["offsets"] == null:
			sp.erase("offsets")
	return out


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
