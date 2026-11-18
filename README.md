# Wilderland

An iPhone app that identifies wildlife by sound — frogs and toads, crickets, katydids and cicadas, coyotes, wolves, squirrels, elk and other mammals, plus birds — entirely on the phone.

## How it works

| Piece | What it does | Source | License |
|---|---|---|---|
| `perch_v2_f16.onnx` (205 MB) | Scores 5-second windows of 32 kHz audio against 14,795 classes: about 10,300 birds, 2,100 insects, 1,250 amphibians, 660 mammals, 70 reptiles | [Perch 2.0](https://huggingface.co/cgeorgiaw/Perch), Google DeepMind; ONNX conversion from [justinchuby/Perch-onnx](https://huggingface.co/justinchuby/Perch-onnx) | Apache 2.0 |
| `geomodel.onnx` (14 MB) | Says which species occur at a latitude/longitude and week of year | [BirdNET geomodel](https://github.com/birdnet-team/geomodel) | CC BY-SA 4.0 (weights) |
| `species.json` | Common names, animal groups, taxonomy and coarse ranges for species the geomodel doesn't cover | [iNaturalist](https://www.inaturalist.org) taxonomy export and observations API | — |

Audio and location never leave the phone. Inference runs through [ONNX Runtime](https://onnxruntime.ai).

## Layout

- `Core/` — Swift package with all identification logic (`WilderCore`) and `wilder-cli`, a Mac command-line tester that runs the same code over audio files.
- `App/` — the SwiftUI iPhone app. `App/Resources/` holds the models and catalog.
- `scripts/` — Python used to build the files in `App/Resources/`.
- `project.yml` — [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec; run `xcodegen generate` after adding or removing files.

## Getting the model

`perch_v2_f16.onnx` is too large for the git repository, so it's attached to the [latest release](../../releases/latest) instead. After cloning, download it into `App/Resources/`:

```bash
scripts/fetch_model.sh
```

To rebuild it yourself instead, download the float32 model from [justinchuby/Perch-onnx](https://huggingface.co/justinchuby/Perch-onnx) and run `python scripts/shrink.py <downloaded>.onnx App/Resources/perch_v2_f16.onnx`.

## Running on your iPhone

1. In Xcode, install the iOS platform if it isn't already (Settings › Components).
2. Open `Wilderland.xcodeproj`, select the Wilderland target › Signing & Capabilities, and choose your team.
3. Plug in the phone, pick it as the run destination, and press Run.

## Testing identification on the Mac

```bash
cd Core && swift build -c release
.build/release/wilder-cli ../App/Resources --lat 44.06 --lon -121.3 --month 6 recording.m4a
```

A file named `Genus_species_N.wav` is also scored against that name.

## What to expect

Perch's scores are uncalibrated, so matches are graded Possible / Likely / Strong rather than given a percentage. Loud, distinctive callers (coyotes, chorus frogs, toads, field and tree crickets, cicadas, squirrels) identify well. Elk bugles were missed in testing, and deer are rarely identifiable by sound. Close relatives that sound alike are often confused, so treat a match as a strong hint to check against reference recordings.
