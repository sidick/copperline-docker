# copperline-docker

Run the [Copperline](https://github.com/CopperlineHQ/Copperline) cycle-driven Amiga
emulator in your browser, served from a single Docker container.

Copperline is written in Rust and compiled to WebAssembly. This image builds the
WebAssembly bundle in a Rust build stage and serves the resulting static site with
nginx. It boots the bundled open-source **AROS** ROM out of the box — no Kickstart
needed — and configures a stock Amiga 500 (512K chip RAM + 512K trapdoor) by
default, switchable to an AGA Amiga 1200 from the page's machine selector.

> **Looking for the native build instead?** This image runs Copperline's
> in-browser WebAssembly build. A sibling image,
> [`ghcr.io/sidick/copperline-vnc`](https://github.com/sidick/amiga-emulation-docker),
> runs the full native Copperline application inside a container, streamed to
> your browser over KasmVNC, with persistent configuration and disk/ROM storage
> in a server-side volume. It is published (alongside an amiberry image) from
> the [amiga-emulation-docker](https://github.com/sidick/amiga-emulation-docker)
> repo and auto-tracks upstream Copperline releases.

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
- pick it from the page's **DF0 from list…** dropdown (mounted files appear
  there automatically), or
- open `http://localhost:8080/?df0=files/game.adf` (a bootable, shareable link), or
- click **DF0 from URL** and enter `files/game.adf`, or
- browse the listing at `http://localhost:8080/files/`.

Supported formats (detected by content): ADF, ADZ, DMS, IPF, SCP — plain or
gzip/zip-packed, up to 64 MiB. Disks are always write-protected in the browser.

#### Curating the disk list with `index.json`

By default the list dropdowns show every matching file in the folder, named
by filename. To curate — choose which files appear, give them friendly
names, or list files kept in subdirectories — drop an `index.json` next to
the disks; when present it replaces the scraped listing:

```json
[
  { "name": "Boulder Dash (1 disk)", "url": "boulderdash.adf" },
  { "name": "Lemmings — disk 1 of 2", "url": "lemmings/disk1.adf" },
  { "name": "Lemmings — disk 2 of 2", "url": "lemmings/disk2.adf" },
  "workbench13.adf"
]
```

Entries are either a filename (relative to `files/`) or a `{name, url}`
object; either way the list is shown alphabetically. One caveat: a manifest
is taken as-is — unlike a scraped listing it is *not* filtered by file
extension, and both dropdowns read the same folder, so a manifest's entries
appear in the disk **and** Kickstart lists alike. That makes `index.json`
a good fit for disk libraries (skip it, or accept the odd entry, if you
also serve ROMs); for separately curated disk and ROM lists, use a custom
shell whose two selects point `data-src` at different folders, each with
its own manifest.

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

## Configuring the page

The page's defaults — which machine boots, what's in the drive, whether it
powers on by itself — come from an optional `copperline.json` served next to
the page (the schema is
[upstream's](https://github.com/CopperlineHQ/Copperline/blob/main/docs/guide/browser.md)).
The container gives you two ways to provide it:

### Environment variables

Set any of these and the container writes `copperline.json` at startup:

| Variable                  | `copperline.json` key | Values                          |
| ------------------------- | --------------------- | ------------------------------- |
| `COPPERLINE_MACHINE`      | `machine`             | `A500` (default), `A1200`       |
| `COPPERLINE_DF0`          | `df0`                 | disk URL, e.g. `files/demo.adf` |
| `COPPERLINE_KICK`         | `kick`                | ROM path on this site, e.g. `files/kick31.rom` |
| `COPPERLINE_JOY`          | `joy`                 | `off`, `keys`, `cd32`, `touch`  |
| `COPPERLINE_FDSPEED`      | `floppy_speed`        | `100`, `200`, `400`, `800`, `turbo` |
| `COPPERLINE_FLOPPY_SOUNDS`| `floppy_sounds`       | `true`, `false`                 |
| `COPPERLINE_MONO_AUDIO`   | `mono_audio`          | `true`, `false`                 |
| `COPPERLINE_SERIAL_URL`   | `serial_url`          | WebSocket gateway URL           |
| `COPPERLINE_SERIAL_RAW`   | `serial_raw`          | `true`, `false`                 |
| `COPPERLINE_AUTOBOOT`     | `autoboot`            | `true`, `false`                 |

A demo kiosk that boots straight into a mounted disk:

```sh
docker run -p 8080:8080 \
  -v ./disks:/usr/share/nginx/html/files:ro \
  -e COPPERLINE_DF0=files/demo.adf \
  -e COPPERLINE_AUTOBOOT=true \
  ghcr.io/sidick/copperline
```

### Or mount the file

For full control (or to keep the config in version control), hand-write
`copperline.json` and mount it; it wins over the environment variables:

```sh
docker run -p 8080:8080 \
  -v ./copperline.json:/usr/share/nginx/html/copperline.json:ro \
  ghcr.io/sidick/copperline
```

### Precedence

1. Visitor's own changes on the page always win.
2. URL parameters (`?df0=`, `?kick=`, `?machine=`, `?joy=`, `?fdspeed=`)
   override the config per visit — handy for sharing links.
3. A bind-mounted `copperline.json` beats `COPPERLINE_*` variables.
4. With neither, the page runs its stock defaults (boot AROS on an A500).

## Making it yours

The page is meant to be rebranded and reskinned without forking the image.
Ready-to-adapt compose recipes for common setups (kiosk, disk shelf, BBS
terminal, reskin, custom shell, private hosting) live in
[`examples/`](examples/). Three layers, smallest hammer first:

### Title and subtitle

```sh
docker run -p 8080:8080 \
  -e COPPERLINE_TITLE="Dave's Amiga Corner" \
  -e COPPERLINE_SUBTITLE="Insert disk 1 of 11" \
  ghcr.io/sidick/copperline
```

Plain single-line text (it is HTML-escaped for you); sets the page heading,
the line under it, and the browser-tab title.

### Theme

The page's styling funnels through a handful of CSS custom properties, and
`theme.css` — an empty file in the stock image — loads last, so anything in
it wins. Mount your own to reskin:

```sh
docker run -p 8080:8080 \
  -v ./theme.css:/usr/share/nginx/html/theme.css:ro \
  ghcr.io/sidick/copperline
```

```css
/* theme.css — e.g. a light look with blue accents */
:root {
  --bg: #f2f4f8;        /* page background                       */
  --panel: #ffffff;     /* buttons, inputs, selects              */
  --line: #c3cadb;      /* borders                               */
  --ink: #17202f;       /* text                                  */
  --ink-mute: #5b6880;  /* secondary text, labels                */
  --accent: #2b6bd9;    /* highlights, primary button, links     */
}
```

Any further CSS works too — the element ids below are stable.

### Bring your own page

For a completely different page, mount your own `index.html` over the
shipped one; the JS glue (`try.js` and friends) is served by the image and
drives whatever elements it finds. The contract:

**Required** (try.js binds these unconditionally) — `#shell` (wrapper around
the display; fullscreen target), `#screen` (the canvas), `#overlay` (boot
overlay), `#boot` (boot button), `#load-status` (status line), `#stat`
(performance line), `#df0` and `#kick` (file inputs), `#eject`, `#reset`,
`#joy`, `#fullscreen`, `#vol` (range input).

**Optional** — everything else degrades gracefully or self-builds below the
canvas: `#df0url`/`#kickurl`, `#df0list`/`#kicklist` (self-filling lists;
`data-src` names the folder), `#machine`, `#floppy-speed`, `#pause`,
`#screenshot`, `#savestate`/`#loadstate`/`#quicksave`/`#quickload`,
`#ledbar`, `#floppy-sounds`, `#mono-audio`,
`#serial-url`/`#serial-connect`/`#serial-status`/`#serial-raw`,
`#bug-report`/`#bug-report-err`. The authoritative list lives in
[upstream's browser guide](https://github.com/CopperlineHQ/Copperline/blob/main/docs/guide/browser.md)
under "Optional page-shell hooks". A working minimal shell lives in
[`examples/custom-shell/`](examples/custom-shell/).

Note: `COPPERLINE_TITLE`/`COPPERLINE_SUBTITLE` only know the stock shell's
markers, so with your own page they are ignored (your page *is* the
branding); a read-only mount is detected and skipped cleanly.

## Publishing and access control

A note before putting a deployment on the open internet. The image itself
contains only open-source software — Copperline (GPL) and the bundled AROS
ROMs (AROS Public License); Kickstart ROMs and most Amiga software are
copyrighted, and anything in `/files` is supplied by whoever runs the
container. Because the emulator runs in the visitor's browser, **any file
the page can load, a visitor can download** — there is no way to make a
ROM usable by the emulator but not fetchable, and hiding the directory
listing doesn't change that. So on a publicly reachable deployment, treat
everything mounted into `/files` as published: either keep such
deployments private, or don't mount files you can't distribute.

Keeping it private means gating who can reach the site at all:
[`examples/private/`](examples/private/) shows both approaches — binding
the port to localhost/LAN (put a TLS-terminating reverse proxy with its
own auth in front to go further), and HTTP basic auth on the whole site
via a mounted nginx config.

## Audio and secure context

`AudioWorklet` requires a *secure context*: HTTPS **or** `localhost`. Over
`http://localhost:8080` audio works. Reaching the container over plain HTTP via a
LAN hostname/IP leaves audio suspended — the emulator still boots and runs, just
silently. For remote/LAN hosting, terminate TLS in front of the container (a reverse
proxy such as Caddy/Traefik, or an nginx TLS cert).

No COOP/COEP headers are needed: the build is single-threaded, so any static host
works.

## Building a different Copperline version

The Copperline git ref is a build argument, defaulting to the latest release tag
this repo has been updated for. Release tags from v0.12.0 onward contain the
browser frontend (`crates/copperline-web`). Override it with a commit SHA, tag,
or branch:

```sh
# Latest main
docker build --build-arg COPPERLINE_REF=main -t copperline .

# A specific commit or release tag (v0.12.0 or later)
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
├── serial-telnet.js      # telnet layer for the serial/BBS bridge (from Copperline)
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
