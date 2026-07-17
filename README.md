# copperline-docker

Run the [Copperline](https://github.com/LinuxJedi/Copperline) cycle-driven Amiga
emulator in your browser, served from a single Docker container.

Copperline is written in Rust and compiled to WebAssembly. This image builds the
WebAssembly bundle in a Rust build stage and serves the resulting static site with
nginx. It boots the bundled open-source **AROS** ROM out of the box — no Kickstart
needed — and configures a stock Amiga 500 (512K chip RAM + 512K trapdoor).

## Quick start

Pull the pre-built multi-arch image (linux/amd64 + linux/arm64) from GHCR:

```sh
docker run --rm -p 8080:8080 ghcr.io/sidick/copperline:latest
```

Or build it yourself:

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
the server's filesystem. There are three ways to supply your own files, covered
below with `docker` and `docker compose` examples.

### Your own disks — mount them into `/files`

Put your disk images on the host and mount that directory at
`/usr/share/nginx/html/files`; nginx serves it, and the emulator loads disks from it
by URL — no file picker needed.

Create a `disks/` directory and drop `game.adf` into it, then:

```sh
# docker
docker run --rm -p 8080:8080 \
  -v "$PWD/disks":/usr/share/nginx/html/files:ro \
  ghcr.io/sidick/copperline:latest
```

```yaml
# docker-compose.yml (the bundled compose file already does this)
services:
  copperline:
    image: ghcr.io/sidick/copperline:latest
    ports:
      - "8080:8080"
    volumes:
      - ./disks:/usr/share/nginx/html/files:ro
```

```sh
docker compose up
```

Then load the disk any of these ways:
- open `http://localhost:8080/?df0=files/game.adf` (a bootable, shareable link), or
- click **DF0 from URL** and enter `files/game.adf`, or
- browse the listing at `http://localhost:8080/files/`.

Supported formats (detected by content): ADF, ADZ, DMS, IPF, SCP — plain or
gzip/zip-packed, up to 64 MiB. Disks are always write-protected in the browser.

### Your own Kickstart

Put your Kickstart on the host and mount it into `/files` just like a disk, then load
it with the **same-origin** `?kick=` page parameter:

```sh
# docker — mount a directory holding kick13.rom (and any disks)
docker run --rm -p 8080:8080 \
  -v "$PWD/files":/usr/share/nginx/html/files:ro \
  ghcr.io/sidick/copperline:latest
```

Then open `http://localhost:8080/?kick=files/kick13.rom` — the Boot button relabels
to your ROM and boots it. You can combine it with a disk in one URL:
`?kick=files/kick13.rom&df0=files/game.adf`. There's also a **Kickstart from URL**
button on the page that prompts for a same-origin path.

`?kick=` is deliberately **same-origin only** (it can only fetch ROMs the container
already serves — copyrighted images can't be pulled from elsewhere), http(s) only,
and capped at 4 MiB; the core validates the 256/512 KiB ROM size.

You can also load a ROM straight from your machine without mounting anything — click
**Load Kickstart…** and choose your `.rom`, or drag a `.rom` onto the page. Either
way the ROM stays local to your browser and is never uploaded; both work before or
after boot (a pre-boot choice is applied when the machine starts).

### Replace the built-in boot ROM (advanced)

The **Boot AROS** button boots whatever the image serves at
`aros/aros-amiga-m68k-rom.bin` (main, `$F80000`) and `aros/aros-amiga-m68k-ext.bin`
(extended, `$E00000`). Mount your own **matched pair** over both files to change what
the button boots — both are fetched and required:

```sh
# docker — e.g. swap in a different AROS build
docker run --rm -p 8080:8080 \
  -v "$PWD/rom/my-rom.bin":/usr/share/nginx/html/aros/aros-amiga-m68k-rom.bin:ro \
  -v "$PWD/rom/my-ext.bin":/usr/share/nginx/html/aros/aros-amiga-m68k-ext.bin:ro \
  ghcr.io/sidick/copperline:latest
```

```yaml
# docker-compose.yml
services:
  copperline:
    image: ghcr.io/sidick/copperline:latest
    ports:
      - "8080:8080"
    volumes:
      - ./rom/my-rom.bin:/usr/share/nginx/html/aros/aros-amiga-m68k-rom.bin:ro
      - ./rom/my-ext.bin:/usr/share/nginx/html/aros/aros-amiga-m68k-ext.bin:ro
```

This is meant for swapping in an alternative **AROS** build, which ships as a
matched main + extended ROM pair. A stock Amiga Kickstart is a single ROM with no
extended half, so it does not fit this two-file boot path — use the **Load
Kickstart…** picker above for those.

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

## Publishing to GHCR

The [`Publish container image`](.github/workflows/publish-image.yml) workflow builds
a multi-arch (`linux/amd64` + `linux/arm64`) image and pushes it to
`ghcr.io/<owner>/<repo>`. It is **manually triggered**: in the repo, go to
**Actions → Publish container image → Run workflow** and optionally set:

- `copperline_ref` — the Copperline commit SHA, tag, or branch to build.
- `tag` — the image tag to publish (default `latest`); a `sha-<commit>` tag is
  always added as well.

It authenticates with the built-in `GITHUB_TOKEN` (no secrets to configure) and
caches the Rust build between runs. The Dockerfile's build stage is pinned to
`$BUILDPLATFORM`, so the architecture-independent wasm build compiles once on the
native runner instead of being emulated under QEMU for each target arch.

The published package starts **private** — make it public under the repo's
**Packages** settings if you want unauthenticated `docker pull`s.

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
