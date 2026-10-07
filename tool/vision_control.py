#!/usr/bin/env python3
"""Isolated debug app control; requires explicit device and JSON input, no secrets."""
import argparse
import json
import subprocess
import sys
import time
import uuid

PACKAGE = "com.vdamov3.cashier_trae.visiondev"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--serial", required=True, help="Explicit Android scale ADB serial")
parser.add_argument("--json", action="store_true", help="Always emits structured JSON")
parser.add_argument("--timeout", type=float, default=30)
args = parser.parse_args()

def adb(*command, data=None):
    return subprocess.run(["adb", "-s", args.serial, *command], input=data,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)

try:
    request = json.load(sys.stdin)
    if not isinstance(request, dict) or not isinstance(request.get("action"), str):
        raise ValueError("Expected a JSON object with action")
    request["request_id"] = str(uuid.uuid4())
    encoded = json.dumps(request, allow_nan=False).encode()
    if len(encoded) > 200000:
        raise ValueError("Request too large")
    # Fixed paths and package; JSON travels through stdin, never shell interpolation.
    adb("shell", "run-as", PACKAGE, "sh", "-c",
        "'mkdir -p files/vision-diagnostics; cat > files/vision-diagnostics/request.tmp; mv files/vision-diagnostics/request.tmp files/vision-diagnostics/request.json'", data=encoded)
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            result = adb("shell", "run-as", PACKAGE, "cat", "files/vision-diagnostics/response.json")
            response = json.loads(result.stdout)
            if response.get("request_id") == request["request_id"]:
                print(json.dumps(response, ensure_ascii=False))
                sys.exit(1 if response.get("code") in {"command_failed", "invalid_action", "outcome_unknown"} else 0)
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(.3)
    print(json.dumps({"code": "timeout", "request_id": request["request_id"],
                      "detail": "No matching reply; do not blindly retry capture_sample. Check app state."}))
    sys.exit(1)
except (ValueError, OSError, subprocess.CalledProcessError) as error:
    print(json.dumps({"code": "transport_or_request_error", "detail": str(error)}))
    sys.exit(1)
