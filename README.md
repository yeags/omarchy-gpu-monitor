# GPU Monitor for Omarchy

A local, read-only Quickshell bar widget. Click **GPU** to switch between devices
and see utilization, VRAM, temperature, power draw/limit, core/memory clocks,
fan percentage, and the last 60 utilization samples. Missing sensors show **—**.
NVIDIA appears first by default. The panel follows the Omarchy theme and language
(English catalog included; other languages fall back to English).

## Install

Requires the Omarchy Quickshell desktop and Python 3. For NVIDIA telemetry,
`nvidia-smi` and a working matching NVIDIA driver are required. AMD uses readable
kernel sysfs sensors. Intel devices are detected but may have no exposed metrics.
No packages are installed, no network requests are made, and no elevated GPU
permissions are requested by the widget.

```bash
./install.sh
```

The installer copies `yeags.gpu-monitor` to your Omarchy user plugins, backs up
any existing copy, and enables it beside the system monitor. The shell hot-reloads.
You can also copy that folder manually, then run:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable yeags.gpu-monitor --section right
```

## Configuration

In `~/.config/omarchy/shell.json`, the widget's bar layout entry supports:

```json
{"id": "yeags.gpu-monitor", "interval": 2}
```

`interval` is the polling period in seconds (1–60; default 2). Samples are kept in
memory per GPU and per widget instance. A snapshot launches a short Python process;
NVIDIA queries time out after three seconds, and queries never overlap within an
instance. Activity history uses sample positions rather than a fixed time axis;
a timeout or manual refresh can change the time between samples. Missing readings
leave gaps. VRAM values are MiB; integrated GPU VRAM may represent only its reserved
memory, rather than all shared system RAM. Fan percentage is NVIDIA only.

If the NVIDIA driver cannot be queried, the GPU remains listed with an explicit
status. No fallback values are presented as NVIDIA performance. Run `nvidia-smi`
in your desktop terminal to investigate driver/device access separately.

## Validate

```bash
omarchy plugin validate ./yeags.gpu-monitor
python3 -m unittest discover -s tests -v
python3 yeags.gpu-monitor/metrics.py
```

## Remove

```bash
omarchy plugin disable yeags.gpu-monitor
```

Then remove the `yeags.gpu-monitor` folder from your user plugins directory.
Source remains in this project.
