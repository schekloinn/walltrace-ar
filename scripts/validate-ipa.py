import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def macho(data):
    magic, cpu, subtype, filetype, count, commands_size, flags, reserved = struct.unpack_from('<8I', data)
    require(magic == 0xFEEDFACF and cpu == 0x0100000C, 'Expected thin 64-bit arm64 Mach-O')
    offset = 32
    minimum = None
    signed = False
    entitlements = None
    for _ in range(count):
        command, size = struct.unpack_from('<2I', data, offset)
        require(size >= 8 and offset + size <= len(data), 'Invalid load command')
        if command == 0x32:
            platform, encoded = struct.unpack_from('<2I', data, offset + 8)
            require(platform == 2, 'Binary must target iOS devices, not Simulator')
            minimum = f'{encoded >> 16}.{(encoded >> 8) & 255}.{encoded & 255}'
        elif command == 0x25:
            encoded, = struct.unpack_from('<I', data, offset + 8)
            minimum = f'{encoded >> 16}.{(encoded >> 8) & 255}.{encoded & 255}'
        elif command in (0x21, 0x2C):
            encrypted, = struct.unpack_from('<I', data, offset + 16)
            require(encrypted == 0, 'Unexpected encrypted binary')
        elif command == 0x1D:
            start, length = struct.unpack_from('<2I', data, offset + 8)
            require(start + length <= len(data), 'Truncated signature')
            sig = data[start:start + length]
            sig_magic, sig_length, sig_count = struct.unpack_from('>3I', sig)
            require(sig_magic == 0xFADE0CC0 and sig_length <= length, 'Invalid signature superblob')
            for i in range(sig_count):
                slot, blob_offset = struct.unpack_from('>2I', sig, 12 + i * 8)
                blob_magic, blob_length = struct.unpack_from('>2I', sig, blob_offset)
                if slot == 0:
                    require(blob_magic == 0xFADE0C02, 'Missing CodeDirectory')
                    signed = True
                if slot == 5:
                    require(blob_magic == 0xFADE7171, 'Invalid XML entitlements')
                    entitlements = plistlib.loads(sig[blob_offset + 8:blob_offset + blob_length])
        offset += size
    require(signed, 'Missing code signature')
    require(minimum is not None and tuple(map(int, minimum.split('.'))) <= (15, 8, 7), 'Minimum iOS exceeds 15.8.7')
    require(entitlements is not None, 'Missing shared-container entitlements')
    require(entitlements.get('com.apple.security.application-groups') == ['group.local.puffline.shared'], 'Wrong shared group')
    require(not any(key in entitlements for key in ['platform-application', 'get-task-allow', 'com.apple.private.security.no-sandbox']), 'Unexpected privileged/debug entitlement')
    return {'architecture': 'arm64', 'platform': 'iOS', 'minimum_os': minimum, 'signed': signed, 'entitlements': entitlements}


ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    require(archive.testzip() is None, 'ZIP integrity failure')
    names = archive.namelist()
    require(all(name.startswith('Payload/') and '..' not in name.split('/') for name in names), 'Unexpected package paths')
    result = {}
    for label, folder, identifier in [
        ('app', 'Payload/Puffline.app/', 'local.puffline.app'),
        ('widget', 'Payload/Puffline.app/PlugIns/PufflineWidget.appex/', 'local.puffline.app.widget'),
    ]:
        info = plistlib.loads(archive.read(folder + 'Info.plist'))
        require(info['CFBundleIdentifier'] == identifier, 'Wrong bundle identifier')
        require(info['MinimumOSVersion'] == '15.0', 'Wrong deployment target')
        require(info['UIDeviceFamily'] == [1], 'Expected iPhone-only bundle')
        executable = archive.getinfo(folder + info['CFBundleExecutable'])
        require((executable.external_attr >> 16) & 0o111, 'Executable mode not retained')
        result[label] = macho(archive.read(executable))
        result[label]['bundle_id'] = identifier
        if label == 'app':
            schemes = [s for item in info['CFBundleURLTypes'] for s in item['CFBundleURLSchemes']]
            require('puffline' in schemes, 'Missing Shortcuts URL scheme')
            require(info['CFBundleDisplayName'] == 'Puffline', 'Wrong display name')
            require(info['CFBundleDevelopmentRegion'] == 'uk', 'Wrong app language')
        else:
            require(info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'Missing WidgetKit extension')
    result['sha256'] = hashlib.sha256(ipa.read_bytes()).hexdigest()
    result['bytes'] = ipa.stat().st_size
    result['files'] = len(names)
    result['physical_device_tested'] = False
    print(json.dumps(result, ensure_ascii=False, indent=2))
