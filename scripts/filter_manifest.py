#!/usr/bin/env python3
"""
filter_manifest.py

Removes metadata types listed in manifest/excluded-metadata.txt from an
auto-generated package.xml (used for --retrieve_mode full).

Why this exists: `sf project generate manifest --from-org` lists EVERY
metadata type present in the org, including things you almost never want
an automated pipeline touching unattended (Profile, PermissionSet sharing,
security settings, etc). This script trims those out before retrieve/deploy
run against the filtered manifest.

Usage:
    python3 scripts/filter_manifest.py manifest/package-full.xml manifest/excluded-metadata.txt
"""
import sys
import xml.etree.ElementTree as ET

NS = "http://soap.sforce.com/2006/04/metadata"
ET.register_namespace("", NS)


def load_excluded(path):
    """
    Returns two sets:
      whole_types    -> type names to remove entirely
      member_excludes -> set of (type_name, member_name) tuples to remove individually
    Lines with just "TypeName" exclude the whole type.
    Lines with "TypeName:MemberName" exclude only that one member.
    """
    whole_types = set()
    member_excludes = set()
    try:
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if ":" in line:
                    type_name, member_name = line.split(":", 1)
                    member_excludes.add((type_name.strip(), member_name.strip()))
                else:
                    whole_types.add(line)
    except FileNotFoundError:
        print(f"No exclusion file found at {path}, skipping filter.")
    return whole_types, member_excludes


def filter_manifest(manifest_path, whole_types, member_excludes):
    tree = ET.parse(manifest_path)
    root = tree.getroot()
    ns = {"sf": NS}

    kept_types, removed_types, removed_members = 0, 0, 0
    for types_el in list(root.findall("sf:types", ns)):
        name_el = types_el.find("sf:name", ns)
        type_name = name_el.text if name_el is not None else None

        if type_name in whole_types:
            root.remove(types_el)
            removed_types += 1
            continue

        # Remove individually-excluded members within this type
        for member_el in list(types_el.findall("sf:members", ns)):
            if (type_name, member_el.text) in member_excludes:
                types_el.remove(member_el)
                removed_members += 1

        # If every member was excluded, drop the now-empty <types> block entirely
        if len(types_el.findall("sf:members", ns)) == 0:
            root.remove(types_el)
            removed_types += 1
        else:
            kept_types += 1

    tree.write(manifest_path, encoding="UTF-8", xml_declaration=True)
    print(f"Manifest filtered: kept {kept_types} type(s), removed {removed_types} whole type(s), removed {removed_members} individual member(s).")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: filter_manifest.py <manifest.xml> <excluded-list.txt>")
        sys.exit(1)

    manifest_path, excluded_path = sys.argv[1], sys.argv[2]
    whole_types, member_excludes = load_excluded(excluded_path)
    if whole_types or member_excludes:
        filter_manifest(manifest_path, whole_types, member_excludes)
    else:
        print("Nothing to exclude, manifest left as-is.")
