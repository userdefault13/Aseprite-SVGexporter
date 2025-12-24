# SVG Exporter for Aseprite

An Aseprite extension that exports sprite drawings to SVG format in three different ways:

1. **SVG File** - Exports as a standalone `.svg` file
2. **SVG Inline Code** - Displays the SVG code in a dialog that can be copied to clipboard
3. **SVG JSON** - Exports the SVG code embedded in a JSON object, which can be saved as a file or copied

## Installation

1. Package the extension:
   ```bash
   zip -r svg-exporter.aseprite-extension package.json svg-exporter.lua svg-generator.lua
   ```

2. Install in Aseprite:
   - Open Aseprite
   - Go to `Edit > Preferences > Extensions`
   - Click `Add Extension` and select the `svg-exporter.aseprite-extension` file
   - Restart Aseprite

## Usage

After installation, you'll find the export options under:
- **File > Export > Export to SVG (Choose Format)** - Shows a menu to choose format
- **File > Export > SVG File** - Directly export to SVG file
- **File > Export > SVG Inline** - Export as inline SVG code
- **File > Export > SVG JSON** - Export as JSON with SVG code

## Features

- **Multi-layer support**: Handles all visible layers in your sprite
- Exports current frame of the active sprite
- Supports transparency (alpha channel)
- Preserves exact pixel colors
- Optimized export option (experimental)
- Copy to clipboard functionality
- **SVG File Export**: Uses `<g>` elements with class names to group layers
- **JSON Export**: Array format with one SVG per layer, including layer names
- **Inline Export**: Shows complete SVG with layer groups

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
Displays the complete SVG code with layer groups, which can be copied directly into HTML or other documents.

## How It Works

The extension converts each pixel in your sprite to an SVG `<rect>` element. The SVG maintains the exact dimensions and colors of your original sprite. 

**Multi-layer handling:**
- Only visible layers are exported
- Each layer is processed separately
- Layer names are used as class names in SVG files (sanitized for valid CSS class names)
- JSON exports include each layer as a separate entry in the layers array

## Notes

- Large sprites may generate large SVG files since each pixel becomes a rectangle
- The optimized export option attempts to group similar pixels (experimental)
- Transparency is preserved using RGBA color values

