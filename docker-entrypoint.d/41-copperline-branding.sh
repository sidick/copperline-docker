#!/bin/sh
# Rebrand the stock page shell from the environment: COPPERLINE_TITLE
# replaces the page heading and the browser-tab <title>, and
# COPPERLINE_SUBTITLE the line under the heading. Values are single-line
# plain text (they are HTML-escaped here).
#
# Only the marker elements the stock index.html carries are touched. A
# bind-mounted shell is left alone: read-only makes the edit impossible,
# and a custom shell without the markers is its author's business - both
# cases are noted in the log and ignored. Anything beyond these two
# strings is theme.css or bring-your-own-index.html territory.
set -eu

html=/usr/share/nginx/html/index.html
title=${COPPERLINE_TITLE:-}
subtitle=${COPPERLINE_SUBTITLE:-}

[ -n "$title" ] || [ -n "$subtitle" ] || exit 0

# HTML-escape the text, then escape sed replacement specials (\ & |).
esc() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' \
    | sed 's/[\\&|]/\\&/g'
}

# In-place edit that must not kill the container: a read-only bind mount
# passes -w (permission bits) but fails at write time, so try the edit and
# downgrade any failure to a warning.
edit() { # $1 = sed program, $2 = env var name (for the warning)
  if ! sed -i "$1" "$html" 2>/dev/null; then
    echo "copperline: could not edit $html (read-only mount?); ignoring $2" >&2
    return 1
  fi
}

if [ -n "$title" ]; then
  if grep -q 'id="page-title"' "$html"; then
    t=$(esc "$title")
    edit "s|<span id=\"page-title\">[^<]*</span>|<span id=\"page-title\">$t</span>|" COPPERLINE_TITLE \
      && edit "s|<title>[^<]*</title>|<title>$t</title>|" COPPERLINE_TITLE \
      && echo "copperline: page title set from COPPERLINE_TITLE" >&2 \
      || true
  else
    echo "copperline: no page-title marker in $html (custom shell?); ignoring COPPERLINE_TITLE" >&2
  fi
fi

if [ -n "$subtitle" ]; then
  if grep -q 'id="page-subtitle"' "$html"; then
    s=$(esc "$subtitle")
    edit "s|<small id=\"page-subtitle\">[^<]*</small>|<small id=\"page-subtitle\">$s</small>|" COPPERLINE_SUBTITLE \
      && echo "copperline: page subtitle set from COPPERLINE_SUBTITLE" >&2 \
      || true
  else
    echo "copperline: no page-subtitle marker in $html (custom shell?); ignoring COPPERLINE_SUBTITLE" >&2
  fi
fi
