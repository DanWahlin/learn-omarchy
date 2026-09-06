#!/usr/bin/env bash
# Build runtime sprite strips for a character from its concept sheets.
#
#   tools/prepare-character-sprites.sh <character>
#
# Reads assets/characters/<character>/sprites.conf (bash key=value) and the
# concept sheets under assets/characters/<character>/concepts/, then writes
# <character>-idle.png, -talk.png, -flight.png, -point.png, and -point-up.png
# into assets/characters/<character>/sprites/. All output is deterministic.
set -euo pipefail

character="${1:-}"
mode="${2:-}"
[[ "$character" =~ ^[a-z0-9-]+$ && ( -z "$mode" || "$mode" == "--clean-runtime-only" ) && $# -le 2 ]] || {
  echo "usage: prepare-character-sprites.sh <character> [--clean-runtime-only]" >&2
  exit 2
}

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
character_dir="$root/assets/characters/$character"
config="$character_dir/sprites.conf"
[[ -f "$config" ]] || { echo "prepare-character-sprites: config not found: $config" >&2; exit 1; }

# Defaults (HEXON's geometry); the config may override any of them.
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
strip_source="$character_dir/concepts/$character-idle-blink-strip-v1.png"
flight_source="$character_dir/concepts/$character-flight-v1.png"
# Extra flight frames (same canvas as flight_source, e.g. a wing down-stroke)
# appended into a multi-frame flight strip. All frames share one crop box so
# the body stays put while the wings move.
flight_extra_sources=()
# Optional talking strip laid out like the idle strip (8 copies in 192px
# columns) whose mouth/beak varies per copy. When set, the talk animation
# uses these faces instead of the idle strip's blink/happy faces.
talk_source=""
# Face box used for the talking strip; defaults to the idle face box.
talk_face_x=""
talk_face_y=""
talk_face_width=""
talk_face_height=""
# Optional polygon in face-crop coordinates. Keep surrounding eyes out of the
# replacement; also publish the masked patches for registered speech overlays.
talk_face_mask=""
# Optional frame order for the talk strip, as space-separated column indexes
# (e.g. "0 1 0 3 0 1 0 3"). Lets a strip alternate between a few clean copies
# instead of using every generated column.
talk_frame_order=""
point_source="$character_dir/concepts/$character-point-v1.png"
point_up_source="$character_dir/concepts/$character-point-up-v1.png"
# Optional closed-eye versions of the pointing poses (edits of the same
# sheets). The eye region is found by diffing against the open-eye sheet and
# pasted onto the fitted pose so the body stays pixel-identical while blinking.
point_blink_source="$character_dir/concepts/$character-point-blink-v1.png"
point_up_blink_source="$character_dir/concepts/$character-point-up-blink-v1.png"
# Optional fixed eye boxes ("WxH+X+Y" in the output frame) used instead of the
# automatic difference region, which generated edits can inflate.
point_face=""
point_up_face=""
# Halfway poses played while raising or lowering the pointing limb.
# "concept": fit <name>-point-mid-v1.png / <name>-point-up-mid-v1.png sheets.
# "derive": rotate the pointing arm about the shoulder by the angles below.
point_mid_mode="concept"
point_mid_source="$character_dir/concepts/$character-point-mid-v1.png"
point_up_mid_source="$character_dir/concepts/$character-point-up-mid-v1.png"
derive_arm_keep="128,66 171,101"
derive_shoulder="131,84"
derive_mid_angle=38
derive_up_mid_angle=-58
# "concept": build point-up from its own concept sheet.
# "derive": lift the arm from the finished pointing sprite (HEXON's method).
point_up_mode="concept"
derive_arm_crop="40x34+130+66"
derive_arm_scale="100%x130%"
derive_erase="131,62 200,104"
derive_arm_offset="+121+36"
# Alpha cutoff applied before trimming (e.g. "50%") to drop faint stray pixels
# left by generated art; empty keeps every pixel.
alpha_cutoff=""
# "trim": trim each strip frame on all sides (HEXON). "column": keep the full
# column width and trim vertically only, so copies that touch their column
# edges stay horizontally aligned with one another.
frame_align="trim"
# Explicitly audited isolated alpha=1 pixels, never a global glow threshold.
stray_point_pixels=()
stray_flight_pixels=()

# shellcheck disable=SC1090
source "$config"

command -v magick >/dev/null 2>&1 || { echo "prepare-character-sprites: ImageMagick is required" >&2; exit 1; }
output_dir="$character_dir/sprites"

clean_pixels() {
  local file="$1"; shift
  [[ -f "$file" && $# -gt 0 ]] || return 0
  local expression="" point
  for point in "$@"; do
    [[ -z "$expression" ]] || expression+=" || "
    expression+="(i == ${point%,*} && j == ${point#*,})"
  done
  magick "$file" -channel A -fx "u <= (1.01/255) && ($expression) ? 0 : u" +channel \
    -strip -define png:exclude-chunks=date,time "$file"
}

clean_runtime() {
  local pose
  for pose in point point-up point-blink point-up-blink point-mid point-up-mid; do
    clean_pixels "$output_dir/$character-$pose.png" "${stray_point_pixels[@]}"
  done
  clean_pixels "$output_dir/$character-flight.png" "${stray_flight_pixels[@]}"
}

if [[ "$mode" == "--clean-runtime-only" ]]; then
  clean_runtime
  echo "Cleaned audited stray alpha pixels for $character; body and glow preserved"
  exit 0
fi

for required in "$strip_source" "$flight_source" "$point_source"; do
  [[ -f "$required" ]] || { echo "prepare-character-sprites: source not found: $required" >&2; exit 1; }
done
if [[ "$point_up_mode" == "concept" ]]; then
  [[ -f "$point_up_source" ]] || { echo "prepare-character-sprites: source not found: $point_up_source" >&2; exit 1; }
fi

work="$character_dir/.sprite-work-$$"
mkdir "$work"
trap 'rm -rf "$work"' EXIT
mkdir -p "$output_dir"

cutoff_args=()
if [[ -n "$alpha_cutoff" ]]; then
  cutoff_args=(-channel A -threshold "$alpha_cutoff" +channel)
fi

for index in {0..7}; do
  source_x=$((index * source_frame_width))
  magick "$strip_source" \
    -crop "${source_frame_width}x${source_crop_height}+${source_x}+${source_crop_y}" \
    +repage \
    "${cutoff_args[@]}" \
    "$work/column-${index}.png"
  if [[ "$frame_align" == "column" ]]; then
    # Vertical bounds from the trim, but keep the full column width.
    trim_dims="$(magick "$work/column-${index}.png" -trim -format "%h %Y" info:)"
    trim_height="${trim_dims% *}"
    trim_y="${trim_dims#* }"
    magick "$work/column-${index}.png" \
      -crop "${source_frame_width}x${trim_height}+0+${trim_y}" \
      +repage \
      -filter point \
      -resize "x${character_height}" \
      -gravity south \
      -background none \
      -extent "${frame_size}x${frame_size}" \
      +repage \
      "$work/source-${index}.png"
  else
    magick "$work/column-${index}.png" \
      -trim \
      +repage \
      -filter point \
      -resize "x${character_height}" \
      -gravity south \
      -background none \
      -extent "${frame_size}x${frame_size}" \
      +repage \
      "$work/source-${index}.png"
  fi
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
  +append -strip -define png:exclude-chunks=date,time "$output_dir/$character-idle.png"

if [[ -n "$talk_source" ]]; then
  [[ -f "$talk_source" ]] || { echo "prepare-character-sprites: talk source not found: $talk_source" >&2; exit 1; }
  tf_x="${talk_face_x:-$face_x}"; tf_y="${talk_face_y:-$face_y}"
  tf_w="${talk_face_width:-$face_width}"; tf_h="${talk_face_height:-$face_height}"
  talk_frames=()
  speech_frames=()
  for index in {0..7}; do
    source_x=$((index * source_frame_width))
    magick "$talk_source" \
      -crop "${source_frame_width}x${source_crop_height}+${source_x}+${source_crop_y}" \
      +repage \
      "${cutoff_args[@]}" \
      "$work/talk-column-${index}.png"
    if [[ "$frame_align" == "column" ]]; then
      trim_dims="$(magick "$work/talk-column-${index}.png" -trim -format "%h %Y" info:)"
      magick "$work/talk-column-${index}.png" \
        -crop "${source_frame_width}x${trim_dims% *}+0+${trim_dims#* }" +repage \
        -filter point -resize "x${character_height}" -gravity south -background none \
        -extent "${frame_size}x${frame_size}" +repage "$work/talk-source-${index}.png"
    else
      magick "$work/talk-column-${index}.png" -trim +repage \
        -filter point -resize "x${character_height}" -gravity south -background none \
        -extent "${frame_size}x${frame_size}" +repage "$work/talk-source-${index}.png"
    fi
    magick "$work/talk-source-${index}.png" \
      -crop "${tf_w}x${tf_h}+${tf_x}+${tf_y}" +repage "$work/speech-${index}.png"
    if [[ -n "$talk_face_mask" ]]; then
      magick "$work/speech-${index}.png" \
        \( -size "${tf_w}x${tf_h}" xc:none +antialias -fill white -draw "polygon $talk_face_mask" \) \
        -compose DstIn -composite "$work/speech-${index}.png"
    fi
    magick "$work/source-0.png" "$work/speech-${index}.png" \
      -geometry "+${tf_x}+${tf_y}" -composite "$work/talk-${index}.png"
    talk_frames+=("$work/talk-${index}.png")
    speech_frames+=("$work/speech-${index}.png")
  done
  if [[ -n "$talk_frame_order" ]]; then
    ordered=()
    for index in $talk_frame_order; do ordered+=("${talk_frames[$index]}"); done
    talk_frames=("${ordered[@]}")
    ordered=()
    for index in $talk_frame_order; do ordered+=("${speech_frames[$index]}"); done
    speech_frames=("${ordered[@]}")
  fi
  magick "${talk_frames[@]}" +append -strip -define png:exclude-chunks=date,time "$output_dir/$character-talk.png"
  if [[ -n "$talk_face_mask" ]]; then
    magick "${speech_frames[@]}" +append -strip -define png:color-type=6 \
      -define png:exclude-chunks=date,time "$output_dir/$character-speech.png"
  fi
else
  magick \
    "$work/neutral.png" "$work/happy.png" "$work/neutral.png" "$work/happy.png" \
    "$work/blink-half.png" "$work/happy.png" "$work/neutral.png" "$work/happy.png" \
    +append -strip -define png:exclude-chunks=date,time "$output_dir/$character-talk.png"
fi

flight_sources=("$flight_source" "${flight_extra_sources[@]}")
if [[ ${#flight_sources[@]} -eq 1 ]]; then
  magick "$flight_source" \
    "${cutoff_args[@]}" \
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
    "$output_dir/$character-flight.png"
else
  # Union of every frame's trimmed box, so all frames crop and scale identically.
  min_x=999999; min_y=999999; max_x=0; max_y=0
  for source in "${flight_sources[@]}"; do
    [[ -f "$source" ]] || { echo "prepare-character-sprites: flight source not found: $source" >&2; exit 1; }
    box="$(magick "$source" "${cutoff_args[@]}" -trim -format "%X %Y %w %h" info:)"
    read -r bx by bw bh <<< "$box"
    bx=${bx#+}; by=${by#+}
    (( bx < min_x )) && min_x=$bx
    (( by < min_y )) && min_y=$by
    (( bx + bw > max_x )) && max_x=$((bx + bw))
    (( by + bh > max_y )) && max_y=$((by + bh))
  done
  flight_frames=()
  frame_index=0
  for source in "${flight_sources[@]}"; do
    magick "$source" \
      "${cutoff_args[@]}" \
      -crop "$((max_x - min_x))x$((max_y - min_y))+${min_x}+${min_y}" \
      +repage \
      -filter point \
      -resize "$((flight_frame_width - 16))x$((frame_size - 16))" \
      -gravity center \
      -background none \
      -extent "${flight_frame_width}x${frame_size}" \
      +repage \
      "$work/flight-${frame_index}.png"
    flight_frames+=("$work/flight-${frame_index}.png")
    frame_index=$((frame_index + 1))
  done
  magick "${flight_frames[@]}" +append -strip -define png:exclude-chunks=date,time "$output_dir/$character-flight.png"
fi

# Fit one or two pose sheets that share a canvas into point frames. With a
# second (blink) sheet both use one crop box so they align pixel for pixel.
fit_poses() {
  local output="$1"; local blink_output="$2"; local source="$3"; local blink_source="$4"; local face_box="${5:-}"
  local frame_w=$point_frame_width
  if [[ -z "$blink_source" || ! -f "$blink_source" ]]; then
    magick "$source" "${cutoff_args[@]}" -trim +repage -filter point \
      -resize "$((frame_w - 16))x$((frame_size - 16))" -gravity center -background none \
      -extent "${frame_w}x${frame_size}" +repage -strip -define png:exclude-chunks=date,time "$output"
    return
  fi
  local min_x=999999 min_y=999999 max_x=0 max_y=0 box bx by bw bh
  for sheet in "$source" "$blink_source"; do
    box="$(magick "$sheet" "${cutoff_args[@]}" -trim -format "%X %Y %w %h" info:)"
    read -r bx by bw bh <<< "$box"; bx=${bx#+}; by=${by#+}
    (( bx < min_x )) && min_x=$bx; (( by < min_y )) && min_y=$by
    (( bx + bw > max_x )) && max_x=$((bx + bw)); (( by + bh > max_y )) && max_y=$((by + bh))
  done
  local crop="$((max_x - min_x))x$((max_y - min_y))+${min_x}+${min_y}"
  magick "$source" "${cutoff_args[@]}" -crop "$crop" +repage -filter point \
    -resize "$((frame_w - 16))x$((frame_size - 16))" -gravity center -background none \
    -extent "${frame_w}x${frame_size}" +repage -strip -define png:exclude-chunks=date,time "$output"
  magick "$blink_source" "${cutoff_args[@]}" -crop "$crop" +repage -filter point \
    -resize "$((frame_w - 16))x$((frame_size - 16))" -gravity center -background none \
    -extent "${frame_w}x${frame_size}" +repage "$work/blink-fit.png"
  # Eye region = where the two fitted frames differ, padded a little.
  local diff
  if [[ -n "$face_box" ]]; then
    diff="$(echo "$face_box" | sed -E 's/^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$/\1 \2 \3 \4/')"
  else
    diff="$(magick "$output" "$work/blink-fit.png" -compose difference -composite -alpha off \
      -threshold 12% -trim -format "%w %h %X %Y" info: 2>/dev/null || true)"
  fi
  read -r bw bh bx by <<< "$diff"; bx=${bx#+}; by=${by#+}
  if [[ "$face_box" == "0x0+0+0" ]]; then
    magick "$work/blink-fit.png" -strip -define png:exclude-chunks=date,time "$blink_output"
    return
  fi
  if [[ -z "$bw" || "$bw" -le 0 ]]; then
    cp "$output" "$blink_output"
    return
  fi
  local pad=3
  bx=$(( bx - pad < 0 ? 0 : bx - pad )); by=$(( by - pad < 0 ? 0 : by - pad ))
  bw=$(( bw + pad * 2 )); bh=$(( bh + pad * 2 ))
  magick "$output" \( "$work/blink-fit.png" -crop "${bw}x${bh}+${bx}+${by}" +repage \) \
    -geometry "+${bx}+${by}" -composite -strip -define png:exclude-chunks=date,time "$blink_output"
  echo "  $(basename "$blink_output"): eye region ${bw}x${bh}+${bx}+${by}"
}

fit_poses "$output_dir/$character-point.png" "$output_dir/$character-point-blink.png" "$point_source" "$point_blink_source" "$point_face"

derive_point_up() {
  local source="$1"; local output="$2"
  magick "$source" -crop "$derive_arm_crop" +repage "$work/point-arm.png"
  magick "$work/point-arm.png" -rotate -90 -flop -filter point -resize "$derive_arm_scale" "$work/point-arm-up.png"
  magick "$source" \
    -alpha set \
    \( -size "${point_frame_width}x${frame_size}" xc:none -fill white -draw "rectangle $derive_erase" \) \
    -compose DstOut -composite \
    "$work/point-arm-up.png" -geometry "$derive_arm_offset" -compose Over -composite \
    -strip \
    -define png:exclude-chunks=date,time \
    "$output"
}

if [[ "$point_up_mode" == "concept" ]]; then
  fit_poses "$output_dir/$character-point-up.png" "$output_dir/$character-point-up-blink.png" "$point_up_source" "$point_up_blink_source" "$point_up_face"
else
  # Lift the outstretched arm from the pointing pose, turn it to point up,
  # mirror it so it leans away from the head, lengthen it a little, and
  # reattach it at the shoulder. The blink variant gets the same treatment.
  derive_point_up "$output_dir/$character-point.png" "$output_dir/$character-point-up.png"
  if [[ -f "$output_dir/$character-point-blink.png" ]]; then
    derive_point_up "$output_dir/$character-point-blink.png" "$output_dir/$character-point-up-blink.png"
  fi
fi

if [[ "$point_mid_mode" == "derive" ]]; then
  magick "$output_dir/$character-point.png" -alpha set \
    \( -size "${point_frame_width}x${frame_size}" xc:none -fill white -draw "rectangle $derive_erase" \) \
    -compose DstOut -composite "$work/mid-body.png"
  magick "$output_dir/$character-point.png" -alpha set \
    \( -size "${point_frame_width}x${frame_size}" xc:none -fill white -draw "rectangle $derive_arm_keep" \) \
    -compose DstIn -composite "$work/mid-arm.png"
  for spec in "point-mid $derive_mid_angle" "point-up-mid $derive_up_mid_angle"; do
    set -- $spec
    magick "$work/mid-arm.png" -virtual-pixel transparent -filter point -distort SRT "$derive_shoulder $2" +repage "$work/$1-arm.png"
    magick "$work/mid-body.png" "$work/$1-arm.png" -compose Over -composite \
      -strip -define png:exclude-chunks=date,time "$output_dir/$character-$1.png"
  done
else
  if [[ -f "$point_mid_source" ]]; then
    fit_poses "$work/point-refit.png" "$output_dir/$character-point-mid.png" "$point_source" "$point_mid_source" "0x0+0+0"
  fi
  if [[ -f "$point_up_mid_source" ]]; then
    fit_poses "$work/point-up-refit.png" "$output_dir/$character-point-up-mid.png" "$point_up_source" "$point_up_mid_source" "0x0+0+0"
  fi
fi

clean_runtime
echo "Prepared $character sprite strips in $output_dir"
