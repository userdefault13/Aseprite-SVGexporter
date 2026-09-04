# SVG Exporter for Aseprite

An Aseprite extension that exports sprite drawings to SVG format in three different ways:

1. **SVG File** - Exports as a standalone `.svg` file
2. **SVG Inline Code** - Generates SVG and offers Copy to Clipboard or Save SVG File
3. **SVG JSON** - Exports SVG layers as JSON, with Copy to Clipboard or Save JSON File

## Installation

### npm (download extension files)

```bash
npm install @userdefault13/aseprite-svg-exporter
```

Extension files are in `node_modules/@userdefault13/aseprite-svg-exporter/`. Zip them or point Aseprite at that folder.

### Package locally

1. Package the extension:
   ```bash
   ./package.sh
   ```

2. Install in Aseprite:
   - Open Aseprite
   - Go to `Edit > Preferences > Extensions`
   - Click `Add Extension` and select the `svg-exporter.aseprite-extension` file
   - Restart Aseprite

## Usage

After installation, open **File > SVG Exporter** (or run the extension from the File menu). The export dialog lets you:

- Preview the current frame
- Export the full sprite or a selection only
- Choose **SVG File**, **SVG Inline Code**, or **SVG JSON**

If no sprite is open, you can pick an `.ase` / `.aseprite` file from disk first.

## Features

- **Multi-layer support**: Handles all visible layers in your sprite
- Exports current frame of the active sprite
- **Selection export**: Crop to the active marquee from the export menu
- Supports transparency (alpha channel)
- Preserves exact pixel colors
- Optimized export with merged paths and hex-stable CSS classes
- Copy to clipboard functionality
- **SVG File Export**: Uses `<g>` elements with class names to group layers
- **JSON Export**: Array format with one SVG per layer, including layer names
- **Inline Export**: Full SVG with layer groups via Copy or Save (not shown in a text field — Aseprite dialog entries truncate at 4096 characters)

## Export Formats

### SVG File
Exports a complete SVG file where each layer is wrapped in a `<g>` element with a class name based on the layer name:
```svg
<svg>
  <g class="layer_name_1">
    <!-- layer 1 pixels -->
  </g>
  <g class="layer_name_2">
    <!-- layer 2 pixels -->
  </g>
</svg>
```

### JSON Export
Exports an array of layer objects, each containing the layer name and its SVG code:
```json
{
  "width": 32,
  "height": 32,
  "frame": 1,
  "layers": [
    {
      "name": "Background",
      "svg": "<svg>...</svg>"
    },
    {
      "name": "Foreground",
      "svg": "<svg>...</svg>"
    }
  ]
}
```

### Inline SVG
Generates the complete SVG with layer groups. Use **Copy to Clipboard** to paste into HTML/other documents, or **Save SVG File** to write the full output to disk. Leave **Wrap in markdown code fence** unchecked for plain SVG; enable it to copy as a ` ```svg ` block.

## How It Works

The extension converts each pixel in your sprite to an SVG `<rect>` element. The SVG maintains the exact dimensions and colors of your original sprite. 

**Multi-layer handling:**
- Only visible layers are exported
- Each layer is processed separately
- Layer names are used as class names in SVG files (sanitized for valid CSS class names)
- JSON exports include each layer as a separate entry in the layers array

## Notes

- Large sprites may generate large SVG files since each pixel becomes a rectangle
- The optimized export merges adjacent pixels into paths and assigns hex-stable CSS classes (e.g. `c4e4e8c`)
- Canonical Aavegotchi colors map to `.gotchi-primary`, `.gotchi-secondary`, and `.gotchi-cheek`
- Transparency is preserved using RGBA color values
- Inline and JSON dialogs do not show the full code in a text field (Aseprite caps entry widgets at 4096 characters); use Copy or Save for the complete payload

## Batch CLI (side-scroll library)

Headless export of Paarcel Aavegotchi aseprites → SVG JSON → `aavegotchi_side-scroll_*.json` (never writes `aavegotchi_db_*`):

```bash
# Export one collateral (default: amAAVE)
./batch-export.sh amAAVE

# Export all collaterals
./batch-export.sh --all

# Assemble library into Paarcel + Paaint JSONs/
python3 assemble-side-scroll-library.py amAAVE
# or: python3 assemble-side-scroll-library.py --all
```

Raw SVG-JSON lands in:
`Paarcel/Assets/Resources/Aavegotchi/JSONs/_side-scroll-raw/`

Assembled files:
- `aavegotchi_side-scroll_main.json`
- `aavegotchi_side-scroll_collaterals.json`
- `aavegotchi_side-scroll_eye_shapes_haunt{1,2}.json`
- `aavegotchi_side-scroll_base-{collateral}.json`

Single-file export:

```bash
aseprite -b \
  --script-param input=/path/file.aseprite \
  --script-param output=/path/out.svg.json \
  --script batch-export-cli.lua
```

## Publishing to npm

Store your npm automation token in abra (one-time):

```bash
abra set Aseprite-SVGexporter NPM_TOKEN
```

Publish:

```bash
npm run publish:npm
```


## Author

**Julius Wong** (userDef@ult) — [userdefault.dev](https://www.userdefault.dev) · [GitHub](https://github.com/userdefault13) · [X](https://x.com/userDefault_0x)

Freelance engineer working on AI agent orchestration, AI developer tooling, and Unity/WebGL
multiplayer games. Write-up of the game art pipeline work behind this project:
[userdefault.dev/work/aseprite-pixel-tools](https://www.userdefault.dev/work/aseprite-pixel-tools).

Available for freelance and contract work — [book a consult](https://www.userdefault.dev/hire),
or read more about [Unity & WebGL game development](https://www.userdefault.dev/services/unity-game-development).
