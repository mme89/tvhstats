#!/usr/bin/env bash

mix deps.get
mix ecto.migrate

# Pre-install asset toolchains for dev watchers (avoid first-run missing binary issues)
mix sass.install --if-missing >/dev/null 2>&1 || true
mix tailwind.install --if-missing >/dev/null 2>&1 || true
mix esbuild.install --if-missing >/dev/null 2>&1 || true

exec "$@"