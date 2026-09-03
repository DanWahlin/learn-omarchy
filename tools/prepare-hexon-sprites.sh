#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_strip="$root/assets/characters/hexon/concepts/hexon-idle-blink-strip-v1.png"
flight_source="$root/assets/characters/hexon/concepts/hexon-flight-v1.png"
point_source="$root/assets/characters/hexon/concepts/hexon-point-v1.png"
output_dir="$root/assets/characters/hexon/sprites"
frame_size=192
flight_frame_width=256
point_frame_width=224
character_height=160
source_frame_width=192
source_crop_height=520
source_crop_y=220
face_width=48
face_height=28
face_x=72
face_y=66

command -v magick >/dev/null 2>&1 || {
  echo "prepare-hexon-sprites: ImageMagick is required" >&2
  exit 1
}
[[ -f "$source_strip" ]] || {
  echo "prepare-hexon-sprites: source strip not found: $source_strip" >&2
  exit 1
}
[[ -f "$flight_source" ]] || {
  echo "prepare-hexon-sprites: flight source not found: $flight_source" >&2
  exit 1
}
[[ -f "$point_source" ]] || {
  echo "prepare-hexon-sprites: point source not found: $point_source" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$output_dir"

for index in {0..7}; do
  source_x=$((index * source_frame_width))
  magick "$source_strip" \
    -crop "${source_frame_width}x${source_crop_height}+${source_x}+${source_crop_y}" \
    +repage \
    -trim \
    +repage \
    -filter point \
    -resize "x${character_height}" \
    -gravity south \
    -background none \
    -extent "${frame_size}x${frame_size}" \
    +repage \
    "$work/source-${index}.png"
done

compose_face() {
  local expression_frame="$1"
  local output="$2"
  magick "$work/source-0.png" \
    \( "$work/source-${expression_frame}.png" \
      -crop "${face_width}x${face_height}+${face_x}+${face_y}" \
      +repage \) \
    -geometry "+${face_x}+${face_y}" \
    -composite \
    "$output"
}

compose_face 0 "$work/neutral.png"
compose_face 1 "$work/blink-half.png"
compose_face 2 "$work/blink-closed.png"
compose_face 3 "$work/happy.png"

magick \
  "$work/neutral.png" "$work/neutral.png" "$work/neutral.png" "$work/neutral.png" \
  "$work/neutral.png" "$work/neutral.png" "$work/neutral.png" "$work/neutral.png" \
  "$work/neutral.png" "$work/neutral.png" "$work/neutral.png" "$work/blink-half.png" \
  "$work/blink-closed.png" "$work/blink-half.png" "$work/neutral.png" "$work/neutral.png" \
  +append -strip -define png:exclude-chunks=date,time "$output_dir/hexon-idle.png"

magick \
  "$work/neutral.png" "$work/happy.png" "$work/neutral.png" "$work/happy.png" \
  "$work/blink-half.png" "$work/happy.png" "$work/neutral.png" "$work/happy.png" \
  +append -strip -define png:exclude-chunks=date,time "$output_dir/hexon-talk.png"

magick "$flight_source" \
  -trim \
  +repage \
  -filter point \
  -resize "$((flight_frame_width - 16))x$((frame_size - 16))" \
  -gravity center \
  -background none \
  -extent "${flight_frame_width}x${frame_size}" \
  +repage \
  -strip \
  -define png:exclude-chunks=date,time \
  "$output_dir/hexon-flight.png"

magick "$point_source" \
  -trim \
  +repage \
  -filter point \
  -resize "$((point_frame_width - 16))x$((frame_size - 16))" \
  -gravity center \
  -background none \
  -extent "${point_frame_width}x${frame_size}" \
  +repage \
  -strip \
  -define png:exclude-chunks=date,time \
  "$output_dir/hexon-point.png"

echo "Prepared HEXON sprite strips in $output_dir"
