#!/bin/bash
# Package the SVG Exporter extension for Aseprite

EXTENSION_NAME="svg-exporter.aseprite-extension"

# Remove old extension if it exists
if [ -f "$EXTENSION_NAME" ]; then
  rm "$EXTENSION_NAME"
  echo "Removed old extension file"
fi

# Create the extension zip file
zip -r "$EXTENSION_NAME" \
  package.json \
  svg-exporter.lua \
  svg-generator.lua \
  -x "*.DS_Store" "*__MACOSX*"

echo "Extension packaged successfully: $EXTENSION_NAME"
echo ""
echo "To install:"
echo "1. Open Aseprite"
echo "2. Go to Edit > Preferences > Extensions"
echo "3. Click 'Add Extension' and select $EXTENSION_NAME"
echo "4. Restart Aseprite"

