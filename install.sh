#!/usr/bin/env bash
set -euo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/yeags.gpu-monitor"
omarchy plugin validate "$source_dir/yeags.gpu-monitor"
if [[ -e "$plugin_dir" ]]; then
  backup_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugin-backups"
  mkdir -p -- "$backup_dir"
  cp -a -- "$plugin_dir" "$backup_dir/yeags.gpu-monitor.$(date +%s)"
fi
mkdir -p -- "$plugin_dir"
cp -a -- "$source_dir/yeags.gpu-monitor/." "$plugin_dir/"
omarchy-shell shell rescanPlugins
# Registry rescans are asynchronous; wait until the copied manifest is visible.
for attempt in {1..25}; do
  if omarchy plugin list --json | jq -e 'any(.[]; .id == "yeags.gpu-monitor")' >/dev/null; then
    config_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
    if [[ -f "$config_file" ]]; then
      cp -a -- "$config_file" "${config_file}.backup.$(date +%s)"
    fi
    omarchy plugin enable yeags.gpu-monitor --section right --before omarchy.monitor
    exit 0
  fi
  sleep 0.2
done
echo "Plugin copied, but the shell registry did not discover it. Retry after checking the shell." >&2
exit 1
