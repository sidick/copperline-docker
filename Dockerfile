# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build the Copperline browser frontend (Rust -> wasm)
#
# Copperline's web crate compiles to wasm32-unknown-unknown and is then
# post-processed by wasm-bindgen. The build is single threaded, so the served
# site needs no COOP/COEP headers. Recipe mirrors the upstream wasm-demo.yml
# workflow. The full (non-slim) rust image is used so a C compiler is present
# for building wasm-bindgen-cli from source.
#
# Pinned to $BUILDPLATFORM: the output (/site -- wasm bundle, JS, HTML, ROMs)
# is architecture-independent, so on a multi-arch (buildx) build this stage
# compiles once on the native builder rather than being emulated under QEMU for
# each target. For a plain single-arch `docker build`, BUILDPLATFORM equals the
# host, so this is a no-op.
# ---------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM rust:1-bookworm AS build

# Copperline git ref to build: a commit SHA, tag, or branch. The browser
# frontend (crates/copperline-web) landed on main after the v0.11.0 release, so
# no release tag contains it yet; this is pinned to a specific main commit for
# reproducibility. Override with --build-arg COPPERLINE_REF=<sha|tag|branch>.
ARG COPPERLINE_REF=bc5bcbf166432d4e2b0d3b2a468f4443eefe5f6a

# 1. wasm target
RUN rustup target add wasm32-unknown-unknown

# 2. Source at the pinned ref. Use fetch-by-ref (not clone --branch) so a raw
#    commit SHA works too; GitHub allows fetching a reachable SHA directly.
RUN git init /src && cd /src && \
    git remote add origin https://github.com/LinuxJedi/Copperline.git && \
    git fetch --depth 1 origin "${COPPERLINE_REF}" && \
    git checkout FETCH_HEAD && \
    test -f crates/copperline-web/Cargo.toml

WORKDIR /src/crates/copperline-web

# 3. wasm-bindgen-cli must EXACTLY match the crate's pinned dependency, or the
#    generated bindings mismatch the runtime. Parse the version straight out of
#    Cargo.toml (same technique as the upstream workflow) so they cannot drift.
RUN V=$(sed -n 's/^wasm-bindgen = "=\(.*\)"$/\1/p' Cargo.toml) && \
    test -n "$V" && \
    cargo install wasm-bindgen-cli --version "$V" --locked

# 4. Build the wasm and run wasm-bindgen
RUN cargo build --release --target wasm32-unknown-unknown --locked && \
    wasm-bindgen --target web --out-dir pkg \
      target/wasm32-unknown-unknown/release/copperline_web.wasm && \
    test -s pkg/copperline_web_bg.wasm

# 5. Assemble the static site into /site
RUN mkdir -p /site/pkg /site/aros && \
    cp pkg/copperline_web.js pkg/copperline_web_bg.wasm /site/pkg/ && \
    cp www/try.js www/audio-worklet.js /site/ && \
    cp /src/assets/aros/aros-amiga-m68k-rom.bin \
       /src/assets/aros/aros-amiga-m68k-ext.bin \
       /src/assets/aros/LICENSE /src/assets/aros/ACKNOWLEDGEMENTS /site/aros/

# Our hand-written page shell (the Copperline repo ships no index.html).
COPY index.html /site/index.html

# ---------------------------------------------------------------------------
# Stage 2: serve the assembled site with nginx as a non-root user
#
# nginx-unprivileged runs as user "nginx" (UID 101) and its temp/pid paths are
# already set up for non-root operation; it listens on 8080 (a non-root process
# cannot bind port 80).
# ---------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:alpine

# Re-declared so the build ARG is visible in this stage for the labels below.
ARG COPPERLINE_REF=bc5bcbf166432d4e2b0d3b2a468f4443eefe5f6a

# OCI image metadata.
LABEL org.opencontainers.image.title="copperline-docker" \
      org.opencontainers.image.description="Copperline cycle-driven Amiga emulator, compiled to WebAssembly and served by nginx" \
      org.opencontainers.image.url="https://copperline.dev/" \
      org.opencontainers.image.source="https://github.com/LinuxJedi/Copperline" \
      org.opencontainers.image.documentation="https://github.com/LinuxJedi/Copperline/blob/main/docs/guide/browser.md" \
      org.opencontainers.image.licenses="GPL-3.0-or-later" \
      org.opencontainers.image.revision="${COPPERLINE_REF}"

# File operations need root; the base image's final USER is 101, so drop back
# to root for setup and hand ownership to the nginx user, then switch back.
USER root

COPY --from=build /site /usr/share/nginx/html
COPY nginx-default.conf /etc/nginx/conf.d/default.conf

# Drop zone for user-provided disks (and ROMs). Served by nginx under /files/
# so the emulator's same-origin "DF0 from URL" / ?df0= loader can fetch them.
# Owned by the nginx user so a bind-mounted host directory is readable.
RUN mkdir -p /usr/share/nginx/html/files && \
    chown -R nginx:nginx /usr/share/nginx/html

USER nginx
VOLUME /usr/share/nginx/html/files

EXPOSE 8080
