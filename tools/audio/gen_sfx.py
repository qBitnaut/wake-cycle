"""SFX + ambience via ElevenLabs sound generation. Raw mp3 cached in scratch; assets are mono OGG.
Usage: gen_sfx.py [sfx|amb] [name ...]"""
import json, os, subprocess, sys, re
import eleven, sfx_spec

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(eleven.SCRATCH, "sfx_raw")


def peak_norm_db(src):
    r = subprocess.run(["ffmpeg", "-i", src, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"max_volume: (-?[\d.]+) dB", r.stderr)
    return float(m.group(1)) if m else 0.0


def to_ogg(src, dst, kbps, target=-2.0, trim=True):
    gain = target - peak_norm_db(src)
    af = "volume=%fdB" % gain
    if trim:
        af = "silenceremove=start_periods=1:start_threshold=-55dB:start_silence=0.01," + af
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-af", af, "-ac", "1", "-ar", "44100",
                    "-c:a", "libvorbis", "-b:a", "%dk" % kbps, dst], check=True)


def make(item, category, outdir, kbps, loop_default=False):
    os.makedirs(RAW, exist_ok=True)
    raw = os.path.join(RAW, item["name"] + ".mp3")
    if not os.path.exists(raw):
        body = {"text": item["prompt"], "duration_seconds": item["sec"], "prompt_influence": item.get("infl", 0.6),
                "model_id": "eleven_text_to_sound_v2"}
        if item.get("loop") or loop_default:
            body["loop"] = True
        out, est, _ = eleven.post("/v1/sound-generation?output_format=mp3_44100_128", body, category, item["name"], est=int(item["sec"] * 20))
        open(raw, "wb").write(out)
        print("made", item["name"], flush=True)
    os.makedirs(outdir, exist_ok=True)
    dst = os.path.join(outdir, item["name"] + ".ogg")
    to_ogg(raw, dst, kbps, trim=not (item.get("loop") or loop_default))
    return dst


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "sfx"
    only = set(sys.argv[2:])
    if which == "sfx":
        outdir = os.path.join(ROOT, "assets/audio/sfx")
        for it in sfx_spec.SFX:
            if only and it["name"] not in only:
                continue
            make(it, "sfx", outdir, 80)
    else:
        outdir = os.path.join(ROOT, "assets/audio/amb")
        for it in sfx_spec.AMBIENCE:
            if only and it["name"] not in only:
                continue
            make(it, "ambience", outdir, 96, loop_default=True)


if __name__ == "__main__":
    main()
