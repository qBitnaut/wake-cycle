"""Narration for data/monologue.json via ElevenLabs TTS (eleven_v4_turbo).
Raw mp3 are cached in the scratch dir (never regenerate a line already made); the
game assets are mono OGG, trimmed and normalised to -16 LUFS. No key is stored here."""
import json, os, re, subprocess, sys
import eleven

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets/audio/voice")
RAW = os.path.join(eleven.SCRATCH, "voice_raw")
VOICE_ID = "bIHbv24MWmeRgasZH58o"  # Will - Relaxed Optimist
MODEL = "eleven_v4_turbo"
SETTINGS = {"stability": 0.45, "similarity_boost": 0.75, "style": 0.3, "use_speaker_boost": True}


def speak_text(t):
    t = t.replace("…", "...")
    t = re.sub(r"\.\.\.(?=\S)", "... ", t)
    return t.strip()


def lines():
    d = json.load(open(os.path.join(ROOT, "data/monologue.json")))
    for k, v in d.items():
        for i, l in enumerate(v):
            yield k, i, (l["text"] if isinstance(l, dict) else l), v


def to_ogg(src, dst):
    af = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse," \
         "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.05,areverse,loudnorm=I=-16:TP=-1.5:LRA=7"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-af", af, "-ac", "1", "-ar", "44100",
                    "-c:a", "libvorbis", "-b:a", "80k", dst], check=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RAW, exist_ok=True)
    manifest = {"voice_id": VOICE_ID, "voice_name": "Will - Relaxed Optimist", "model_id": MODEL,
                "voice_settings": SETTINGS, "format": "ogg vorbis mono 44.1k ~80kbps, -16 LUFS", "clips": {}}
    for k, i, text, all_lines in lines():
        name = "%s_%d" % (k, i)
        raw = os.path.join(RAW, name + ".mp3")
        if not os.path.exists(raw):
            body = {"text": speak_text(text), "model_id": MODEL, "voice_settings": SETTINGS}
            if i > 0:
                p = all_lines[i - 1]
                body["previous_text"] = speak_text(p["text"] if isinstance(p, dict) else p)
            if i < len(all_lines) - 1:
                n = all_lines[i + 1]
                body["next_text"] = speak_text(n["text"] if isinstance(n, dict) else n)
            out, sp, rem = eleven.post("/v1/text-to-speech/%s?output_format=mp3_44100_128" % VOICE_ID, body, "narration", name, est=len(body["text"]))
            open(raw, "wb").write(out)
            print(name, len(text), "reported spend", sp, flush=True)
        dst = os.path.join(OUT, name + ".ogg")
        to_ogg(raw, dst)
        dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", dst]))
        manifest["clips"][name] = {"file": "%s.ogg" % name, "text": text, "seconds": round(dur, 2)}
    json.dump(manifest, open(os.path.join(OUT, "voice.json"), "w"), indent="\t")


if __name__ == "__main__":
    main()
