# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = ["kokoro-onnx>=0.4", "soundfile"]
# ///
"""Neural voiceover with Kokoro (local, Apache-2.0).
   uv run tts.py <out_dir> <voice> <speed> "line 1" "line 2" ...  → out_dir/vo0.wav, vo1.wav, …"""
import sys
from pathlib import Path

import soundfile as sf
from kokoro_onnx import Kokoro

models = Path(__file__).parent / "models"
out, voice, speed, *lines = sys.argv[1:]
Path(out).mkdir(parents=True, exist_ok=True)
tts = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"))
for i, line in enumerate(lines):
    samples, rate = tts.create(line, voice=voice, speed=float(speed), lang="en-us")
    sf.write(f"{out}/vo{i}.wav", samples, rate)
    print(f"vo{i}: {len(samples) / rate:.2f}s  {line}")
