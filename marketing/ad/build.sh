#!/bin/zsh
# Builds the noNotch launch film → dist/noNotch-film-4k.mp4 (3840×2160) and dist/noNotch-film-1080p.mp4
#   marketing/ad/build.sh [fps=60]
set -euo pipefail
HERE=${0:A:h}
ROOT=${HERE:h:h}
FPS=${1:-60}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$HERE"
[[ -d node_modules ]] || npm install --silent

# Voiceover: Kokoro neural TTS (models/ is downloaded once, see README), each line placed at its cue in seconds
VOICE=${VOICE:-af_heart} SPEED=${SPEED:-1.0}
lines=(
  "0.45|Your Mac's notch? It's doing nothing."
  "3.4|So you're digging for Spotify, missing notifications, and hunting through a crowded menu bar. Again."
  "10.75|Meet No Notch. It turns the notch into a living Dynamic Island."
  "17.5|Hover, and your music or video opens right there. Artwork, scrubbing, even live lyrics."
  "24.4|Notifications, charging, AirPods and meetings drop in, then get out of your way."
  "30.0|Drag files to the shelf. Toggle Focus, Wi-Fi, dark mode. One flick."
  "35.7|Everything you need, one glance away, at near-zero CPU."
  "40.9|No Notch. Free for your Mac. Download it today."
)
uv run --quiet tts.py "$WORK" "$VOICE" "$SPEED" "${lines[@]#*|}"
inputs=() delays=() i=0
for l in $lines; do
  inputs+=(-i "$WORK/vo$i.wav")
  ms=$(( ${l%%|*} * 1000 )); ms=${ms%.*}
  delays+=("[$((i + 1)):a]aresample=48000,pan=stereo|c0=c0|c1=c0,adelay=${ms}|${ms}[v$i]")
  i=$((i + 1))
done
vlabels=$(for j in $(seq 0 $((i - 1))); do printf "[v$j]"; done)

echo "→ score"
node audio.mjs "$WORK/music.wav"
echo "→ frames ($FPS fps)"
SCALE=2 node render.mjs "$WORK/frames" "$FPS" "${WORKERS:-6}"

echo "→ mix + encode"
mkdir -p "$ROOT/dist"
ffmpeg -v error -y -framerate "$FPS" -i "$WORK/frames/%05d.jpg" -i "$WORK/music.wav" $inputs -filter_complex "
  $(IFS=';'; echo "${delays[*]}");
  ${vlabels}amix=inputs=$i:normalize=0,highpass=f=90,equalizer=f=3200:t=q:w=1.2:g=3,acompressor=threshold=0.12:ratio=3:attack=8:release=120:makeup=1.6,apad=whole_dur=45[vo];
  [vo]asplit[vo1][vo2];
  [1:a][vo1]sidechaincompress=threshold=0.04:ratio=5:attack=25:release=350[bed];
  [bed][vo2]amix=inputs=2:normalize=0,loudnorm=I=-14:TP=-1:LRA=9,atrim=0:45[a]" \
  -map 0:v -map "[a]" -c:v libx264 -preset medium -crf 16 -pix_fmt yuv420p -tune film -profile:v high -level 5.2 -c:a aac -b:a 256k -ar 48000 -movflags +faststart \
  -t 45 "$ROOT/dist/noNotch-film-4k.mp4"
ffmpeg -v error -y -i "$ROOT/dist/noNotch-film-4k.mp4" -vf scale=1920:1080:flags=lanczos -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p \
  -c:a copy -movflags +faststart "$ROOT/dist/noNotch-film-1080p.mp4"
echo "✓ $ROOT/dist/noNotch-film-4k.mp4"
echo "✓ $ROOT/dist/noNotch-film-1080p.mp4"
