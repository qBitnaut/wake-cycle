"""Writes assets/audio/sfx/sfx.json: logical name -> files, level (dB, relative to the file's -2 dBFS peak),
pitch jitter, loop. Run after gen_sfx.py. Sfx.play(ctx, "jump") picks one of the files at random."""
import json, os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
D = os.path.join(ROOT, "assets/audio/sfx")


def v(prefix, n):
    return ["%s_%d.ogg" % (prefix, i) for i in range(1, n + 1)]


M = {}


def add(name, files, db=-8.0, jitter=0.04, loop=False):
    if isinstance(files, str):
        files = [files + ".ogg"]
    M[name] = {"files": files, "db": db, "jitter": jitter}
    if loop:
        M[name]["loop"] = True


add("step_metal", v("step_metal", 3), -16, 0.08)
add("step_concrete", v("step_concrete", 3), -16, 0.08)
add("step_wet", v("step_wet", 3), -15, 0.08)
add("step_wood", v("step_wood", 3), -16, 0.08)
add("jump", "jump", -9)
add("double_jump", "double_jump", -9)
add("land", "land", -12)
add("land_hard", "land_hard", -8)
add("crawl", "crawl", -16)
add("spring_boost", "spring_boost", -8)
add("surge_whoosh", "surge_whoosh", -9)
add("surge_loop", "surge_loop", -14, 0.0, True)
add("phase_dash", "phase_dash", -8)
add("impact_pound", "impact_pound", -5)
add("shockwave_burst", "shockwave_burst", -6)
add("hurt", "hurt", -8)
add("pickup_small", "pickup_small", -9)
add("pickup_big", "pickup_big", -8)
add("pickup_rare", "pickup_rare", -7)
add("pickup_letter", "pickup_letter", -6)
add("pickup_fish", "pickup_fish", -7)
add("power_up", "power_up", -8)
for p in ("surge", "spring", "phase", "impact"):
    add("pad_" + p, "pad_" + p, -7)
add("crate_break", "crate_break", -6)
add("bot_stomp", "bot_stomp_clank", -7)
add("door_open", "door_open", -8)
add("shutter_open", "shutter_open", -9)
add("gate_grind", "gate_grind", -8)
add("laser_hum", "laser_hum", -14, 0.0, True)
add("laser_zap", "laser_zap", -9)
add("turret_charge", "turret_charge", -9)
add("turret_fire", "turret_fire", -7)
add("drone_hover", "drone_hover", -14, 0.0, True)
add("robot_beep", v("robot_beep", 3), -12, 0.05)
add("robot_chirp", v("robot_chirp", 2), -11, 0.05)
add("robot_explosion", "robot_explosion", -5)
add("robot_debris", "robot_debris", -8)
add("plate_click", "plate_click", -9)
add("plate_release", "plate_release", -11)
add("checkpoint", "checkpoint_chime", -8)
add("goo_bubble", "goo_bubble", -12, 0.0, True)
add("vein_rise", "vein_rise", -10)
add("absorb_pulse", "absorb_pulse", -6)
add("augment_click", "augment_click", -12, 0.06)
add("augment_reveal", "augment_reveal", -10)
add("scanner_sweep", "scanner_sweep", -10)
add("credential_accepted", "credential_accepted", -8)
add("thunder", v("thunder", 3), -8, 0.03)
add("splash", "splash", -12)
add("drop", v("drop", 5), -16, 0.12)
add("map_node_unlock", "map_node_unlock", -10)
add("map_step", "map_step", -14)
add("wing_flap", "wing_flap", -18)
for n, m in M.items():
    for f in m["files"]:
        assert os.path.exists(os.path.join(D, f)), f
json.dump(M, open(os.path.join(D, "sfx.json"), "w"), indent="\t", sort_keys=True)
print(len(M), "names")
