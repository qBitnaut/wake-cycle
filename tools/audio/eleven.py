"""Tiny ElevenLabs client for Wake Cycle's audio. The API key is read from
~/.config/wake-cycle/elevenlabs.key at call time and never stored, logged or printed."""
import json, os, time, urllib.request, urllib.error

KEY_PATH = os.path.expanduser("~/.config/wake-cycle/elevenlabs.key")
BASE = "https://api.elevenlabs.io"
SCRATCH = os.environ.get("WAKE_AUDIO_SCRATCH", "/tmp/claude-1000/scratch")
SPEND_LOG = os.path.join(SCRATCH, "spend.jsonl")


def _key():
    with open(KEY_PATH) as f:
        return f.read().strip()


def used():
    for attempt in range(6):
        try:
            return _used()
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(5 * (attempt + 1))
    raise RuntimeError("subscription endpoint rate limited")


def _used():
    r = urllib.request.Request(BASE + "/v1/user/subscription", headers={"xi-api-key": _key()})
    d = json.load(urllib.request.urlopen(r))
    return d["character_count"], d["character_limit"]


def post(path, body, category, label, est=0):
    """POST JSON, return (bytes, est, None). Logs the estimated credits to the spend log;
    the subscription endpoint lags and is rate limited, so it is polled per batch (see used())."""
    data = json.dumps(body).encode()
    r = urllib.request.Request(BASE + path, data=data, method="POST",
                               headers={"xi-api-key": _key(), "Content-Type": "application/json"})
    for attempt in range(6):
        try:
            out = urllib.request.urlopen(r, timeout=300).read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 5:
                time.sleep(3 * (attempt + 1))
                continue
            raise RuntimeError("HTTP %d on %s: %s" % (e.code, path, e.read()[:300].decode("utf8", "replace")))
    os.makedirs(SCRATCH, exist_ok=True)
    with open(SPEND_LOG, "a") as f:
        f.write(json.dumps({"t": time.time(), "cat": category, "label": label, "est": est}) + "\n")
    return out, est, None
