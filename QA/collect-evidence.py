"""Give XCTest attachments recognisable filenames and verify saved UI takes."""
from pathlib import Path
import array
import json
import shutil
import sys
import wave

root = Path(sys.argv[1])
manifest = root / "frames/manifest.json"
if manifest.exists():
    runs = json.loads(manifest.read_text())
    for run in runs:
        for item in run["attachments"]:
            source = manifest.parent / item["exportedFileName"]
            if source.suffix.lower() != ".png":
                continue
            name = item["suggestedHumanReadableName"].split("_", 1)[0] + ".png"
            destination = source.with_name(name)
            if destination != source and source.exists() and not destination.exists():
                source.rename(destination)
                item["exportedFileName"] = name
    manifest.write_text(json.dumps(runs, ensure_ascii=False, indent=2) + "\n")

normal = root / "saved/studio.json"
log = root / "test.log"
if normal.exists() and log.exists():
    lines = log.read_text().splitlines()
    trail = [line for line in lines if line.startswith(("CAMPAIGN ", "OFF THE RIM ", "RETRY ", "MARK ", "BROADCAST "))]
    orders = [line for line in trail if line.startswith("CAMPAIGN ")]
    if len(orders) == 16 and "BROADCAST all four cuts played to the end" in trail:
        save = json.loads(normal.read_text())
        assert len(set(save["completed"])) == 16 and len(save["takes"]) == 16 and len(save["picks"]) == 4
        assert any("** TEST SUCCEEDED **" in line for line in lines)
        report = [
            "Normal save. 16 orders progressed via XCTest UI touches on one isolated iPad.",
            *trail,
            "Verified after relaunch: 16 unique completions, 16 takes, 4 selected tapes."
        ]
        (root / "progression.txt").write_text("\n".join(report) + "\n")

path = root / "saved/qa-studio.json"
if not path.exists():
    sys.exit(0)
data = json.loads(path.read_text())
takes = data["takes"]
if len(takes) == 2 and all(take["clip"] == "net-goal" for take in takes):
    original, repair = takes
    assert original["strokes"][:2] == repair["strokes"][:2]
    assert data["completed"] == ["net-goal"]
    assert data["picks"]["football"] == repair["id"]
    names = ["original-take", "repaired-take"]
    waves = []
    for name, take in zip(names, takes):
        destination = root / (name + ".wav")
        shutil.copyfile(root / "saved" / (take["id"] + ".wav"), destination)
        with wave.open(str(destination)) as f:
            assert f.getframerate() == 32000 and f.getnframes() == 256000
            waves.append(f.readframes(f.getnframes()))
    lo, hi = round(3.9 * 32000) * 2, round(6.15 * 32000) * 2
    assert waves[0][:lo] == waves[1][:lo] and waves[0][hi:] == waves[1][hi:]
    assert waves[0][lo:hi] != waves[1][lo:hi]
    report = ["Source: UI saves made with XCTest gestures and exported through FoleySound.wave."]
    crowd = []
    for name, take, pcm in zip(names, takes, waves):
        times = {s["prop"]: s["time"] for s in take["strokes"]}
        at = times["card"]
        chunk = pcm[round((at + 0.06) * 32000) * 2:round((at + 0.23) * 32000) * 2]
        peak = max(abs(n) for n in array.array("h", chunk))
        assert peak > 1000
        crowd.append(at)
        line = ", ".join(f"{prop} {time:.4f} s" for prop, time in times.items())
        report.append(f"{name}: {line}, crowd peak {peak} PCM.")
    assert crowd[0] < 4.6 and abs(crowd[1] - 4.95) <= 0.35
    report += [
        "Contact and movement actions match exactly, including IDs, intensities and timestamps.",
        "The mixed PCM outside 3.90–6.15 s is byte-identical.",
        "Both versions saved, with the repaired take selected for the football programme."
    ]
    (root / "audio-verification.txt").write_text("\n".join(report) + "\n")
if "finish-straight" in data["completed"]:
    chosen = next(t for t in takes if t["id"] == data["picks"]["cycling"])
    assert all(p in {s["prop"] for s in chosen["strokes"]} for p in ["blocks","rubber","brush","bowl","card"])
    wav = root / "saved" / (chosen["id"] + ".wav")
    if wav.exists():
        shutil.copyfile(wav, root / "three-layer-final.wav")
