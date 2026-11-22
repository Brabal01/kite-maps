"""Convert Natural Earth Admin 0 Countries (50m GeoJSON) into Kite's resources."""
import json
import sys
from pathlib import Path

source = json.loads(Path(sys.argv[1]).read_text())
output = Path("VelaCore/Sources/VelaCore/Resources")
groups = [[] for _ in range(4)]
sizes = [0] * len(groups)
for feature in source["features"]:
    geometry = feature["geometry"]
    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    country = feature["properties"]["ISO_A2_EH"]
    for polygon in polygons:
        rings = [[round(value, 5) for point in ring for value in point[:2]] for ring in polygon]
        group = sizes.index(min(sizes))
        groups[group].append([country, rings])
        sizes[group] += sum(map(len, rings))
for i, group in enumerate(groups):
    (output / f"country-boundaries-{i}.json").write_text(json.dumps(group, separators=(",", ":")) + "\n")
