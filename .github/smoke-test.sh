#!/usr/bin/env bash
# Smoke-test a running copperline container before the image is published:
# every file the image ships must be served with a sane MIME type, and the
# page must reach its ready state in a real headless browser. Catches the
# class of failure where the build is green but the served page is dead
# (the originally published v0.13.0 image: try.js imported a file the site
# assembly step never copied, so the whole ES module graph was rejected).
#
# Usage: smoke-test.sh <base-url> <container-name>
# Needs: curl, docker, node with puppeteer-core installed (npm install
# --no-save puppeteer-core), and Chrome (CHROME_PATH to override the
# binary; defaults to /usr/bin/google-chrome, the GitHub runner's).
set -euo pipefail

base=${1:?usage: smoke-test.sh <base-url> <container-name>}
name=${2:?usage: smoke-test.sh <base-url> <container-name>}

fail() {
  echo "SMOKE FAIL: $*" >&2
  echo "--- container logs ---" >&2
  docker logs "$name" >&2 || true
  exit 1
}

for i in $(seq 1 30); do
  curl -fsS -o /dev/null "$base/" 2>/dev/null && break
  [ "$i" = 30 ] && fail "nginx did not answer within 30s"
  sleep 1
done

# Sweep every shipped file rather than a hard-coded list, so a file added
# by a future Copperline release is covered the day it appears. /files is
# the user volume (empty here) and carries no shipped assets.
files=$(docker exec "$name" sh -c \
  'cd /usr/share/nginx/html && find . -type f -not -path "./files/*" | sed "s|^\./||"')
[ -n "$files" ] || fail "no files found in the image"

for f in $files; do
  ct=$(curl -fsS -o /dev/null -w '%{content_type}' "$base/$f") \
    || fail "GET /$f did not return 200"
  case "$f" in
    # Module loading dies on a wrong script/wasm type, so pin those. The
    # html check guards the types-block-clobbering mistake nginx invites
    # (see nginx-default.conf).
    *.js)   case "$ct" in application/javascript*|text/javascript*) ;; \
              *) fail "/$f served as '$ct', not JavaScript";; esac ;;
    *.wasm) case "$ct" in application/wasm*) ;; \
              *) fail "/$f served as '$ct', not application/wasm";; esac ;;
    *.html) case "$ct" in text/html*) ;; \
              *) fail "/$f served as '$ct', not text/html";; esac ;;
  esac
  echo "ok: /$f ($ct)"
done

# The definitive check: a browser must load the module graph, init the
# wasm, fetch the AROS ROMs, and enable the Boot button.
node "$(dirname "$0")/smoke-page.mjs" "$base/" \
  || fail "page did not reach its ready state"

echo "SMOKE PASS"
