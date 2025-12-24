-- SVG Exporter for Aseprite
-- Exports sprite to SVG in multiple formats: inline code, JSON, or file

-- Extension version
local EXTENSION_VERSION = "1.0.1"

-- Load the SVG generator module
local function getScriptPath()
  -- Method 1: Use app.activeScript if available
  if app.activeScript and app.activeScript.path then
    return app.activeScript.path
  end
  
  -- Method 2: Use debug.getinfo to get the source file path
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source
    -- Remove '@' prefix if present (indicates file path)
    if string.sub(source, 1, 1) == "@" then
      source = string.sub(source, 2)
    end
    -- Get directory path
    local path = app.fs.filePath(source)
    if path and app.fs.isFile(app.fs.joinPath(path, "svg-generator.lua")) then
      return path
    end
  end
  
  -- Method 3: Try extensions folder
  local extensionsPath = app.fs.joinPath(app.fs.userConfigPath, "extensions")
  local possibleNames = { "svg-exporter", "sug-exporter" }
  
  for _, name in ipairs(possibleNames) do
    local extPath = app.fs.joinPath(extensionsPath, name)
    local genPath = app.fs.joinPath(extPath, "svg-generator.lua")
    if app.fs.isFile(genPath) then
      return extPath
    end
  end
  
  -- Method 4: Try user config as last resort
  return app.fs.userConfigPath
end

local scriptPath = getScriptPath()
local generatorPath = app.fs.joinPath(scriptPath, "svg-generator.lua")

-- Verify the file exists before trying to load it
local svgGenerator
if app.fs.isFile(generatorPath) then
  svgGenerator = dofile(generatorPath)
else
  -- If running as extension, defer error until command is called
  -- If running as script, show error immediately
  if not plugin then
    app.alert("Error: Could not find svg-generator.lua at:\n" .. generatorPath)
    return
  end
  -- For plugin mode, we'll handle the error in the onclick handler
  svgGenerator = nil
end

local function getOutputFilename(sprite)
  local baseName = sprite.filename
  if baseName and baseName ~= "" then
    -- Remove extension if present
    baseName = string.gsub(baseName, "%.%w+$", "")
  else
    baseName = "sprite"
  end
  return baseName
end

local function exportToFile(sprite, frameIndex)
  if not sprite then
    app.alert("No sprite is open")
    return
  end
  
  frameIndex = frameIndex or app.activeFrame.frameNumber
  
  local svgContent = svgGenerator.exportSpriteToSVG(sprite, frameIndex, false, true)
  if not svgContent then
    app.alert("Sprite is empty or has no visible pixels")
    return
  end
  
  local filename = getOutputFilename(sprite)
  local dlg = Dialog("Export SVG File")
  dlg:file{ 
    id="path",
    label="Save as:",
    filename=filename .. ".svg",
    save=true,
    filetypes={"svg"}
  }
  dlg:newrow()
  dlg:check{ 
    id="optimized",
    label="Optimized export",
    text="Use optimized format (experimental)",
    selected=false
  }
  dlg:newrow()
  dlg:check{ 
    id="cssClasses",
    label="CSS Classes",
    text="Use CSS classes with paths (optimized format)",
    selected=false
  }
  dlg:button{ id="ok", text="Export", onclick=function()
    local path = dlg.data.path
    local optimized = dlg.data.optimized
    local useCSSClasses = dlg.data.cssClasses
    
    -- Ensure we have a valid sprite (refresh from active sprite if needed)
    local currentSprite = sprite
    if not currentSprite or not currentSprite.isValid then
      currentSprite = app.activeSprite
    end
    
    if not currentSprite then
      app.alert("No sprite is available for export")
      dlg:close()
      return
    end
    
    -- Get current frame index
    local currentFrameIndex = frameIndex
    if app.activeFrame and app.activeFrame.sprite == currentSprite then
      currentFrameIndex = app.activeFrame.frameNumber
    end
    currentFrameIndex = currentFrameIndex or 1
    
    -- Use layer groups (true) for SVG file export
    svgContent = svgGenerator.exportSpriteToSVG(currentSprite, currentFrameIndex, optimized, true, useCSSClasses)
    
    -- Check if SVG is empty (just tags with no content)
    local isEmpty = false
    if svgContent then
      -- Check if SVG only contains opening and closing tags with nothing in between
      local content = string.gsub(svgContent, "<svg[^>]*>", "")
      content = string.gsub(content, "</svg>", "")
      content = string.gsub(content, "%s+", "")
      isEmpty = (content == "")
    end
    
    -- If CSS classes export failed or is empty, fall back to regular export
    if (not svgContent or svgContent == "" or isEmpty) and useCSSClasses then
      svgContent = svgGenerator.exportSpriteToSVG(currentSprite, currentFrameIndex, optimized, true, false)
      isEmpty = false
      if svgContent then
        local content = string.gsub(svgContent, "<svg[^>]*>", "")
        content = string.gsub(content, "</svg>", "")
        content = string.gsub(content, "%s+", "")
        isEmpty = (content == "")
      end
    end
    
    if not svgContent or svgContent == "" or isEmpty then
      -- Debug: Check what layers we actually found and test export directly
      local debugInfo = {}
      table.insert(debugInfo, "Sprite: " .. (currentSprite.filename or "Untitled"))
      table.insert(debugInfo, "Frame: " .. currentFrameIndex)
      table.insert(debugInfo, "Sprite Size: " .. currentSprite.width .. "x" .. currentSprite.height)
      table.insert(debugInfo, "Total Layers: " .. #currentSprite.layers)
      table.insert(debugInfo, "")
      
      -- Check each layer
      local visibleLayers = 0
      local layersWithCels = 0
      for i, layer in ipairs(currentSprite.layers) do
        if layer then
          local isVisible = layer.isVisible
          local isImage = layer.isImage
          if isVisible ~= false and isImage ~= false then
            visibleLayers = visibleLayers + 1
            local cel = layer:cel(currentFrameIndex) or layer:cel(1)
            if cel and cel.image then
              layersWithCels = layersWithCels + 1
              -- Check if image has pixels using the same method as export
              local hasPixels = false
              local celImage = cel.image
              local celWidth = celImage.width
              local celHeight = celImage.height
              local celX = cel.position.x
              local celY = cel.position.y
              local pixelCount = 0
              local samplePixels = {}
              local firstPixel = nil
              
              -- Check sprite color mode
              local colorMode = currentSprite.colorMode
              local colorModeStr = "unknown"
              if colorMode == ColorMode.RGB then
                colorModeStr = "RGB"
              elseif colorMode == ColorMode.INDEXED then
                colorModeStr = "INDEXED"
              elseif colorMode == ColorMode.GRAYSCALE then
                colorModeStr = "GRAYSCALE"
              end
              
              -- Use the same pixel detection as the export function
              for y = 0, celHeight - 1 do
                for x = 0, celWidth - 1 do
                  local pixel = celImage:getPixel(x, y)
                  
                  -- Extract RGBA using same method as getPixelColor
                  local byte0 = pixel & 0xFF
                  local byte1 = (pixel >> 8) & 0xFF
                  local byte2 = (pixel >> 16) & 0xFF
                  local byte3 = (pixel >> 24) & 0xFF
                  
                  -- Try app.pixelColor.rgba first
                  local r2, g2, b2, a2 = app.pixelColor.rgba(pixel)
                  
                  local r, g, b, a
                  if r2 and type(r2) == "number" and r2 >= 0 and r2 <= 255 and 
                     g2 and type(g2) == "number" and g2 >= 0 and g2 <= 255 and
                     b2 and type(b2) == "number" and b2 >= 0 and b2 <= 255 and
                     a2 and type(a2) == "number" and a2 >= 0 and a2 <= 255 then
                    r, g, b, a = r2, g2, b2, a2
                  else
                    -- Use ABGR format (swap R and B from ARGB)
                    a = byte3
                    r = byte0  -- Red from byte0
                    g = byte1
                    b = byte2  -- Blue from byte2
                  end
                  
                  -- Ensure all values are in valid range
                  r = math.max(0, math.min(255, r or 0))
                  g = math.max(0, math.min(255, g or 0))
                  b = math.max(0, math.min(255, b or 0))
                  a = math.max(0, math.min(255, a or 0))
                  
                  -- For indexed color mode, try to get the actual color from palette
                  if colorMode == ColorMode.INDEXED and a == 0 then
                    -- In indexed mode, get color index and look up in palette
                    local index = pixel & 0xFF  -- Lower 8 bits for index
                    if index ~= 0 then
                      local palette = currentSprite.palettes[1]
                      if palette then
                        local color = palette:getColor(index)
                        if color then
                          r = color.red
                          g = color.green
                          b = color.blue
                          a = color.alpha
                        end
                      end
                    end
                  end
                  
                  -- Store first pixel for debugging (even if transparent)
                  if not firstPixel then
                    firstPixel = string.format("first pixel (0,0): rgba(%d,%d,%d,%d), raw=%d", r, g, b, a, pixel)
                  end
                  
                  if a > 0 then
                    hasPixels = true
                    pixelCount = pixelCount + 1
                    -- Store first few non-transparent pixel samples for debugging
                    if #samplePixels < 3 then
                      table.insert(samplePixels, string.format("(%d,%d): rgba(%d,%d,%d,%d)", x, y, r, g, b, a))
                    end
                  end
                end
              end
              
              table.insert(debugInfo, string.format("  - Color Mode: %s", colorModeStr))
              
              local pixelInfo = string.format("pixels=%d", pixelCount)
              if firstPixel then
                pixelInfo = pixelInfo .. ", " .. firstPixel
              end
              if #samplePixels > 0 then
                pixelInfo = pixelInfo .. ", samples: " .. table.concat(samplePixels, ", ")
              end
              
              table.insert(debugInfo, string.format("Layer %d: %s", i, layer.name or "unnamed"))
              table.insert(debugInfo, string.format("  - Cel: %s", cel and "yes" or "no"))
              table.insert(debugInfo, string.format("  - Position: (%d, %d)", celX, celY))
              table.insert(debugInfo, string.format("  - Image Size: %dx%d", celWidth, celHeight))
              table.insert(debugInfo, string.format("  - Has Pixels: %s", hasPixels and "yes" or "no"))
              table.insert(debugInfo, string.format("  - Pixel Count: %d", pixelCount))
              if firstPixel then
                table.insert(debugInfo, string.format("  - %s", firstPixel))
              end
              if #samplePixels > 0 then
                table.insert(debugInfo, string.format("  - Sample pixels: %s", table.concat(samplePixels, ", ")))
              end
              table.insert(debugInfo, "")
            end
          end
        end
      end
      
      table.insert(debugInfo, "")
      table.insert(debugInfo, "Visible layers: " .. visibleLayers)
      table.insert(debugInfo, "Layers with cels: " .. layersWithCels)
      table.insert(debugInfo, "")
      table.insert(debugInfo, "Make sure at least one layer is visible and contains pixels.")
      table.insert(debugInfo, "")
      table.insert(debugInfo, "SVG Exporter v" .. EXTENSION_VERSION)
      
      app.alert(table.concat(debugInfo, "\n"))
      return
    end
    
    local file = io.open(path, "w")
    if file then
      file:write(svgContent)
      file:close()
      app.alert("SVG exported successfully to:\n" .. path)
    else
      app.alert("Error: Could not write file")
    end
    dlg:close()
  end}
  dlg:newrow()
  dlg:label{ 
    text="SVG Exporter v" .. EXTENSION_VERSION,
    focus=false
  }
  dlg:button{ id="cancel", text="Cancel", onclick=function()
    dlg:close()
  end}
  dlg:show()
end

local function exportToInline(sprite, frameIndex)
  -- Ensure we have a valid sprite (refresh from active sprite if needed)
  local currentSprite = sprite
  if not currentSprite or not currentSprite.isValid then
    currentSprite = app.activeSprite
  end
  
  if not currentSprite then
    app.alert("No sprite is open")
    return
  end
  
  -- Get current frame index
  local currentFrameIndex = frameIndex
  if app.activeFrame and app.activeFrame.sprite == currentSprite then
    currentFrameIndex = app.activeFrame.frameNumber
  end
  currentFrameIndex = currentFrameIndex or 1
  
  -- For inline, use optimized format with CSS classes and paths by default
  local svgContent = svgGenerator.exportSpriteToSVG(currentSprite, currentFrameIndex, true, true, true)
  if not svgContent then
    app.alert("Sprite is empty or has no visible pixels")
    return
  end
  
  -- Show dialog with inline SVG code
  local dlg = Dialog("SVG Inline Code")
  dlg:newrow()
  dlg:label{ 
    id="label",
    text="Copy the SVG code below:",
    focus=false
  }
  dlg:newrow()
  dlg:entry{
    id="svgcode",
    text=svgContent,
    multiline=true,
    readonly=true,
    focus=true
  }
  dlg:newrow()
  dlg:button{ id="copy", text="Copy to Clipboard", onclick=function()
    app.clipboard(svgContent)
    app.alert("SVG code copied to clipboard!")
  end}
  dlg:button{ id="raw", text="Use Raw Format", onclick=function()
    -- Refresh sprite reference
    local currentSprite = sprite
    if not currentSprite or not currentSprite.isValid then
      currentSprite = app.activeSprite
    end
    if currentSprite then
      local currentFrameIndex = currentFrameIndex or 1
      if app.activeFrame and app.activeFrame.sprite == currentSprite then
        currentFrameIndex = app.activeFrame.frameNumber
      end
      local raw = svgGenerator.exportSpriteToSVG(currentSprite, currentFrameIndex, false, true, false)
      if raw then
        dlg:modify{ id="svgcode", text=raw }
      end
    end
  end}
  dlg:newrow()
  dlg:label{ 
    text="SVG Exporter v" .. EXTENSION_VERSION,
    focus=false
  }
  dlg:button{ id="close", text="Close", onclick=function()
    dlg:close()
  end}
  dlg:show()
end

local function exportToJSON(sprite, frameIndex)
  if not sprite then
    app.alert("No sprite is open")
    return
  end
  
  frameIndex = frameIndex or app.activeFrame.frameNumber
  
  -- Get layers as array of SVG strings with CSS classes and paths
  local layers = svgGenerator.getLayersAsSVGArray(sprite, frameIndex, true, true)
  if not layers or #layers == 0 then
    -- Provide more helpful error message
    local layerCount = 0
    if sprite and sprite.layers then
      layerCount = #sprite.layers
    end
    app.alert("No visible layers found with pixels.\n\nSprite has " .. layerCount .. " layer(s).\nMake sure at least one layer is visible and has pixels in frame " .. frameIndex .. ".")
    return
  end
  
  -- Escape SVG content for JSON
  local function escapeJson(str)
    str = string.gsub(str, "\\", "\\\\")
    str = string.gsub(str, '"', '\\"')
    str = string.gsub(str, "\n", "\\n")
    str = string.gsub(str, "\r", "\\r")
    str = string.gsub(str, "\t", "\\t")
    return str
  end
  
  -- Build JSON with layers array
  local jsonParts = {}
  table.insert(jsonParts, '{')
  table.insert(jsonParts, string.format('  "width": %d,', sprite.width))
  table.insert(jsonParts, string.format('  "height": %d,', sprite.height))
  table.insert(jsonParts, string.format('  "frame": %d,', frameIndex))
  table.insert(jsonParts, '  "layers": [')
  
  for i, layerData in ipairs(layers) do
    local escapedSvg = escapeJson(layerData.svg)
    local comma = (i < #layers) and "," or ""
    table.insert(jsonParts, string.format('    {\n      "name": "%s",\n      "svg": "%s"\n    }%s', 
      escapeJson(layerData.name), escapedSvg, comma))
  end
  
  table.insert(jsonParts, '  ]')
  table.insert(jsonParts, '}')
  
  local jsonContent = table.concat(jsonParts, '\n')
  
  local dlg = Dialog("SVG JSON Export")
  dlg:newrow()
  dlg:label{ 
    id="label",
    text="JSON with SVG layers array:",
    focus=false
  }
  dlg:newrow()
  dlg:entry{
    id="jsoncode",
    text=jsonContent,
    multiline=true,
    readonly=true,
    focus=true
  }
  dlg:newrow()
  dlg:button{ id="copy", text="Copy to Clipboard", onclick=function()
    app.clipboard(jsonContent)
    app.alert("JSON code copied to clipboard!")
  end}
  dlg:button{ id="save", text="Save JSON File", onclick=function()
    local filename = getOutputFilename(sprite)
    local path = app.fs.joinPath(app.fs.filePath(sprite.filename) or app.fs.userConfigPath, filename .. ".json")
    local file = io.open(path, "w")
    if file then
      file:write(jsonContent)
      file:close()
      app.alert("JSON exported successfully to:\n" .. path)
    else
      app.alert("Error: Could not write file")
    end
  end}
  dlg:button{ id="optimized", text="Use Optimized SVG", onclick=function()
    local optLayers = svgGenerator.getLayersAsSVGArray(sprite, frameIndex, true)
    if optLayers and #optLayers > 0 then
      local jsonPartsOpt = {}
      table.insert(jsonPartsOpt, '{')
      table.insert(jsonPartsOpt, string.format('  "width": %d,', sprite.width))
      table.insert(jsonPartsOpt, string.format('  "height": %d,', sprite.height))
      table.insert(jsonPartsOpt, string.format('  "frame": %d,', frameIndex))
      table.insert(jsonPartsOpt, '  "layers": [')
      
      for i, layerData in ipairs(optLayers) do
        local escapedSvg = escapeJson(layerData.svg)
        local comma = (i < #optLayers) and "," or ""
        table.insert(jsonPartsOpt, string.format('    {\n      "name": "%s",\n      "svg": "%s"\n    }%s', 
          escapeJson(layerData.name), escapedSvg, comma))
      end
      
      table.insert(jsonPartsOpt, '  ]')
      table.insert(jsonPartsOpt, '}')
      
      local jsonOpt = table.concat(jsonPartsOpt, '\n')
      dlg:modify{ id="jsoncode", text=jsonOpt }
    end
  end}
  dlg:newrow()
  dlg:label{ 
    text="SVG Exporter v" .. EXTENSION_VERSION,
    focus=false
  }
  dlg:button{ id="close", text="Close", onclick=function()
    dlg:close()
  end}
  dlg:show()
end

local function showFileSelectionDialog()
  local dlg = Dialog("Select Aseprite File")
  dlg:newrow()
  dlg:label{ 
    text="Select the .ase file to export:",
    focus=false
  }
  dlg:newrow()
  dlg:file{ 
    id="asefile",
    label="Aseprite File:",
    open=true,
    filetypes={"ase", "aseprite"}
  }
  dlg:newrow()
  dlg:button{ id="load", text="Load & Export", onclick=function()
    local filePath = dlg.data.asefile
    if not filePath or filePath == "" then
      app.alert("Please select a file first")
      return
    end
    
    -- Check if file exists
    if not app.fs.isFile(filePath) then
      app.alert("Error: File does not exist:\n" .. filePath)
      return
    end
    
    dlg:close()
    
    -- Load the sprite
    local sprite = app.open(filePath)
    if not sprite then
      app.alert("Error: Could not open file:\n" .. filePath)
      return
    end
    
    -- Show export menu with loaded sprite
    showExportMenu(sprite)
  end}
  dlg:newrow()
  dlg:newrow()
  dlg:label{ 
    text="SVG Exporter v" .. EXTENSION_VERSION,
    focus=false
  }
  dlg:button{ id="cancel", text="Cancel", onclick=function()
    dlg:close()
  end}
  dlg:show()
end

local function showExportMenu(sprite)
  if not sprite then
    app.alert("No sprite is open")
    return
  end
  
  local spriteName = sprite.filename or "Untitled"
  if spriteName ~= "" then
    spriteName = app.fs.fileName(spriteName)
  end
  
  local dlg = Dialog("Export to SVG")
  
  -- Add preview canvas at the top
  local previewSize = 128
  local spriteWidth = sprite.width
  local spriteHeight = sprite.height
  local scale = math.min(previewSize / spriteWidth, previewSize / spriteHeight, 1.0)
  local previewWidth = math.floor(spriteWidth * scale)
  local previewHeight = math.floor(spriteHeight * scale)
  
  dlg:canvas{
    id="preview",
    width=previewWidth,
    height=previewHeight,
    onpaint=function(ev)
      local ctx = ev.context
      if sprite then
        -- Get current frame
        local currentFrame = app.activeFrame
        local frameNum = 1
        if currentFrame and currentFrame.sprite == sprite then
          frameNum = currentFrame.frameNumber
        end
        -- Create a temporary image to render the sprite
        local img = Image(spriteWidth, spriteHeight)
        img:drawSprite(sprite, frameNum)
        -- Draw the image scaled to fit the preview
        ctx:drawImage(img, Rectangle(0, 0, spriteWidth, spriteHeight), 
                      Rectangle(0, 0, previewWidth, previewHeight))
      end
    end
  }
  dlg:newrow()
  dlg:label{ 
    text="Sprite: " .. spriteName,
    focus=false
  }
  dlg:newrow()
  dlg:label{ 
    text="Choose export format:",
    focus=false
  }
  dlg:newrow()
  dlg:button{ id="file", text="SVG File", onclick=function()
    dlg:close()
    exportToFile(sprite)
  end}
  dlg:newrow()
  dlg:button{ id="inline", text="SVG Inline Code", onclick=function()
    dlg:close()
    exportToInline(sprite)
  end}
  dlg:newrow()
  dlg:button{ id="json", text="SVG JSON", onclick=function()
    dlg:close()
    exportToJSON(sprite)
  end}
  dlg:newrow()
  dlg:button{ id="selectfile", text="Select Different File", onclick=function()
    dlg:close()
    showFileSelectionDialog()
  end}
  dlg:newrow()
  dlg:newrow()
  dlg:label{ 
    text="SVG Exporter v" .. EXTENSION_VERSION,
    focus=false
  }
  dlg:button{ id="cancel", text="Cancel", onclick=function()
    dlg:close()
  end}
  dlg:show()
end

-- Plugin initialization - registers menu commands
function init(plugin)
  -- Ensure svgGenerator is loaded
  if not svgGenerator then
    local scriptPath = getScriptPath()
    local generatorPath = app.fs.joinPath(scriptPath, "svg-generator.lua")
    if app.fs.isFile(generatorPath) then
      svgGenerator = dofile(generatorPath)
    else
      app.alert("Error: Could not find svg-generator.lua at:\n" .. generatorPath)
      return
    end
  end
  
  -- Register "SVG Exporter" command via init() as backup
  -- Primary registration is via package.json script entry with group="file"
  -- This init() registration is kept for compatibility
  plugin:newCommand{
    id = "svg_exporter_init",
    title = "SVG Exporter",
    group = "file_export",  -- File > Export submenu (fallback)
    onenabled = function() return true end,
    onclick = function()
      local sprite = app.activeSprite
      if not sprite then
        showFileSelectionDialog()
      else
        showExportMenu(sprite)
      end
    end
  }
end

-- Main entry point (called by package.json script entry)
function main()
  local sprite = app.activeSprite
  
  -- Get the title/command that was invoked
  -- Aseprite passes parameters including the script title
  local params = app.params or {}
  local title = params.title or ""
  
  -- Handle "SVG Exporter" menu item (from package.json with group="file")
  if string.find(title, "SVG Exporter") then
    if not sprite then
      showFileSelectionDialog()
    else
      showExportMenu(sprite)
    end
    return
  end
  
  -- Check if user wants to select a file (new option)
  if string.find(title, "Select File") or string.find(title, "From File") then
    showFileSelectionDialog()
    return
  end
  
  -- If no sprite is active, show file selection dialog
  if not sprite then
    showFileSelectionDialog()
    return
  end
  
  -- Check the script path/filename or title to determine which export was requested
  -- Since all scripts use the same file, we check the title
  if string.find(title, "Export to SVG File") then
    exportToFile(sprite)
  elseif string.find(title, "Export to SVG Inline") then
    exportToInline(sprite)
  elseif string.find(title, "Export to SVG JSON") then
    exportToJSON(sprite)
  elseif string.find(title, "Export to SVG (Choose Format)") then
    -- Show menu for user to choose
    showExportMenu(sprite)
  else
    -- Default: Show menu for user to choose
    showExportMenu(sprite)
  end
end

-- Return plugin (Aseprite expects this for extensions)
-- When loaded as an extension, Aseprite will call init(plugin)
-- When run as a script directly, main() will be called via package.json
if plugin then
  return plugin
end

