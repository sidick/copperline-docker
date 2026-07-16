# copperline-docker

Run the [Copperline](https://github.com/LinuxJedi/Copperline) cycle-driven Amiga
emulator in your browser, served from a single Docker container.

Copperline is written in Rust and compiled to WebAssembly. This image builds the
WebAssembly bundle in a Rust build stage and serves the resulting static site with
nginx. It boots the bundled open-source **AROS** ROM out of the box — no Kickstart
needed — and configures a stock Amiga 500 (512K chip RAM + 512K trapdoor).

## Quick start

```sh
docker build -t copperline .
docker run --rm -p 8080:8080 copperline
```

Then open **<http://localhost:8080>** and click **Boot AROS**.

The container runs nginx as a non-root user and listens on port **8080** inside
(map it to any host port you like — `-p 8080:8080` above).

> Use `localhost` (or HTTPS), not a LAN IP — see [Audio](#audio-and-secure-context).

Or with Docker Compose:

```sh
docker compose up --build
```

## Loading your own disks and ROMs

The emulator runs entirely in your browser, so files reach it through the page, not
the server's filesystem. Two ways to supply them:

- **File pickers** — *Insert DF0…* for a disk image, *Load Kickstart…* for a ROM.
  These read a file straight off your machine.
- **A mounted `/files` volume** — mount a host directory into the container and load
  disks by URL, no picker needed:

  ```sh
  docker run --rm -p 8080:8080 \
    -v "$PWD/disks":/usr/share/nginx/html/files \
    copperline
  ```

  Drop `game.adf` into `./disks`, then either:
  - open `http://localhost:8080/?df0=files/game.adf` (bootable, shareable link), or
  - click **DF0 from URL** and enter `files/game.adf`, or
  - browse the listing at `http://localhost:8080/files/`.

  Supported disk formats (detected by content): ADF, ADZ, DMS, IPF, SCP — plain or
  gzip/zip-packed, up to 64 MiB. Disks are always write-protected in the browser.

**Kickstart note:** Copperline intentionally has no `?kick=` URL loader (Kickstart
ROMs are copyrighted, so sharing them by URL is unsupported). A Kickstart placed in
the volume must still be loaded through the **Load Kickstart…** picker.

## Audio and secure context

`AudioWorklet` requires a *secure context*: HTTPS **or** `localhost`. Over
`http://localhost:8080` audio works. Reaching the container over plain HTTP via a
LAN hostname/IP leaves audio suspended — the emulator still boots and runs, just
silently. For remote/LAN hosting, terminate TLS in front of the container (a reverse
proxy such as Caddy/Traefik, or an nginx TLS cert).

No COOP/COEP headers are needed: the build is single-threaded, so any static host
works.

## Building a different Copperline version

The Copperline git ref is a build argument. Because the browser frontend
(`crates/copperline-web`) was added to `main` *after* the v0.11.0 release, no
release tag contains it yet, so the default is pinned to a specific `main` commit
for reproducibility. Override it with a commit SHA, tag, or branch:

```sh
# Latest main
docker build --build-arg COPPERLINE_REF=main -t copperline .

# A specific commit or (once one exists) a release tag with the browser build
docker build --build-arg COPPERLINE_REF=<sha-or-tag> -t copperline .
```

(Or edit `COPPERLINE_REF` in `docker-compose.yml`.) The `wasm-bindgen` CLI version
is parsed from Copperline's own `Cargo.toml` during the build so it can never drift
from the crate.

## What's in the image

```
/usr/share/nginx/html/
├── index.html            # minimal page shell (this repo)
├── try.js                # emulator page glue (from Copperline)
├── audio-worklet.js      # audio output worklet (from Copperline)
├── pkg/                  # wasm-bindgen bundle (copperline_web.js + .wasm)
├── aros/                 # bundled open-source AROS ROMs + licence
└── files/                # VOLUME — your mounted disks/ROMs
```

## Licences

- **This project** — GNU GPL v3 or later (`GPL-3.0-or-later`), matching Copperline;
  see [`LICENSE`](LICENSE).
- **Copperline** (the emulator built into the image) — GNU GPL v3 or later.
- **AROS ROMs** — AROS Public License (see `aros/LICENSE` in the running container,
  at `/aros/LICENSE`).
- No Kickstart ROM is included; supply your own dump.
