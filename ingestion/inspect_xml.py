"""
Inspect XML - Build an Inventory of All Fields

Read saved API responses from /samples and lists every element/attribute that occurs, grouped by endpoint (plan, fchg, station).

Usage (from the repo root):
    python ingestion\inspect_xml.py samples\*.xml           # All samples
    python ingestion\inspect_xml.py samples\plan_*.xml      # Only \plan samples
    python ingestion\inspect_xml.py samples\fchg_*.xml      # Only \fchg samples

How to read the output (this is what docs/DATA_DICTIONARY.md is based on):
    path        where the value sits, e.g. s/ar@pt = attribute pt of <ar> inside <s>
                (this is also how the parser later finds it: s.find("ar").get("pt"))
    count       how often the attribute occurs in all files
    % stops     count relative to the number of <s> stops
                if % stops < 100 %  -> field is optional -> column must allow NULL
    distinct    number of different values
                1       -> constant, maybe not worth a column
    examples    up to three different values -> decide the data type
                ("8 D-F" as platform -> TEXT, not INTEGER)
"""

import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from glob import glob
from pathlib import Path

MAX_EXAMPLES = 3

def walk(element, path, stats):
    """Recursively visit an element and all its children, recording every attribute."""
    for name, value in element.attrib.items():
        key = f"{path}@{name}" if path else f"@{name}"
        stats[key]["count"] += 1
        stats[key]["values"].add(value)

    for child in element:
        child_path = f"{path}/{child.tag}" if path else child.tag
        walk(child, child_path, stats)
  
def new_group():
    """Statistics for one endpoint: number of files, number of stops, attribute stats."""
    return {
        "files": 0,
        "stops": 0,
        "attrs": defaultdict(lambda: {"count": 0, "values": set()}),
    }
 
def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
 
    # cmd does not expand wildcards like *.xml itself, so Python does it
    files = sorted({f for pattern in sys.argv[1:] for f in glob(pattern)})
    if not files:
        sys.exit("No files found.")
 
    # group by endpoint = first part of the file name (plan_..., fchg_..., station_...)
    groups = defaultdict(new_group)

    for file in files:
        root = ET.parse(file).getroot()
        group = groups[Path(file).name.split("_")[0]]
        group["files"] += 1
        group["stops"] += len(root.findall("s"))
        walk(root, "", group["attrs"])   # root attributes appear as "@station" etc.
 
    for endpoint, group in sorted(groups.items()):
        stops = group["stops"]
        print(f"\n=== {endpoint}: {group['files']} file(s), {stops} <s> stops ===")
        print(f"{'path':<20}{'count':>7}{'% stops':>9}{'distinct':>10}   examples")
        print("-" * 90)

        for key in sorted(group["attrs"]):
            info = group["attrs"][key]

            # Root attributes (e.g. @station) occur once per file, a share makes no sense
            share = f"{100 * info['count'] / stops:.0f} %" if stops and not key.startswith("@") else "-"
            examples = " | ".join(v[:25] for v in sorted(info["values"])[:MAX_EXAMPLES])
            print(f"{key:<20}{info['count']:>7}{share:>9}{len(info['values']):>10}   {examples}")
 
if __name__ == "__main__":
    main()