#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="/workspace/.godot-runtime"
mkdir -p "$runtime_dir/data" "$runtime_dir/config" "$runtime_dir/cache"
export XDG_DATA_HOME="$runtime_dir/data"
export XDG_CONFIG_HOME="$runtime_dir/config"
export XDG_CACHE_HOME="$runtime_dir/cache"
exec godot --path "$project_dir" "$@"
