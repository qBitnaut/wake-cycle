"""The SFX and ambience wanted, as (name, prompt, seconds, loop). Cinematic, tactile, modern."""
CLOSE = ", close-mic, cinematic foley, clean, no music"
SFX = []


def add(name, prompt, sec, loop=False, infl=0.6):
    SFX.append(dict(name=name, prompt=prompt + CLOSE, sec=sec, loop=loop, infl=infl))


for i in range(1, 4):
    add("step_metal_%d" % i, "a single soft footstep of a small cat paw on a metal grate floor, light tick and ring", 0.5)
    add("step_concrete_%d" % i, "a single soft footstep of a small cat paw on dry concrete, light pad and scuff", 0.5)
    add("step_wet_%d" % i, "a single soft footstep of a small cat paw in a shallow wet puddle on a ground, a small splat", 0.5)
    add("step_wood_%d" % i, "a single soft footstep of a small cat paw on a hollow wooden floor, light creak and thud", 0.5)
add("jump", "a small cat jumping upward, a quick muscular push-off and cloth-light whoosh", 0.6)
add("double_jump", "a cat's mid-air second jump, a crisp airy flick with a faint blue-energy shimmer", 0.7)
add("land", "a small cat landing softly on a hard floor, a paw thump", 0.5)
add("land_hard", "a cat landing hard from a height on concrete, a solid thud and a rattle", 0.6)
add("crawl", "a small cat crawling low on a metal floor, soft slinking fabric and paws", 0.8)
add("spring_boost", "a springy energy boost, a coil release with a rising elastic twang and green energy pop", 0.9)
add("surge_whoosh", "a fast electric surge whoosh, a blue energy burst rushing past with crackle", 1.2)
add("surge_loop", "a continuous electric blue energy rush, a humming fast crackling wind loop", 3.0, loop=True)
add("phase_dash", "a phasing ghostly dash, a short glassy whoosh with a purple energy warp", 0.8)
add("impact_pound", "a heavy ground pound slam, a deep boom with debris rattling and a low sub thump", 1.2)
add("shockwave_burst", "a radial shockwave burst, an expanding pressure boom with an energy ripple", 1.5)
add("hurt", "a small startled cat yelp, short and sharp, not cartoonish", 0.7)
# The cat before its mind wakes: only vocalisations (Monologue plays one instead of a line).
CAT = " Natural house cat, close and warm, realistic, not cartoonish, no music."
for n, t, sec in [
    ("meow_curious", "a single short curious meow of a small house cat, soft and slightly rising", 1.0),
    ("meow_mrrp", "a questioning 'mrrp?' of a house cat, a short rising chirpy murmur", 0.8),
    ("meow_trill", "a soft trill and chirp of a house cat, a gentle rolling purr-chirp", 1.0),
    ("meow_uneasy", "an uneasy low meow of a house cat, a slow worried falling 'meow', subdued", 1.3),
    ("meow_mew", "a small determined 'mew' of a house cat, short, firm and clear", 0.7),
]:
    SFX.append(dict(name=n, prompt=t + "." + CAT, sec=sec, loop=False, infl=0.6))
add("pickup_small", "a small collectible pickup, a soft bright glassy chime", 0.8)
add("pickup_big", "a bigger collectible pickup, a warm layered chime rising", 1.0)
add("pickup_rare", "a rare precious pickup, a magical shimmering chime with a tail", 1.5)
add("pickup_letter", "a golden letter collected, a gentle sparkling bell and warm swell", 1.5)
add("pickup_fish", "a health pickup, a warm soft restorative chime with a gentle blip", 1.0)
add("power_up", "a futuristic nano power-up, a rising energy hum resolving into a clean tone", 1.2)
add("pad_surge", "a blue energy pad activating, a rapid electric charge-up and zap", 1.0)
add("pad_spring", "a green energy pad activating, a bouncy coiled-spring charge-up and release", 1.0)
add("pad_phase", "a purple energy pad activating, an ethereal glassy shimmer charge-up", 1.0)
add("pad_impact", "a red-orange energy pad activating, a heavy low charge-up thud with a rumble", 1.0)
add("crate_break", "a wooden crate smashing apart, planks splintering and cracking", 1.0)
add("bot_stomp_clank", "a heavy metal robot being stomped on, a dull metallic clank and dent", 0.8)
add("door_open", "a heavy sci-fi door sliding open, a hydraulic hiss and motor", 1.5)
add("shutter_open", "a metal roller shutter rattling upward, ratcheting and rolling", 1.8)
add("gate_grind", "a heavy metal gate grinding open on rails, a long scraping rumble", 2.0)
add("laser_hum", "an electric laser fence, a steady low buzzing hum with a faint crackle", 3.0, loop=True)
add("laser_zap", "a laser beam zap hitting something, a sharp electric snap", 0.6)
add("turret_charge", "a sci-fi turret charging up, a rising whine and capacitor build", 1.2)
add("turret_fire", "a sci-fi turret firing a single energy shot, a crisp thump and zap", 0.7)
add("drone_hover", "a small hovering security drone, a steady soft rotor whirr and electric hum", 3.0, loop=True)
for i in range(1, 4):
    add("robot_beep_%d" % i, "a small robot beep, a short clean electronic tone", 0.5)
for i in range(1, 3):
    add("robot_chirp_%d" % i, "a small robot chirp, a quick curious electronic warble", 0.5)
add("robot_explosion", "a small robot exploding, a sharp pop and a burst of sparks and metal", 1.5)
add("robot_debris", "metal robot debris scattering and clattering on a concrete floor", 1.0)
add("plate_click", "a pressure plate clicking down, a firm mechanical click and thunk", 0.5)
add("plate_release", "a pressure plate releasing, a light mechanical click", 0.5)
add("checkpoint_chime", "a checkpoint reached, a calm bright layered chime with a soft tail", 1.2)
add("goo_bubble", "viscous glowing nanofluid goo bubbling slowly, thick wet bubbles", 3.0, loop=True)
add("vein_rise", "a glowing energy rising through veins, a swelling electric hum and crackle", 2.5)
add("absorb_pulse", "a nano absorption pulse, a deep soft heartbeat-like energy thump and wash", 1.5)
add("augment_click", "a tiny precise mechanical augment lock-in, a crisp digital click", 0.5)
add("augment_reveal", "an upgrade reveal, a crisp mechanical click followed by a bright shimmer", 1.0)
add("scanner_sweep", "a security scanner beam sweeping, a slow electronic sweep with a rising scan tone", 2.0)
add("credential_accepted", "a credential accepted, two clean ascending electronic tones and a latch click", 1.2)
for i in range(1, 4):
    add("thunder_%d" % i, "distant rolling thunder over a city at night, deep and slow", 5.0 if i < 3 else 6.0, infl=0.5)
add("splash", "a small splash of a cat paw dropping into a puddle", 0.8)
for i in range(1, 6):
    add("drop_%d" % i, "a single water drop falling and plinking into a shallow puddle", 0.5)
add("map_node_unlock", "a map location unlocking, a soft magical rising chime with a gentle whoosh", 1.5)
add("map_step", "a small light step marker tick, a soft wooden-glass tap", 0.5)
add("wing_flap", "a bird flapping its wings once, taking off", 0.6)

# Actor-kit sounds (KitSfx logical names). Variants are _1/_2 files.
add("laser_charge", "a sci-fi laser emitter charging, a tightening rising whine with a capacitor flutter and a bright electric peak", 1.2)
for i in range(1, 3):
    add("barrel_explode_%d" % i, "an explosive barrel detonating, a fiery boom with a metal shell rupture, a low sub thump and debris", 1.8)
add("barrel_fuse", "a short fuse burning and sizzling, a hissing crackle with spitting sparks", 1.5)
add("acid_hiss", "acid eating through metal, a corrosive fizzing hiss with small wet bubbles", 1.2)
add("acid_splash", "a splash of acid droplets landing on a floor, a wet sizzling splat", 0.8)
add("electric_warn", "an electrical hazard warning, a rising buzzing crackle with a few sharp sparks", 0.9)
add("electric_arc", "a continuous electric arc between two terminals, a steady crackling buzz with sharp snaps", 3.0, loop=True)
add("crusher_warn", "a heavy hydraulic crusher priming, a low mechanical groan and a pneumatic hiss", 1.0)
add("crusher_slam", "a heavy hydraulic press slamming down, a massive metallic impact with a deep boom and a short ring", 1.0)
add("spike_warn", "metal spikes arming under a floor, a quick mechanical ratchet and a small rattle", 0.7)
add("spike_pop", "metal spikes shooting up out of a floor, a sharp snapping thunk and a metallic ring", 0.6)
add("steam_hiss", "a burst of pressurised steam venting from a pipe, a sharp clean hiss that fades", 1.2)
add("flame_burst", "a short burst of flame from a nozzle, a whooshing roar with a soft ignition thump", 1.2)
add("bomb_drop", "a small bomb dropping through the air, a falling whistle ending in a metallic clunk", 1.0)
for i in range(1, 3):
    add("robot_explode_%d" % i, "a security robot blowing up, a hard electric pop, a fireball whump and shrapnel pinging away", 1.6)
add("robot_stun", "a robot being electrically stunned, a zapping buzz with a short-circuit stutter and a power-down wind", 1.0)
for i in range(1, 3):
    add("robot_clank_%d" % i, "a heavy robot foot clanking down on a metal floor, a hollow metallic clank with a short ring", 0.6)
for i in range(1, 3):
    add("debris_%d" % i, "chunks of concrete and metal debris falling and bouncing on a floor, a short clatter", 1.0)
add("hopper_squat", "a spring-legged robot crouching, a compressing hydraulic creak and a short coil squeak", 0.6)
for i in range(1, 3):
    add("hopper_land_%d" % i, "a spring-legged robot landing, a hard metallic thump with a springy boing and rattle", 0.7)
add("crawler_drop", "a small crawler robot dropping from a ceiling onto a floor, a light metallic thud and skitter", 0.7)
add("camera_alarm", "a security camera alarm, a steady rhythmic electronic alarm beeping pulse", 3.0, loop=True)
add("camera_spot", "a security camera spotting a target, a sharp electronic lock-on blip and a servo whirr", 0.8)
add("mech_charge", "a big combat mech charging a weapon, a deep rising electric hum with servo whine and a heavy thrum", 1.5)
for i in range(1, 3):
    add("mech_slam_%d" % i, "a giant combat mech slamming its fist into the ground, a huge heavy boom with a metal crunch and rumbling debris", 1.4)
add("wall_break", "a brittle wall bursting apart, a crunching crack with concrete chunks collapsing", 1.4)
for i in range(1, 3):
    add("wall_clank_%d" % i, "a hard clank against a thick metal wall, a short dull metallic hit with a ring", 0.6)
add("platform_shake", "a metal platform trembling before it falls, a rattling creak with loose bolts shaking", 1.2)
add("platform_fall", "a metal platform breaking loose and falling, a screeching wrench then a whoosh", 1.2)
add("conveyor_hum", "a factory conveyor belt running, a steady low motor hum with a soft rhythmic rolling clatter", 3.0, loop=True)
add("rock_fall", "a rock breaking loose and tumbling down, a short rumbling scrape and clatter", 1.0)
for i in range(1, 3):
    add("rock_land_%d" % i, "a heavy rock landing on stone ground, a solid thud with a gravel scatter", 0.7)
add("pickup_heal", "a nanotech healing pickup, a warm soft restorative shimmer with a gentle rising chime", 1.2)
add("memory_fragment", "a soft magical crystalline chime, delicate glass-like bell tones with a faint digital nanotech shimmer and a gentle tail", 2.0)

AMBIENCE = [
    # v3 (soft rain on a high roof; the first take had "a distant machine hum" and read as clanky). Chosen of three
    # candidates by spectral analysis; the raw is high-passed 40 Hz / low-passed 6.5 kHz and levelled to -24 LUFS.
    dict(name="amb_warehouse", sec=28, infl=0.5, af="highpass=f=40,lowpass=f=6500", lufs=-24, prompt="very gentle distant rain on a high tin roof inside a huge empty hall, soft airy patter, quiet and calm, a few faint water drips, no bangs, no clanging, no machine sounds, seamless loop"),
    # The indoor hum layer, a separate loop (Ambience.hum_bed) played about 13 dB under the rain; low-passed at 320 Hz.
    dict(name="amb_warehouse_hum", sec=20, af="highpass=f=35,lowpass=f=320", lufs=-24, prompt="a very faint, low, steady, smooth electrical hum, distant ventilation and transformer drone, constant, no rhythm, no clanks, no impacts, seamless loop"),
    dict(name="amb_yard", sec=25, prompt="steady heavy rain on an open concrete yard at night with gusting wind, seamless loop"),
    dict(name="amb_stacks", sec=25, prompt="lighter rain at height on rooftops, a wind blowing across tall buildings, a faint distant city hum, seamless loop"),
    dict(name="amb_perimeter", sec=25, prompt="rain easing off, a steady electric fence hum, a faint distant siren, damp night, seamless loop"),
    dict(name="amb_home", sec=25, prompt="a calm morning with birdsong, water dripping from eaves, a soft breeze, peaceful, seamless loop"),
    dict(name="amb_map", sec=25, prompt="a soft airy ambient pad drone, gentle and calm, faintly magical, seamless loop"),
    dict(name="rain_loop", sec=20, prompt="smooth gentle steady rain falling on the ground, no thunder, no wind, seamless loop"),
]
