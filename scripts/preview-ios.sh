#!/usr/bin/env bash
# Best-effort visual check only. The verified device IPA is already built.
set -u
cd "$(dirname "$0")/.." || exit 0
python3 - <<'PY'
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import time

output = Path('dist')
output.mkdir(exist_ok=True)
screenshot = output / 'preview-home.png'
status_file = output / 'preview-status.json'
# Leave enough headroom below the workflow's four-minute step timeout.
deadline = time.monotonic() + 225
chosen = None
booted_here = False

def run(args, limit, log=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError('Preview reached its bounded time budget')
    stream = open(log, 'w') if log else subprocess.PIPE
    process = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        result, _ = process.communicate(timeout=min(limit, remaining))
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise RuntimeError(f'{args[0]} {args[1] if len(args) > 1 else ""} timed out after at most {limit} seconds')
    finally:
        if log:
            stream.close()
    if process.returncode:
        detail = (result or '').strip()[-1800:]
        raise RuntimeError(f'Command exited {process.returncode}: {" ".join(args)}\n{detail}')
    return result or ''

def optional(args, limit=5):
    try:
        run(args, limit)
    except Exception as error:
        print(f'Preview optional setup skipped: {error}', flush=True)

try:
    if platform.system() != 'Darwin':
        raise RuntimeError('Simulator screenshot requires macOS and Xcode')
    available = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], 12))
    iphones = []
    for runtime, devices in available.get('devices', {}).items():
        for device in devices:
            if device.get('isAvailable', True) and device.get('name', '').startswith('iPhone'):
                device['runtime'] = runtime
                iphones.append(device)
    if not iphones:
        raise RuntimeError('No available iPhone simulator was found')
    def preference(device):
        name = device['name']
        return (0 if 'iPhone 16' in name else 1 if 'iPhone SE' in name else 2,
                0 if device.get('state') == 'Booted' else 1, name)
    chosen = sorted(iphones, key=preference)[0]
    udid = chosen['udid']
    print(f'Preview device: {chosen["name"]} ({chosen["runtime"]})', flush=True)
    run(['xcodebuild', '-project', 'ConversationTranslator.xcodeproj',
         '-scheme', 'ConversationTranslator', '-configuration', 'Debug',
         '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
         '-derivedDataPath', 'build-preview', 'CODE_SIGNING_ALLOWED=NO', 'build'],
        130, output / 'preview-build.log')
    app = Path('build-preview/Build/Products/Debug-iphonesimulator/ConversationTranslator.app')
    if not app.is_dir():
        raise RuntimeError('Simulator build did not produce the app')
    # Cap cold simulator startup at 100 seconds; the overall preview budget still applies.
    boot_deadline = time.monotonic() + 100
    if chosen.get('state') != 'Booted':
        run(['xcrun', 'simctl', 'boot', udid], 10)
        booted_here = True
    run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], max(1, boot_deadline - time.monotonic()))
    optional(['xcrun', 'simctl', 'ui', udid, 'appearance', 'light'])
    optional(['xcrun', 'simctl', 'status_bar', udid, 'override', '--time', '9:41',
              '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3',
              '--batteryState', 'charged', '--batteryLevel', '100'])
    run(['xcrun', 'simctl', 'install', udid, str(app)], 12)
    run(['xcrun', 'simctl', 'launch', '--terminate-running-process', udid,
         'local.conversation.translator'], 12)
    # Wait only for the first static home frame. Never grant or exercise microphone access.
    time.sleep(min(2, max(0, deadline - time.monotonic())))
    run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot)], 10)
    if not screenshot.is_file() or screenshot.stat().st_size == 0:
        raise RuntimeError('Simulator did not produce a screenshot')
    status_file.write_text(json.dumps({'success': True, 'device': chosen['name'],
                                      'runtime': chosen['runtime'], 'screenshot': str(screenshot)}, indent=2))
    print(f'PREVIEW SUCCESS: {screenshot} ({screenshot.stat().st_size} bytes)', flush=True)
except Exception as error:
    status_file.write_text(json.dumps({'success': False, 'error': str(error)}, indent=2))
    print(f'::warning::PREVIEW FAILED: {error}. The verified device IPA remains valid.', flush=True)
finally:
    if chosen and booted_here:
        optional(['xcrun', 'simctl', 'shutdown', chosen['udid']], 5)
PY
