#!/usr/bin/env bash
# Sends this Mac's API keys to Parallax running on a headset or simulator, so
# nothing has to be typed on a floating keyboard.
#
#   scripts/send-keys.sh <port> [code]
#
# The port and the code are shown in Parallax under Settings › From your Mac.
# Keys are read from the login Keychain and never printed.
set -euo pipefail

port="${1:-}"
code="${2:-}"
if [ -z "$port" ]; then
  echo "usage: scripts/send-keys.sh <port shown in the app> [code]" >&2
  exit 64
fi
if [ -z "$code" ]; then
  read -r -p "Code shown in Parallax: " code
fi

: "${ANTHROPIC_KEY_SERVICE:=claude-autonomous:ANTHROPIC_API_KEY}"
: "${GEMINI_KEY_SERVICE:=claude-autonomous:GEMINI_API_KEY}"

python3 - "$port" "$code" "$ANTHROPIC_KEY_SERVICE" "$GEMINI_KEY_SERVICE" <<'PY'
import json
import re
import socket
import subprocess
import sys

port, code, anthropic_service, gemini_service = sys.argv[1:5]


def keychain(service: str) -> str:
    """Read a password without ever echoing it."""
    try:
        return subprocess.run(
            ["security", "find-generic-password", "-s", service, "-w"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return ""


def discover() -> str:
    """Resolve the headset over Bonjour; fall back to this Mac (simulator)."""
    try:
        browse = subprocess.run(
            ["dns-sd", "-t", "4", "-B", "_parallax._tcp"],
            capture_output=True, text=True,
        )
    except FileNotFoundError:
        return "127.0.0.1"
    if "Parallax" not in browse.stdout:
        return "127.0.0.1"
    resolve = subprocess.run(
        ["dns-sd", "-t", "4", "-L", "Parallax", "_parallax._tcp"],
        capture_output=True, text=True,
    )
    match = re.search(r"can be reached at (\S+):", resolve.stdout)
    return match.group(1).rstrip(".") + "." if match else "127.0.0.1"


keys = {}
for provider, service in (("claude", anthropic_service), ("gemini", gemini_service)):
    value = keychain(service)
    if value:
        keys[provider] = value
    else:
        print(f"no key in the Keychain under {service} — skipping {provider}")

if not keys:
    print("nothing to send")
    sys.exit(1)

host = discover()
payload = json.dumps({"code": code, "keys": keys}) + "\n"

with socket.create_connection((host, int(port)), timeout=10) as sock:
    sock.sendall(payload.encode())
    answer = sock.recv(4096).decode().strip()

print(f"{host}:{port} -> {answer}")
sys.exit(0 if '"ok":true' in answer.replace(" ", "") else 1)
PY
