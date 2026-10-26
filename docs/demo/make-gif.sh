#!/bin/sh
# Convert a trimmed screen recording into the README GIF.
# Usage: docs/demo/make-gif.sh demo.mov
set -eu
input=${1:?usage: docs/demo/make-gif.sh <recording>}
output=docs/assets/navigation.gif
mkdir -p "$(dirname "$output")"
ffmpeg -y -i "$input" \
  -filter_complex '[0:v]fps=12,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse' \
  -loop 0 "$output"
ls -lh "$output"
