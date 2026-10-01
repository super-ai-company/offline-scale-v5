"""Audit actual 64-bit ELF LOAD alignment in an APK or AAB; exit 1 if unsafe."""
import struct
import sys
import zipfile


def audit(path):
    failures = []
    checked = 0
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith('.so') or not any(
                '/'+abi+'/' in '/'+name for abi in ('arm64-v8a', 'x86_64')
            ):
                continue
            data = archive.read(name)
            checked += 1
            if data[:6] != b'\x7fELF\x02\x01':
                failures.append((name, 'not a supported ELF64 little-endian library'))
                continue
            offset = struct.unpack_from('<Q', data, 32)[0]
            entry_size, count = struct.unpack_from('<HH', data, 54)
            loads = []
            for index in range(count):
                at = offset + index * entry_size
                if struct.unpack_from('<I', data, at)[0] == 1:
                    alignment = struct.unpack_from('<Q', data, at + 48)[0]
                    file_offset, address = struct.unpack_from('<QQ', data, at + 8)
                    loads.append(alignment)
                    if alignment < 16384 or (address - file_offset) % 16384:
                        failures.append((name, f'incompatible LOAD alignment {alignment:#x}'))
                        break
            if not loads:
                failures.append((name, 'missing LOAD segments'))
    if not checked:
        raise ValueError('No 64-bit native libraries found')
    print(f'Checked {checked} 64-bit libraries; {len(failures)} failures')
    for name, reason in failures:
        print(f'FAIL {name}: {reason}')
    print('ELF alignment alone does not replace 16 KB runtime or signing validation.')
    return 1 if failures else 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('Usage: check_play_native.py APK_OR_AAB')
    sys.exit(audit(sys.argv[1]))
