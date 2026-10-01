#!/usr/bin/env python3
"""Verify payload, iOS deployment version, microphone keys and arm64 Mach-O."""
import argparse
import hashlib
import json
import plistlib
import struct
from pathlib import Path
from zipfile import ZipFile


def version(raw):
    return f'{raw >> 16}.{(raw >> 8) & 255}.{raw & 255}'


def inspect_macho(binary):
    assert binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected little-endian 64-bit Mach-O'
    fields = struct.unpack_from('<8I', binary)
    assert fields[1] == 0x0100000c, 'Expected arm64 device binary'
    offset = 32
    minimum = None
    linked = []
    for _ in range(fields[4]):
        command, size = struct.unpack_from('<2I', binary, offset)
        assert size >= 8 and offset + size <= len(binary), 'Invalid load command'
        if command == 0x32:  # LC_BUILD_VERSION
            platform, minos = struct.unpack_from('<2I', binary, offset + 8)
            assert platform == 2, 'Expected iOS device platform'
            minimum = version(minos)
        if command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            minimum = version(struct.unpack_from('<I', binary, offset + 8)[0])
        if command in (0xc, 0x80000018, 0x8000001f):
            start = offset + struct.unpack_from('<I', binary, offset + 8)[0]
            name = binary[start:offset + size].split(b'\0', 1)[0].decode()
            linked.append({'path': name, 'weak': command == 0x80000018})
        offset += size
    assert minimum is not None, 'Missing iOS deployment load command'
    assert int(minimum.split('.')[0]) <= 15, f'Binary requires iOS {minimum}'
    for library in linked:
        if '/Translation.framework/' in library['path']:
            assert library['weak'], 'Translation must be weak-linked for iOS 15'
    return {'architecture': 'arm64', 'minimum_binary_ios': minimum, 'libraries': linked}


def inspect_ipa(path):
    with ZipFile(path) as archive:
        names = archive.namelist()
        plist_paths = [name for name in names if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        assert len(plist_paths) == 1, 'Expected exactly one application payload'
        info = plistlib.loads(archive.read(plist_paths[0]))
        assert int(info['MinimumOSVersion'].split('.')[0]) <= 15, 'App requires newer than iOS 15'
        assert info.get('NSMicrophoneUsageDescription'), 'Missing microphone usage description'
        assert info.get('NSSpeechRecognitionUsageDescription'), 'Missing speech usage description'
        executable = plist_paths[0].rsplit('/', 1)[0] + '/' + info['CFBundleExecutable']
        macho = inspect_macho(archive.read(executable))
        assert not any('.env' in Path(name).name for name in names), 'Unexpected environment file'
    return {'file': str(path), 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
            'build': info['CFBundleVersion'], 'minimum_plist_ios': info['MinimumOSVersion'], **macho}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect_ipa(args.ipa), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
