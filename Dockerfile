# ── Stage 1: Build ────────────────────────────────────────────────────────
#
# The server depends on go_engine via a local path (../packages/go_engine).
# Both packages must be present in the build context, so this Dockerfile
# lives at the repo root and the build context is the entire monorepo.
#
# Render.com: set "Root Directory" to / (repo root) — Render will use this
# file automatically.  The PORT env var is injected by Render; the server
# reads it via Platform.environment['PORT'].
FROM dart:stable AS build

WORKDIR /app

# Copy the engine package first (path dependency of server/).
COPY packages/go_engine/ packages/go_engine/

# Copy server source and resolve its dependencies.
COPY server/ server/

WORKDIR /app/server
RUN dart pub get

# AOT-compile to a self-contained native binary (no Dart SDK needed at runtime).
RUN dart compile exe bin/server.dart -o /app/server_bin

# ── Stage 2: Minimal runtime image ────────────────────────────────────────
FROM debian:bookworm-slim

# ca-certificates is needed if the server ever makes outbound HTTPS calls.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/server_bin /usr/local/bin/gohackme_server

EXPOSE 8080
CMD ["/usr/local/bin/gohackme_server"]
