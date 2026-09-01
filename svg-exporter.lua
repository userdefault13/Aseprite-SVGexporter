-- SVG Exporter for Aseprite
-- Exports sprite to SVG in multiple formats: inline code, JSON, or file

-- Extension version
local EXTENSION_VERSION = "1.0.4"

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

local function isSvgEmpty(svgContent)
  if not svgContent or svgContent == "" then
    return true
  end
  local content = string.gsub(svgContent, "<svg[^>]*>", "")
  content = string.gsub(content, "</svg>", "")
  content = string.gsub(content, "%s+", "")
  return content == ""
end

local function describeVisibleLayers(sprite, frameIndex)
  local lines = {}
  local visibleCount = 0
  for i, layer in ipairs(sprite.layers) do
    if layer and layer.isVisible ~= false and layer.isImage ~= false then
      visibleCount = visibleCount + 1
      local cel = layer:cel(frameIndex) or layer:cel(1)
      local status = (cel and cel.image) and "has pixels" or "empty cel"
      table.insert(lines, string.format("  • %s (%s)", layer.name or ("Layer " .. i), status))
    end
  end
  return visibleCount, lines
end

local function exportToFile(sprite, frameIndex, bounds)
  if not sprite then
    app.alert("No sprite is open")
    return
  end
  
  frameIndex = frameIndex or app.activeFrame.frameNumber
  
  local svgContent = svgGenerator.exportSpriteToSVG(sprite, frameIndex, false, true, false, bounds)
  if not svgContent then
    app.alert("Sprite is empty or has no visible pixels")
    return
  end
  
  local filename = getOutputFilename(sprite)
  local dlg = Dialog("Export SVG File")
  if bounds and not bounds.isEmpty then
    dlg:label{
      text=string.format("Selection: %dx%d at (%d,%d)",
        bounds.width, bounds.height, bounds.x, bounds.y),
      focus=false
    }
    dlg:newrow()
  end
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
    
    svgContent = svgGenerator.exportSpriteToSVG(
      currentSprite, currentFrameIndex, optimized, true, useCSSClasses, bounds)

    if isSvgEmpty(svgContent) and useCSSClasses then
      svgContent = svgGenerator.exportSpriteToSVG(
        currentSprite, currentFrameIndex, optimized, true, false, bounds)
    end

    if isSvgEmpty(svgContent) then
      local visibleCount, layerLines = describeVisibleLayers(currentSprite, currentFrameIndex)
      local debugInfo = {
        "Export produced no visible pixels.",
        "",
        "Sprite: " .. (currentSprite.filename or "Untitled"),
        "Frame: " .. currentFrameIndex,
        "Size: " .. currentSprite.width .. "x" .. currentSprite.height,
        "Visible image layers: " .. visibleCount,
      }
      if bounds and not bounds.isEmpty then
        table.insert(debugInfo, string.format(
          "Selection: %dx%d at (%d,%d)",
          bounds.width, bounds.height, bounds.x, bounds.y))
      end
      if #layerLines > 0 then
        table.insert(debugInfo, "")
        table.insert(debugInfo, "Layers:")
        for _, line in ipairs(layerLines) do
          table.insert(debugInfo, line)
        end
      end
      table.insert(debugInfo, "")
      table.insert(debugInfo, "SVG Exporter v" .. EXTENSION_VERSION)
      app.alert(table.concat(debugInfo, "\n"))
      return
    end

    local file = io.open(path, "wb")
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

local function exportToInline(sprite, frameIndex, bounds)
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
  local svgContent = svgGenerator.exportSpriteToSVG(currentSprite, currentFrameIndex, true, true, true, bounds)
  if not svgContent then
    app.alert("Sprite is empty or has no visible pixels")
    return
  end

  local function statusText(content)
    return string.format("SVG ready (%d characters). Use Copy or Save.", #content)
  end
  
  -- Dialog avoids Entry widgets: Aseprite caps entry text at 4096 chars
  local dlg = Dialog("SVG Inline Code")
  dlg:newrow()
  dlg:label{ 
    id="status",
    text=statusText(svgContent),
    focus=false
  }
  dlg:newrow()
  dlg:check{
    id="markdownFence",
    text="Wrap copy in markdown code fence",
    selected=false
  }
  dlg:newrow()
  dlg:button{ id="copy", text="Copy to Clipboard", onclick=function()
    local payload = svgContent
    local mode = "plain"
    if dlg.data.markdownFence then
      payload = "```svg\n" .. svgContent .. "\n```"
      mode = "markdown"
    end
    local ok, err = pcall(function()
      app.clipboard.text = payload
    end)
    if ok then
      app.alert(string.format(
        "SVG copied to clipboard (%s, %d characters).", mode, #payload))
    else
      app.alert("Failed to copy to clipboard:\n" .. tostring(err) ..
        "\n\nUse Save SVG File instead.")
    end
  end}
  dlg:button{ id="save", text="Save SVG File", onclick=function()
    dlg:close()

    local filename = getOutputFilename(currentSprite)
    local saveDlg = Dialog("Save SVG File")
    saveDlg:file{
      id="path",
      label="Save as:",
      filename=filename .. ".svg",
      save=true,
      filetypes={"svg"}
    }
    saveDlg:button{ id="ok", text="Save", onclick=function()
      local path = saveDlg.data.path
      if not path or path == "" then
        app.alert("Please specify a file path")
        return
      end

      local file = io.open(path, "wb")
      if file then
        file:write(svgContent)
        file:close()
        app.alert(string.format(
          "SVG exported successfully (%d characters) to:\n%s",
          #svgContent, path))
        saveDlg:close()
      else
        app.alert("Error: Could not write file to:\n" .. path)
      end
    end}
    saveDlg:button{ id="cancel", text="Cancel", onclick=function()
      saveDlg:close()
    end}
    saveDlg:show()
  end}
  dlg:button{ id="raw", text="Use Raw Format", onclick=function()
    local spriteRef = currentSprite
    if not spriteRef or not spriteRef.isValid then
      spriteRef = app.activeSprite
    end
    if spriteRef then
      local frame = currentFrameIndex or 1
      if app.activeFrame and app.activeFrame.sprite == spriteRef then
        frame = app.activeFrame.frameNumber
      end
      local raw = svgGenerator.exportSpriteToSVG(spriteRef, frame, false, true, false, bounds)
      if raw then
        svgContent = raw
        dlg:modify{ id="status", text=statusText(svgContent) }
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

local function exportToJSON(sprite, frameIndex, bounds)
  if not sprite then
    app.alert("No sprite is open")
    return
  end
  
  frameIndex = frameIndex or app.activeFrame.frameNumber
  
  -- Get layers as array of SVG strings with CSS classes and paths
  local layers = svgGenerator.getLayersAsSVGArray(sprite, frameIndex, true, true, bounds)
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

  local function buildJsonFromLayers(layerList, spr, frame)
    local parts = {}
    table.insert(parts, '{')
    table.insert(parts, string.format('  "width": %d,', spr.width))
    table.insert(parts, string.format('  "height": %d,', spr.height))
    table.insert(parts, string.format('  "frame": %d,', frame))
    table.insert(parts, '  "layers": [')

    for i, layerData in ipairs(layerList) do
      local escapedSvg = escapeJson(layerData.svg)
      local comma = (i < #layerList) and "," or ""
      table.insert(parts, string.format('    {\n      "name": "%s",\n      "svg": "%s"\n    }%s',
        escapeJson(layerData.name), escapedSvg, comma))
    end

    table.insert(parts, '  ]')
    table.insert(parts, '}')
    return table.concat(parts, '\n')
  end

  local function statusText(content)
    return string.format("JSON ready (%d characters). Use Copy or Save.", #content)
  end

  local jsonContent = buildJsonFromLayers(layers, sprite, frameIndex)
  
  -- Dialog avoids Entry widgets: Aseprite caps entry text at 4096 chars
  local dlg = Dialog("SVG JSON Export")
  dlg:newrow()
  dlg:label{ 
    id="status",
    text=statusText(jsonContent),
    focus=false
  }
  dlg:newrow()
  dlg:button{ id="copy", text="Copy to Clipboard", onclick=function()
    local ok, err = pcall(function()
      app.clipboard.text = jsonContent
    end)
    if ok then
      app.alert(string.format("JSON copied to clipboard (%d characters).", #jsonContent))
    else
      app.alert("Failed to copy to clipboard:\n" .. tostring(err) ..
        "\n\nUse Save JSON File instead.")
    end
  end}
  dlg:button{ id="save", text="Save JSON File", onclick=function()
    dlg:close()

    local filename = getOutputFilename(sprite)
    local saveDlg = Dialog("Save JSON File")
    saveDlg:file{ 
      id="path",
      label="Save as:",
      filename=filename .. ".json",
      save=true,
      filetypes={"json"}
    }
    saveDlg:button{ id="ok", text="Save", onclick=function()
      local path = saveDlg.data.path
      if not path or path == "" then
        app.alert("Please specify a file path")
        return
      end

      local file = io.open(path, "wb")
      if file then
        file:write(jsonContent)
        file:close()
        app.alert(string.format(
          "JSON exported successfully (%d characters) to:\n%s",
          #jsonContent, path))
        saveDlg:close()
      else
        app.alert("Error: Could not write file to:\n" .. path)
      end
    end}
    saveDlg:button{ id="cancel", text="Cancel", onclick=function()
      saveDlg:close()
    end}
    saveDlg:show()
  end}
  dlg:button{ id="raw", text="Use Raw Format", onclick=function()
    local rawLayers = svgGenerator.getLayersAsSVGArray(sprite, frameIndex, false, false, bounds)
    if rawLayers and #rawLayers > 0 then
      jsonContent = buildJsonFromLayers(rawLayers, sprite, frameIndex)
      dlg:modify{ id="status", text=statusText(jsonContent) }
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
  
  -- Check if there's a selection (before preview so we can use it)
  local hasSelection = false
  local selectionBounds = nil
  if sprite and sprite.selection then
    local selection = sprite.selection
    if selection and selection.bounds then
      local bounds = selection.bounds
      if not bounds.isEmpty then
        hasSelection = true
        selectionBounds = bounds
      end
    end
  end
  
  -- Add preview canvas at the top
  local previewSize = 128
  local spriteWidth = sprite.width
  local spriteHeight = sprite.height
  
  -- Function to update preview based on selection state
  local function updatePreviewDimensions()
    local displayWidth = spriteWidth
    local displayHeight = spriteHeight
    local displayX = 0
    local displayY = 0
    
    -- If selection export is enabled, use selection bounds
    if hasSelection and dlg.data.exportSelection then
      displayWidth = selectionBounds.width
      displayHeight = selectionBounds.height
      displayX = selectionBounds.x
      displayY = selectionBounds.y
    end
    
    local scale = math.min(previewSize / displayWidth, previewSize / displayHeight, 1.0)
    local previewWidth = math.floor(displayWidth * scale)
    local previewHeight = math.floor(displayHeight * scale)
    
    return previewWidth, previewHeight, displayWidth, displayHeight, displayX, displayY, scale
  end
  
  local initialPreviewWidth, initialPreviewHeight = updatePreviewDimensions()
  
  dlg:canvas{
    id="preview",
    width=initialPreviewWidth,
    height=initialPreviewHeight,
    onpaint=function(ev)
      local ctx = ev.context
      if sprite then
        -- Get current frame
        local currentFrame = app.activeFrame
        local frameNum = 1
        if currentFrame and currentFrame.sprite == sprite then
          frameNum = currentFrame.frameNumber
        end
        
        -- Determine what to show based on selection checkbox
        local displayWidth = spriteWidth
        local displayHeight = spriteHeight
        local displayX = 0
        local displayY = 0
        
        if hasSelection and dlg.data.exportSelection then
          -- Show only selection area
          displayWidth = selectionBounds.width
          displayHeight = selectionBounds.height
          displayX = selectionBounds.x
          displayY = selectionBounds.y
        end
        
        -- Calculate preview scale
        local scale = math.min(previewSize / displayWidth, previewSize / displayHeight, 1.0)
        local previewWidth = math.floor(displayWidth * scale)
        local previewHeight = math.floor(displayHeight * scale)
        
        -- Create a temporary image to render the sprite
        local img = Image(spriteWidth, spriteHeight)
        img:drawSprite(sprite, frameNum)
        
        -- Draw the image (cropped to selection if enabled)
        if hasSelection and dlg.data.exportSelection then
          -- Draw only the selection area
          ctx:drawImage(img, 
            Rectangle(displayX, displayY, displayWidth, displayHeight), 
            Rectangle(0, 0, previewWidth, previewHeight))
        else
          -- Draw full sprite
          ctx:drawImage(img, 
            Rectangle(0, 0, spriteWidth, spriteHeight), 
            Rectangle(0, 0, previewWidth, previewHeight))
        end
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
  dlg:check{ 
    id="exportSelection",
    label="Export Selection Only",
    text="Export only the selected area (if available)",
    selected=false,
    enabled=hasSelection,
    onchange=function()
      -- Refresh preview when checkbox changes
      local previewWidth, previewHeight = updatePreviewDimensions()
      dlg:modify{ id="preview", width=previewWidth, height=previewHeight }
      dlg:repaint()
    end
  }
  if hasSelection then
    dlg:newrow()
    dlg:label{ 
      text=string.format("Selection: %dx%d at (%d,%d)", 
        selectionBounds.width, selectionBounds.height, 
        selectionBounds.x, selectionBounds.y),
      focus=false
    }
  end
  
  dlg:newrow()
  dlg:button{ id="file", text="SVG File", onclick=function()
    local exportSelection = dlg.data.exportSelection and hasSelection
    dlg:close()
    exportToFile(sprite, nil, exportSelection and selectionBounds or nil)
  end}
  dlg:newrow()
  dlg:button{ id="inline", text="SVG Inline Code", onclick=function()
    local exportSelection = dlg.data.exportSelection and hasSelection
    dlg:close()
    exportToInline(sprite, nil, exportSelection and selectionBounds or nil)
  end}
  dlg:newrow()
  dlg:button{ id="json", text="SVG JSON", onclick=function()
    local exportSelection = dlg.data.exportSelection and hasSelection
    dlg:close()
    exportToJSON(sprite, nil, exportSelection and selectionBounds or nil)
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

