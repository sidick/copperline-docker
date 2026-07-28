#!/bin/sh
# Generate the page's optional copperline.json (site defaults - machine
# model, disk/ROM to load, autoboot, and so on; the schema is upstream's,
# see docs/guide/browser.md) from COPPERLINE_* environment variables, so
# the common cases need no file authoring:
#
#   docker run -e COPPERLINE_DF0=files/demo.adf -e COPPERLINE_AUTOBOOT=true ...
#
# Runs from /docker-entrypoint.d/ (the nginx image executes these at
# startup, as the nginx user). Precedence:
#   - a copperline.json that already exists (bind-mounted) always wins:
#     the file is left alone and COPPERLINE_* vars are ignored, loudly;
#   - with no COPPERLINE_* vars set, nothing is written, the page's
#     config fetch 404s, and the emulator runs its stock defaults;
#   - either way, ?df0=/?kick=/?machine=/?joy=/?fdspeed= URL parameters
#     override the file per visit, and hand changes on the page win.
set -eu

out=/usr/share/nginx/html/copperline.json

any=false
for v in MACHINE KICK DF0 JOY FDSPEED FLOPPY_SOUNDS MONO_AUDIO \
         SERIAL_URL SERIAL_RAW AUTOBOOT; do
  eval "val=\${COPPERLINE_${v}:-}"
  [ -n "$val" ] && any=true
done
$any || exit 0

if [ -e "$out" ]; then
  echo "copperline: $out already exists (bind-mounted?); ignoring COPPERLINE_* environment" >&2
  exit 0
fi

# Minimal JSON string escaping: backslash and double quote.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

fields=''
emit() {
  fields="${fields:+$fields,
}  $1"
}
emit_str() { # $1 = json key, $2 = value ('' = unset)
  { [ -n "$2" ] && emit "\"$1\": \"$(esc "$2")\""; } || true
}
emit_bool() { # $1 = json key, $2 = value, $3 = env var name (for the warning)
  case "$2" in
    '') ;;
    true|false) emit "\"$1\": $2" ;;
    *) echo "copperline: ignoring $3='$2' (expected true or false)" >&2 ;;
  esac
}

emit_str  machine       "${COPPERLINE_MACHINE:-}"
emit_str  kick          "${COPPERLINE_KICK:-}"
emit_str  df0           "${COPPERLINE_DF0:-}"
emit_str  joy           "${COPPERLINE_JOY:-}"
case "${COPPERLINE_FDSPEED:-}" in
  '') ;;
  100|200|400|800|0) emit "\"floppy_speed\": ${COPPERLINE_FDSPEED}" ;;
  turbo)             emit '"floppy_speed": 0' ;;
  *) echo "copperline: ignoring COPPERLINE_FDSPEED='${COPPERLINE_FDSPEED}' (expected 100, 200, 400, 800, 0 or turbo)" >&2 ;;
esac
emit_bool floppy_sounds "${COPPERLINE_FLOPPY_SOUNDS:-}" COPPERLINE_FLOPPY_SOUNDS
emit_bool mono_audio    "${COPPERLINE_MONO_AUDIO:-}"    COPPERLINE_MONO_AUDIO
emit_str  serial_url    "${COPPERLINE_SERIAL_URL:-}"
emit_bool serial_raw    "${COPPERLINE_SERIAL_RAW:-}"    COPPERLINE_SERIAL_RAW
emit_bool autoboot      "${COPPERLINE_AUTOBOOT:-}"      COPPERLINE_AUTOBOOT

[ -n "$fields" ] || exit 0

printf '{\n%s\n}\n' "$fields" > "$out"
echo "copperline: wrote $out from COPPERLINE_* environment" >&2
