import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

PLUGIN = Path(__file__).resolve().parents[1] / 'yeags.gpu-monitor'
spec = importlib.util.spec_from_file_location('metrics', PLUGIN / 'metrics.py')
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class TelemetryTests(unittest.TestCase):
    def test_nvidia_csv_and_unavailable_sensors(self):
        devices = metrics.parse_nvidia('GPU-123, "NVIDIA GPU, test", 00000000:01:00.0, 42, 1024, 12288, 61, 99.5, 250, 2200, 14001, [N/A]\ninvalid,row\n')
        self.assertEqual(len(devices), 1)
        gpu = devices[0]
        self.assertEqual(gpu['name'], 'NVIDIA GPU, test')
        self.assertEqual(gpu['pci'], '0000:01:00.0')
        self.assertEqual(gpu['utilization'], 42)
        self.assertEqual(gpu['power'], 99.5)
        self.assertIsNone(gpu['fan'])
        for value in ('NaN', 'inf', '-1', '[Not Supported]', ''):
            self.assertIsNone(metrics.number(value))

    def test_timeout_keeps_gpu_visible_and_reads_amd(self):
        with tempfile.TemporaryDirectory() as directory:
            drm = Path(directory)
            for card, vendor in [('card0', '0x1002'), ('card1', '0x10de')]:
                path = drm / ('0000:01:00.0' if vendor == '0x10de' else '0000:71:00.0')
                path.mkdir()
                (drm / card).mkdir()
                (drm / card / 'device').symlink_to(path)
                (path / 'vendor').write_text(vendor)
            amd = drm / 'card0' / 'device'
            (amd / 'gpu_busy_percent').write_text('23')
            (amd / 'mem_info_vram_used').write_text('104857600')
            sensor = amd / 'hwmon' / 'hwmon0'
            sensor.mkdir(parents=True)
            (sensor / 'temp1_input').write_text('51250')
            (sensor / 'power1_input').write_text('15000000')
            def timeout(*args, **kwargs):
                raise subprocess.TimeoutExpired('nvidia-smi', 3)
            devices = metrics.snapshot(drm, timeout)['devices']
            self.assertEqual(devices[0]['status'], 'nvidiaUnavailable')
            self.assertIsNone(devices[0]['utilization'])
            self.assertEqual(devices[1]['utilization'], 23)
            self.assertEqual(devices[1]['memoryUsed'], 100)
            self.assertEqual(devices[1]['temperature'], 51.25)
            self.assertEqual(devices[1]['power'], 15)

    def test_no_devices_and_missing_utility(self):
        def missing(*args, **kwargs):
            raise FileNotFoundError()
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(metrics.snapshot(Path(directory), missing), {'devices': []})

    def test_markup_names_preserved_only_for_plain_text_display(self):
        markup = '<img src="https://example.invalid/tracker">'
        gpu = metrics.parse_nvidia(f'GPU-1, {markup}, 00000000:01:00.0, 0, 0, 1, 30, 0, 1, 0, 0, 0')[0]
        self.assertEqual(gpu['name'], markup)
        qml = (PLUGIN / 'Widget.qml').read_text()
        # All plugin text uses this plain-text base. The shared tooltip only
        # receives a bundled catalog value, never device names or helper output.
        self.assertIn('component Label: Text {\n        textFormat: Text.PlainText', qml)
        self.assertEqual(qml.count('tooltipText:'), 1)
        self.assertIn('tooltipText: strings.t("title")', qml)
        self.assertNotIn('textRole:', qml)


if __name__ == '__main__':
    unittest.main()
