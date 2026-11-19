#!/usr/bin/env python3
"""Read-only GPU telemetry. One bounded JSON snapshot per invocation."""
import csv
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess

FIELDS = ['uuid', 'name', 'pci.bus_id', 'utilization.gpu', 'memory.used',
          'memory.total', 'temperature.gpu', 'power.draw', 'power.limit',
          'clocks.gr', 'clocks.mem', 'fan.speed']
KEYS = ['utilization', 'memoryUsed', 'memoryTotal', 'temperature', 'power',
        'powerLimit', 'coreClock', 'memoryClock', 'fan']


def number(value):
    try:
        result = float(value)
        return result if math.isfinite(result) and result >= 0 else None
    except (ValueError, TypeError):
        return None


def pci_id(value):
    # NVIDIA uses an eight-digit domain; sysfs uses four.
    match = re.fullmatch(r'(?:[0-9a-fA-F]{4})?([0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7])', value.strip())
    return match.group(1).lower() if match else value.strip().lower()


def parse_nvidia(output):
    devices = []
    for row in csv.reader(io.StringIO(output), skipinitialspace=True):
        if len(row) != len(FIELDS):
            continue
        row = [cell.strip() for cell in row]
        device = dict(zip(KEYS, map(number, row[3:])))
        device.update(id=row[0][:128], name=row[1][:160], pci=pci_id(row[2]),
                      vendor='NVIDIA', status='ok')
        devices.append(device)
    return devices[:16]


def read(path):
    try:
        return path.read_text()[:256].strip()
    except (OSError, UnicodeError):
        return ''


def scaled(path, divisor=1):
    value = number(read(path))
    return value / divisor if value is not None else None


def snapshot(drm=Path('/sys/class/drm'), runner=subprocess.run):
    devices = []
    nvidia_status = 'nvidiaUnavailable'
    try:
        result = runner(['nvidia-smi', '--query-gpu=' + ','.join(FIELDS),
                         '--format=csv,noheader,nounits'], capture_output=True,
                        text=True, timeout=3, env={**os.environ, 'LC_ALL': 'C'})
        if result.returncode == 0:
            devices = parse_nvidia(result.stdout)
    except FileNotFoundError:
        nvidia_status = 'nvidiaMissing'
    except (OSError, subprocess.TimeoutExpired):
        pass
    seen = {device['pci'] for device in devices}
    for card in sorted(drm.glob('card[0-9]*')):
        if not re.fullmatch(r'card\d+', card.name):
            continue
        path = card / 'device'
        vendor_id = read(path / 'vendor')
        if vendor_id not in ('0x1002', '0x10de', '0x8086'):
            continue
        pci = path.resolve().name
        if pci in seen:
            continue
        vendor = {'0x1002': 'AMD', '0x10de': 'NVIDIA', '0x8086': 'Intel'}[vendor_id]
        device = dict.fromkeys(KEYS)
        device.update(id=pci, pci=pci, vendor=vendor,
                      name=f'{vendor} · {pci}', status=nvidia_status if vendor == 'NVIDIA' else 'partial')
        if vendor != 'NVIDIA':
            device.update(utilization=scaled(path / 'gpu_busy_percent'),
                          memoryUsed=scaled(path / 'mem_info_vram_used', 1048576),
                          memoryTotal=scaled(path / 'mem_info_vram_total', 1048576))
            for hwmon in sorted((path / 'hwmon').glob('hwmon*')):
                device.update(temperature=scaled(hwmon / 'temp1_input', 1000),
                              power=scaled(hwmon / 'power1_average', 1000000),
                              powerLimit=scaled(hwmon / 'power1_cap', 1000000),
                              coreClock=scaled(hwmon / 'freq1_input', 1000000),
                              memoryClock=scaled(hwmon / 'freq2_input', 1000000))
                if device['power'] is None:
                    device['power'] = scaled(hwmon / 'power1_input', 1000000)
                break
        devices.append(device)
        seen.add(pci)
    devices.sort(key=lambda device: (device['vendor'] != 'NVIDIA', device['pci']))
    return {'devices': devices[:16]}


if __name__ == '__main__':
    print(json.dumps(snapshot(), allow_nan=False))
