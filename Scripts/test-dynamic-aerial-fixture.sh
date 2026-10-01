#!/bin/bash
set -euo pipefail

# Synthetic regression fixtures only. Passing this test does not establish
# native macOS 27 provenance or prove Day/Night switching works.
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$temporary_directory/module-cache}"
xcrun swiftc "$repo_root/Scripts/capture-dynamic-aerial-fixture.swift" -o "$temporary_directory/capture"

python3 - "$temporary_directory" <<'PY'
import datetime
import pathlib
import plistlib
import sys

directory = pathlib.Path(sys.argv[1])
def add_unreachable_ascii_object(data, secret):
    """Add one unused object-table string to a small synthetic binary plist."""
    assert data.startswith(b"bplist00") and len(secret) < 15
    trailer = data[-32:]
    offset_size = trailer[6]
    object_count = int.from_bytes(trailer[8:16], "big")
    table_offset = int.from_bytes(trailer[24:32], "big")
    assert offset_size == 1 and table_offset + object_count == len(data) - 32
    extra = bytes([0x50 | len(secret)]) + secret.encode("ascii")
    new_table_offset = table_offset + len(extra)
    assert new_table_offset < 256
    new_trailer = bytearray(trailer)
    new_trailer[8:16] = (object_count + 1).to_bytes(8, "big")
    new_trailer[24:32] = new_table_offset.to_bytes(8, "big")
    return data[:table_offset] + extra + data[table_offset:-32] + bytes([table_offset]) + bytes(new_trailer)

configuration = add_unreachable_ascii_object(
    plistlib.dumps({"assetID": "00000000-0000-0000-0000-000000000001"}, fmt=plistlib.FMT_BINARY),
    "PRIVATELEAK",
)
assert plistlib.loads(configuration) == {"assetID": "00000000-0000-0000-0000-000000000001"}
options = plistlib.dumps({"values": {"aerialVariant": {"picker": {"_0": {"id": "automatic"}}}}}, fmt=plistlib.FMT_BINARY)

def write(name, root):
    (directory / name).write_bytes(plistlib.dumps(root, fmt=plistlib.FMT_BINARY))

def selection():
    return {
        "Type": "linked",
        "Linked": {
            "Content": {
                "Choices": [{"Configuration": configuration, "Files": [], "Provider": "com.apple.wallpaper.choice.aerials"}],
                "EncodedOptionValues": options,
                "Shuffle": "$null",
            },
            "LastSet": datetime.datetime(2026, 1, 1),
            "LastUse": datetime.datetime(2026, 1, 2),
        },
        "PrivatePath": "/Users/foreign/secret.mov",
    }

valid = {"AllSpacesAndDisplays": selection(), "Spaces": {"FOREIGN-SPACE": {"Path": "/Users/foreign/secret.mov"}}, "Foreign": "FOREIGN-SENTINEL"}
write("valid.plist", valid)

bad_provider = plistlib.loads(plistlib.dumps(valid))
bad_provider["AllSpacesAndDisplays"]["Linked"]["Content"]["Choices"][0]["Provider"] = "com.example.foreign"
write("bad-provider.plist", bad_provider)

multi = plistlib.loads(plistlib.dumps(valid))
multi["AllSpacesAndDisplays"]["Linked"]["Content"]["Choices"].append(dict(multi["AllSpacesAndDisplays"]["Linked"]["Content"]["Choices"][0]))
write("multi.plist", multi)

extra = plistlib.loads(plistlib.dumps(valid))
extra_options = {"values": {"aerialVariant": {"picker": {"_0": {"id": "automatic", "personal": "LEAK"}}}}}
extra["AllSpacesAndDisplays"]["Linked"]["Content"]["EncodedOptionValues"] = plistlib.dumps(extra_options, fmt=plistlib.FMT_BINARY)
write("extra-options.plist", extra)

manual = plistlib.loads(plistlib.dumps(valid))
manual["AllSpacesAndDisplays"]["Linked"]["Content"]["EncodedOptionValues"] = plistlib.dumps({"values": {"aerialVariant": {"picker": {"_0": {"id": "day"}}}}}, fmt=plistlib.FMT_BINARY)
write("non-automatic.plist", manual)

bad_config = plistlib.loads(plistlib.dumps(valid))
bad_config["AllSpacesAndDisplays"]["Linked"]["Content"]["Choices"][0]["Configuration"] = plistlib.dumps({"assetID": "not-a-uuid"}, fmt=plistlib.FMT_BINARY)
write("bad-configuration.plist", bad_config)

extra_content = plistlib.loads(plistlib.dumps(valid))
extra_content["AllSpacesAndDisplays"]["Linked"]["Content"]["Unexpected"] = "foreign"
write("extra-content.plist", extra_content)

malformed = plistlib.loads(plistlib.dumps(valid))
malformed["AllSpacesAndDisplays"]["Linked"]["Content"]["EncodedOptionValues"] = b"not-a-plist"
write("malformed-options.plist", malformed)
PY

before="$(shasum -a 256 "$temporary_directory/valid.plist")"
"$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/sanitized.plist"
after="$(shasum -a 256 "$temporary_directory/valid.plist")"
[[ "$before" == "$after" ]] || { echo "input changed" >&2; exit 1; }
[[ "$(stat -f %Lp "$temporary_directory/sanitized.plist")" == "600" ]] || { echo "output mode is not 0600" >&2; exit 1; }

python3 - "$temporary_directory" <<'PY'
import pathlib
import plistlib
import sys

directory = pathlib.Path(sys.argv[1])
source = plistlib.loads((directory / "valid.plist").read_bytes())
output_bytes = (directory / "sanitized.plist").read_bytes()
assert output_bytes.startswith(b"<?xml"), "output must be XML plist"
result = plistlib.loads(output_bytes)
assert set(result) == {"Type", "Linked"}
assert set(result["Linked"]) == {"Content"}
content = result["Linked"]["Content"]
assert set(content) == {"Choices", "EncodedOptionValues", "Shuffle"}
original_content = source["AllSpacesAndDisplays"]["Linked"]["Content"]
assert plistlib.loads(content["EncodedOptionValues"]) == plistlib.loads(original_content["EncodedOptionValues"])
assert plistlib.loads(content["Choices"][0]["Configuration"]) == plistlib.loads(original_content["Choices"][0]["Configuration"])
assert b"PRIVATELEAK" not in content["Choices"][0]["Configuration"]
assert content["Choices"][0]["Files"] == []
assert content["Choices"][0]["Provider"] == "com.apple.wallpaper.choice.aerials"
for forbidden in [b"FOREIGN-SENTINEL", b"FOREIGN-SPACE", b"/Users/foreign", b"LastSet", b"LastUse", b"2026-01"]:
    assert forbidden not in output_bytes, forbidden
PY

for name in bad-provider multi extra-options non-automatic bad-configuration extra-content malformed-options; do
    output="$temporary_directory/$name-output.plist"
    if "$temporary_directory/capture" --input "$temporary_directory/$name.plist" --output "$output" 2>"$temporary_directory/error.log"; then
        echo "unexpected success for $name" >&2
        exit 1
    fi
    [[ ! -e "$output" ]] || { echo "invalid input created output: $name" >&2; exit 1; }
done

if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/valid.plist" 2>"$temporary_directory/error.log"; then
    echo "same input/output unexpectedly succeeded" >&2
    exit 1
fi
[[ "$before" == "$(shasum -a 256 "$temporary_directory/valid.plist")" ]] || { echo "collision changed input" >&2; exit 1; }

ln "$temporary_directory/valid.plist" "$temporary_directory/input-hardlink.plist"
if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/input-hardlink.plist" 2>"$temporary_directory/error.log"; then
    echo "hardlink collision unexpectedly succeeded" >&2
    exit 1
fi
[[ "$before" == "$(shasum -a 256 "$temporary_directory/valid.plist")" ]] || { echo "hardlink collision changed input" >&2; exit 1; }

ln -s "$temporary_directory/valid.plist" "$temporary_directory/input-symlink.plist"
if "$temporary_directory/capture" --input "$temporary_directory/input-symlink.plist" --output "$temporary_directory/symlink-input-output.plist" 2>"$temporary_directory/error.log"; then
    echo "symlink input unexpectedly succeeded" >&2
    exit 1
fi
[[ ! -e "$temporary_directory/symlink-input-output.plist" ]] || { echo "symlink input created output" >&2; exit 1; }

mkfifo "$temporary_directory/input-fifo.plist"
if "$temporary_directory/capture" --input "$temporary_directory/input-fifo.plist" --output "$temporary_directory/fifo-input-output.plist" 2>"$temporary_directory/error.log"; then
    echo "FIFO input unexpectedly succeeded" >&2
    exit 1
fi
[[ ! -e "$temporary_directory/fifo-input-output.plist" ]] || { echo "FIFO input created output" >&2; exit 1; }

if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/sanitized.plist" 2>"$temporary_directory/error.log"; then
    echo "existing output unexpectedly overwritten" >&2
    exit 1
fi

ln -s "$temporary_directory/sanitized.plist" "$temporary_directory/output-symlink.plist"
if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/output-symlink.plist" 2>"$temporary_directory/error.log"; then
    echo "existing output symlink unexpectedly followed" >&2
    exit 1
fi
ln -s "$temporary_directory/no-target.plist" "$temporary_directory/output-dangling.plist"
if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/output-dangling.plist" 2>"$temporary_directory/error.log"; then
    echo "dangling output symlink unexpectedly followed" >&2
    exit 1
fi
[[ ! -e "$temporary_directory/no-target.plist" ]] || { echo "dangling symlink target created" >&2; exit 1; }

if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" 2>"$temporary_directory/error.log"; then
    echo "missing output argument unexpectedly accepted" >&2
    exit 1
fi
if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/extra-argument.plist" ignored 2>"$temporary_directory/error.log"; then
    echo "extra argument unexpectedly accepted" >&2
    exit 1
fi
[[ ! -e "$temporary_directory/extra-argument.plist" ]] || { echo "invalid CLI created output" >&2; exit 1; }

if "$temporary_directory/capture" --input "$temporary_directory/valid.plist" --output "$temporary_directory/missing-parent/result.plist" 2>"$temporary_directory/error.log"; then
    echo "missing parent unexpectedly created" >&2
    exit 1
fi
[[ ! -e "$temporary_directory/missing-parent" ]] || { echo "output parent was created" >&2; exit 1; }

echo "Synthetic capture helper smoke test passed"
