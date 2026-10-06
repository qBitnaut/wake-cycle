"""Music via the ElevenLabs Music API, made into seamless loops with an ffmpeg crossfade
(the last XF seconds blend into the first XF). Raw mp3 cached in scratch. Usage: gen_music.py [name ...]"""
import os, subprocess, sys
import eleven

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(eleven.SCRATCH, "music_raw")
OUT = os.path.join(ROOT, "assets/audio/music")
XF = 3.0
TRACKS = [
    ("warehouse", 30, "Lonely, spacious, curious ambient piece for a small cat waking in a huge dark empty warehouse: soft felted piano with sparse notes, airy synth pad, faint glassy textures, slow, no drums, gentle and mysterious, loopable."),
    ("yard", 30, "Atmospheric night-rain ambient: a low pulsing synth heartbeat that slowly rises, wet reverberant plucks, distant pads, building quiet urgency and wonder, soft sub bass, no vocals, loopable."),
    ("stacks", 30, "Wonder and height: a wide airy ambient piece with shimmering arpeggiated bells, a floating warm pad and a slow melody, the feeling of looking over a sleeping city at night from rooftops, hopeful, no drums, loopable."),
    ("perimeter", 30, "Tension slowly building towards a hopeful resolve: low electric hum, a restrained rhythmic pulse, rising strings and synths that open into a warm major-key lift, cinematic, no vocals, loopable."),
    ("home", 30, "Warm, gentle, resolving morning music: soft acoustic guitar and piano with a light string pad, tender and peaceful, homecoming, sunlight, unhurried, no vocals, loopable."),
    ("map", 30, "A calm travel theme for a world map: a light rolling harp and soft marimba with a warm pad and a gentle walking pulse, curious and relaxed, no vocals, loopable."),
]


def loopify(src, dst, dur):
    x = XF
    fc = ("[0:a]atrim=0:%f,asetpts=PTS-STARTPTS[h];[0:a]atrim=%f:%f,asetpts=PTS-STARTPTS[m];"
          "[0:a]atrim=%f:%f,asetpts=PTS-STARTPTS[t];[t][h]acrossfade=d=%f[cf];[m][cf]concat=n=2:v=0:a=1,loudnorm=I=-20:TP=-2:LRA=9[o]"
          % (x, x, dur - x, dur - x, dur, x))
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-filter_complex", fc, "-map", "[o]", "-ac", "2",
                    "-ar", "44100", "-c:a", "libvorbis", "-b:a", "112k", dst], check=True)


def main():
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, sec, prompt in TRACKS:
        if only and name not in only:
            continue
        raw = os.path.join(RAW, name + ".mp3")
        if not os.path.exists(raw):
            out, _, _ = eleven.post("/v1/music?output_format=mp3_44100_128",
                                    {"prompt": prompt, "music_length_ms": sec * 1000, "force_instrumental": True},
                                    "music", name, est=sec * 40)
            open(raw, "wb").write(out)
            print("made", name, flush=True)
        dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", raw]))
        loopify(raw, os.path.join(OUT, "wc_%s.ogg" % name), dur)


if __name__ == "__main__":
    main()
