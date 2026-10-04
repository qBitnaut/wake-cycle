"""Wake Cycle HD shared palette (single source of truth for the blend tools).

palette.md documents these values for humans; if they disagree, this file
wins and palette.md is regenerated from it (`python3 palette.py --md`).

Every material ramp has six hand-picked stops, dark to light:

    ink     outline and the deepest crevice (close to the global INK)
    shadow  the shaded side; carries the ramp's hue shift (cooler, purpler)
    face    the flat, lit-from-front surface; sets the material's value
    light   bevel tops and rounded highlights
    high    hot edge highlight
    spec    specular glint (near white, tinted warm)

Shadows lean toward violet-blue and highlights toward warm yellow, so every
ramp is hue-shifted the way hand pixel art is, rather than a straight
brightness scale of one hue.
"""

INK = "#161630"  # global outline / darkest navy (ansimuz Warped's ink)

RAMPS = {
    # Foreground structure: floors, walls, girders, catwalks. Teal-blue steel.
    "steel": {
        "ink": "#141a2c",
        "shadow": "#2a4658",
        "face": "#5b7280",
        "light": "#8aa7ab",
        "high": "#c3d8cf",
        "spec": "#f1f5e6",
    },
    # Darker steel for ceilings, bulkheads, window frames: sits between the
    # back wall and the walkable structure in value.
    "bulkhead": {
        "ink": "#10121f",
        "shadow": "#1c2c3b",
        "face": "#354655",
        "light": "#536a74",
        "high": "#7f9898",
        "spec": "#b4c6bd",
    },
    # Hot pipes and small accents. Ansimuz Warped's platform ramp.
    "rust": {
        "ink": "#2d163a",
        "shadow": "#6e2b4b",
        "face": "#9a4c44",
        "light": "#bc7652",
        "high": "#e8a25d",
        "spec": "#fbd9a0",
    },
    # Crates, underfloor, heavy structural accents.
    "maroon": {
        "ink": "#1d1230",
        "shadow": "#45193f",
        "face": "#7c3a4c",
        "light": "#9e5658",
        "high": "#c98068",
        "spec": "#efb98a",
    },
    # Coolant pipes. Muted: must never read as the cyan PHASE power glow.
    "teal": {
        "ink": "#0f1f2c",
        "shadow": "#1e4a58",
        "face": "#35727a",
        "light": "#4f958f",
        "high": "#86c4b2",
        "spec": "#dff4e6",
    },
    # Gas / data pipes. Muted dusk violet: must never read as IMPACT violet.
    "violet": {
        "ink": "#1a1430",
        "shadow": "#37295a",
        "face": "#5a4f80",
        "light": "#7a72a4",
        "high": "#a59ec8",
        "spec": "#ece6f4",
    },
    # Spikes, laser emitters, warning furniture. Matches FXPalette.SODIUM.
    "hazard": {
        "ink": "#2a1208",
        "shadow": "#8a3a14",
        "face": "#d07a26",
        "light": "#eda63a",
        "high": "#ffd66e",
        "spec": "#fff4cc",
    },
}

# Non-ramp colours.
SINGLES = {
    "laser_core": "#fff0e0",   # beam centre line (emissive, x1.0-1.2 in Godot)
    "laser": "#ff4a3a",        # beam body: red-orange, distinct from fur and sodium
    "sodium": "#ff8c29",       # warning lamp glass = FXPalette.SODIUM (1.0, 0.55, 0.16)
    "indicator": "#41b5c0",    # back-wall status lights (calmed from ansimuz 00c9ea)
    "moon": "#b3ccff",         # = FXPalette.MOON (0.70, 0.80, 1.0)
    "cat_outline": "#161630",  # 1 px outline on the HD cat = INK
}

# Back wall family, dark to light: the harmonised Warped interior wall
# (harmonize_bg.py) plus the flat upper-wall fill and seams (mock_c.py).
# Everything behind the play space lives here, below the steel face in value.
BACKWALL = ["#0f1620", "#141c27", "#1a2431", "#202d3a", "#263646", "#2b4152", "#395766"]

# Night sky seen through openings (Warped City skyline, harmonised).
SKY = ["#0c1030", "#121845", "#182252", "#1e2c62", "#2c4479", "#5a86ac"]


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def ramp_rgb(name):
    return {k: hex_to_rgb(v) for k, v in RAMPS[name].items()}


def _md():
    out = ["| ramp | ink | shadow | face | light | high | spec |", "|---|---|---|---|---|---|---|"]
    for name, r in RAMPS.items():
        out.append("| %s | %s |" % (name, " | ".join("`%s`" % r[k] for k in ("ink", "shadow", "face", "light", "high", "spec"))))
    return "\n".join(out)


if __name__ == "__main__":
    import sys
    if "--md" in sys.argv:
        print(_md())
