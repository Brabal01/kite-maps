"""Regression test for a device-specific runtime reported before the general iOS runtime."""
import runpy
import unittest
from pathlib import Path

bootstrap = runpy.run_path(str(Path(__file__).with_name("boot-simulator.py")))
select_device = bootstrap["select_device"]
IPHONE = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
DUO = "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"


def runtime(version, suffix, phones, available=True):
    return {"version": version, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-" + suffix,
            "isAvailable": available,
            "supportedDeviceTypes": [{"name": name, "identifier": identifier} for name, identifier in phones]}


class SimulatorSelectionTests(unittest.TestCase):
    def testSkipsDeviceSpecificBuildWithSameVersion(self):
        restricted = runtime("27.2", "27-2-iPhone19-4", [("iPhone Duo", DUO)])
        general = runtime("27.2", "27-2", [("iPhone 17 Pro", IPHONE)])
        selected, phone = select_device({"runtimes": [restricted, general]})
        self.assertEqual(selected, general)
        self.assertEqual(phone, IPHONE)

    def testSelectsOlderCompatibleRuntimeIfNewestHasNoSupportedIPhone(self):
        unavailable = runtime("27.2", "27-2", [("iPhone 17 Pro", IPHONE)], available=False)
        restricted = runtime("27.1", "27-1", [("iPhone Duo", DUO)])
        general = runtime("27.0", "27-0", [("iPhone 17 Pro", IPHONE)])
        selected, phone = select_device({"runtimes": [unavailable, restricted, general]})
        self.assertEqual(selected, general)
        self.assertEqual(phone, IPHONE)


if __name__ == "__main__":
    unittest.main()
