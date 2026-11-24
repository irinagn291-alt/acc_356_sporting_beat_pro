from pathlib import Path
import json
import shutil
import sys

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
names = sys.argv[3:]
attachments = [item for test in json.loads((source / "manifest.json").read_text())
               for item in test["attachments"] if not item["isAssociatedWithFailure"]]
index = {item["suggestedHumanReadableName"].split("_", 1)[0]: item["exportedFileName"]
         for item in attachments if item["exportedFileName"].endswith(".png")}
destination.mkdir(exist_ok=True, parents=True)
for name in names:
    file = source / index[name]
    shutil.copyfile(file, destination / (name + ".png"))
    print(f"{destination.name}/{name}.png ({file.stat().st_size} bytes)")
