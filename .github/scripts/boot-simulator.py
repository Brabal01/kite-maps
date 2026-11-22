"""Create and boot an unpaired iPhone in the runner's default device set."""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

TRANSIENT = re.compile(
    r"Invalid parameter not satisfying: devicePair|CoreSimulatorService connection became invalid"
    r"|Unable to boot device in current state: Booting"
)
LOG = Path("simulator-boot.log")


class SimulatorError(Exception):
    pass


def simctl(*arguments, timeout=45):
    cmd = ["xcrun", "simctl", *arguments]
    with LOG.open("a") as log:
        log.write(f"\n> {' '.join(cmd)}\n")
        try:
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, errors="replace", timeout=timeout)
        except subprocess.TimeoutExpired as error:
            log.write(error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes)
                      else error.stdout or "")
            raise SimulatorError(f"{arguments[0]} exceeded {timeout}s") from error
        log.write(result.stdout)
    if result.returncode:
        raise SimulatorError(result.stdout.strip())
    return result.stdout


def discard(udid):
    for operation in ("shutdown", "delete"):
        try:
            simctl(operation, udid)
        except SimulatorError as error:
            print(f"{operation} {udid}: {error}", file=sys.stderr)


def boot():
    for attempt in range(2):
        udid = None
        try:
            inventory = json.loads(simctl("list", "-j"))
            runtimes = [runtime for runtime in inventory["runtimes"]
                        if runtime.get("isAvailable") and ".SimRuntime.iOS-" in runtime["identifier"]
                        and tuple(map(int, runtime["version"].split("."))) >= (16, 2)]
            if not runtimes:
                raise SimulatorError("No available iOS simulator runtime >= 16.2")
            runtime = max(runtimes, key=lambda item: tuple(map(int, item["version"].split("."))))
            models = {item["name"]: item["identifier"] for item in inventory["devicetypes"]
                      if item["identifier"].startswith("com.apple.CoreSimulator.SimDeviceType.iPhone-")}
            model = next((models[name] for name in ("iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro")
                          if name in models), None)
            if model is None:
                raise SimulatorError("No supported iPhone device type was found")
            udid = simctl("create", f"Kite CI {os.environ.get('GITHUB_RUN_ID', os.getpid())}",
                          model, runtime["identifier"]).strip()
            if not re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
                raise SimulatorError(f"Unexpected simulator identifier: {udid}")
            simctl("boot", udid)
            simctl("bootstatus", udid, "-b", timeout=240)
            print(f"Booted {udid} on iOS {runtime['version']}")
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                output.write(f"udid={udid}\n")
            return
        except (SimulatorError, ValueError, KeyError) as error:
            if udid and re.fullmatch(r"[0-9A-Fa-f-]{36}", udid):
                discard(udid)
            if attempt == 0 and TRANSIENT.search(str(error)):
                print(f"Retrying transient CoreSimulator failure: {error}", file=sys.stderr)
                time.sleep(8)
                continue
            print(f"Simulator setup failed: {error}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    boot()
