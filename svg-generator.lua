-- SVG Generator Module
-- Converts Aseprite sprite data to SVG format

local function rgbaToHex(r, g, b, a)
  if a == 0 then
    return "transparent"
  end
  local hex = string.format("#%02x%02x%02x", r, g, b)
  if a < 255 then
    local alpha = math.floor((a / 255) * 100) / 100
    return string.format("rgba(%d,%d,%d,%.2f)", r, g, b, alpha)
  end
  return hex
end

local function getPixelColor(image, x, y)
  if not image or not image.width or not image.height then
    return nil
  end
  if x < 0 or y < 0 or x >= image.width or y >= image.height then
    return nil
  end
  local pixel = image:getPixel(x, y)
  
  -- Extract RGBA from pixel value
  -- Aseprite uses ARGB format: AAAAAAAA RRRRRRRR GGGGGGGG BBBBBBBB
  -- But we need to check if it's actually ABGR (swapped R and B)
  local byte0 = pixel & 0xFF           -- Blue (or Red if swapped)
  local byte1 = (pixel >> 8) & 0xFF    -- Green
  local byte2 = (pixel >> 16) & 0xFF   -- Red (or Blue if swapped)
  local byte3 = (pixel >> 24) & 0xFF   -- Alpha
  
  -- Try ARGB format first
  local a = byte3
  local r = byte2
  local g = byte1
  local b = byte0
  
  -- Also try app.pixelColor.rgba - this should be the authoritative source
  local r2, g2, b2, a2 = app.pixelColor.rgba(pixel)
  
  -- If app.pixelColor.rgba returns valid values, use those
  -- But check if they're in the right format (sometimes it returns the pixel value itself)
  if r2 and type(r2) == "number" and r2 >= 0 and r2 <= 255 and 
     g2 and type(g2) == "number" and g2 >= 0 and g2 <= 255 and
     b2 and type(b2) == "number" and b2 >= 0 and b2 <= 255 and
     a2 and type(a2) == "number" and a2 >= 0 and a2 <= 255 then
    r, g, b, a = r2, g2, b2, a2
  else
    -- app.pixelColor.rgba didn't work, use bit extraction
    -- Based on the color swap issue, try ABGR format (swap R and B)
    a = byte3
    r = byte0  -- Swap: use byte0 for Red
    g = byte1
    b = byte2  -- Swap: use byte2 for Blue
  end
  
  -- Ensure all values are in valid range
  r = math.max(0, math.min(255, r or 0))
  g = math.max(0, math.min(255, g or 0))
  b = math.max(0, math.min(255, b or 0))
  a = math.max(0, math.min(255, a or 0))
  
  return {r = r, g = g, b = b, a = a}
end

-- Escape XML/SVG special characters for class names
local function escapeClassName(name)
  if not name or name == "" then
    return "layer"
  end
  -- Replace spaces and special characters with underscores
  name = string.gsub(name, "%s+", "_")
  name = string.gsub(name, "[^%w_-]", "")
  if name == "" then
    return "layer"
  end
  return name
end

-- Generate a CSS-safe class name from a color hex
local function colorToClassName(hex)
  -- Remove # and convert to lowercase
  local name = string.lower(string.gsub(hex, "#", ""))
  -- Generate a meaningful name based on color
  -- For now, use a simple pattern like "color-xxxxxx"
  return "color-" .. name
end

-- Convert a grid of pixels to path data by tracing outlines
-- This is a simplified version that groups adjacent pixels
local function pixelsToPath(pixels, width, height)
  if not pixels or #pixels == 0 then
    return nil
  end
  
  -- Create a 2D grid to mark which pixels are filled
  local grid = {}
  for y = 0, height - 1 do
    grid[y] = {}
    for x = 0, width - 1 do
      grid[y][x] = false
    end
  end
  
  -- Mark filled pixels
  for _, pixel in ipairs(pixels) do
    if pixel.y >= 0 and pixel.y < height and pixel.x >= 0 and pixel.x < width then
      grid[pixel.y][pixel.x] = true
    end
  end
  
  -- Find connected regions and convert to paths
  local paths = {}
  local visited = {}
  
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if grid[y][x] and not visited[y * width + x] then
        -- Find all connected pixels in this region
        local region = {}
        local stack = {{x = x, y = y}}
        visited[y * width + x] = true
        
        while #stack > 0 do
          local current = table.remove(stack)
          table.insert(region, current)
          
          -- Check 4 neighbors
          local neighbors = {
            {x = current.x + 1, y = current.y},
            {x = current.x - 1, y = current.y},
            {x = current.x, y = current.y + 1},
            {x = current.x, y = current.y - 1}
          }
          
          for _, neighbor in ipairs(neighbors) do
            local key = neighbor.y * width + neighbor.x
            if neighbor.x >= 0 and neighbor.x < width and 
               neighbor.y >= 0 and neighbor.y < height and
               grid[neighbor.y][neighbor.x] and 
               not visited[key] then
              visited[key] = true
              table.insert(stack, neighbor)
            end
          end
        end
        
        -- Convert region to path using a simple outline algorithm
        if #region > 0 then
          local pathData = regionToPath(region)
          if pathData then
            table.insert(paths, pathData)
          end
        end
      end
    end
  end
  
  return paths
end

-- Convert a region of pixels to SVG path data
-- Uses a simplified algorithm that traces the outline
local function regionToPath(region)
  if #region == 0 then
    return nil
  end
  
  -- For single pixel
  if #region == 1 then
    local p = region[1]
    return string.format("M%d,%dh1v1h-1z", p.x, p.y)
  end
  
  -- For multiple pixels, find bounding box and create a path
  -- This is a simplified approach - for better results, use a proper outline tracing algorithm
  local minX, minY = region[1].x, region[1].y
  local maxX, maxY = region[1].x, region[1].y
  
  for _, p in ipairs(region) do
    if p.x < minX then minX = p.x end
    if p.x > maxX then maxX = p.x end
    if p.y < minY then minY = p.y end
    if p.y > maxY then maxY = p.y end
  end
  
  -- Create a simple rectangular path for now
  -- A more sophisticated algorithm would trace the actual outline
  return string.format("M%d,%dh%dv%dh-%dz", minX, minY, maxX - minX + 1, maxY - minY + 1, maxX - minX + 1)
end

-- Find connected regions of pixels and convert to path outlines
-- Uses a flood-fill algorithm to find regions, then traces their outlines
local function findConnectedRegions(pixels, width, height)
  local grid = {}
  local visited = {}
  
  -- Build grid
  for y = 0, height - 1 do
    grid[y] = {}
    for x = 0, width - 1 do
      grid[y][x] = false
    end
  end
  
  for _, p in ipairs(pixels) do
    if p.y >= 0 and p.y < height and p.x >= 0 and p.x < width then
      grid[p.y][p.x] = true
    end
  end
  
  -- Find connected regions using flood-fill
  local regions = {}
  
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if grid[y][x] and not visited[y * width + x] then
        local region = {}
        local stack = {{x = x, y = y}}
        visited[y * width + x] = true
        
        while #stack > 0 do
          local current = table.remove(stack)
          table.insert(region, current)
          
          -- Check 4-connected neighbors
          local neighbors = {
            {x = current.x + 1, y = current.y},
            {x = current.x - 1, y = current.y},
            {x = current.x, y = current.y + 1},
            {x = current.x, y = current.y - 1}
          }
          
          for _, neighbor in ipairs(neighbors) do
            local key = neighbor.y * width + neighbor.x
            if neighbor.x >= 0 and neighbor.x < width and 
               neighbor.y >= 0 and neighbor.y < height and
               grid[neighbor.y][neighbor.x] and 
               not visited[key] then
              visited[key] = true
              table.insert(stack, neighbor)
            end
          end
        end
        
        if #region > 0 then
          table.insert(regions, region)
        end
      end
    end
  end
  
  return regions
end

-- Trace the outline of a region and convert to SVG path
-- Uses a simplified algorithm that merges adjacent pixels into paths
local function regionToPathOutline(region, width, height)
  if #region == 0 then
    return nil
  end
  
  -- For single pixel
  if #region == 1 then
    local p = region[1]
    return string.format("M%d,%dh1v1h-1z", p.x, p.y)
  end
  
  -- Create a grid from the region
  local grid = {}
  for y = 0, height - 1 do
    grid[y] = {}
    for x = 0, width - 1 do
      grid[y][x] = false
    end
  end
  
  for _, p in ipairs(region) do
    if p.y >= 0 and p.y < height and p.x >= 0 and p.x < width then
      grid[p.y][p.x] = true
    end
  end
  
  -- Find horizontal runs and merge them
  local runs = {}
  local used = {}
  
  for y = 0, height - 1 do
    local startX = nil
    for x = 0, width - 1 do
      if grid[y][x] then
        if startX == nil then
          startX = x
        end
      else
        if startX ~= nil then
          table.insert(runs, {x = startX, y = y, width = x - startX, height = 1})
          startX = nil
        end
      end
    end
    if startX ~= nil then
      table.insert(runs, {x = startX, y = y, width = width - startX, height = 1})
    end
  end
  
  -- Try to merge vertical adjacent runs
  local mergedRuns = {}
  for _, run in ipairs(runs) do
    local merged = false
    for i, mergedRun in ipairs(mergedRuns) do
      if mergedRun.x == run.x and mergedRun.width == run.width and 
         mergedRun.y + mergedRun.height == run.y then
        mergedRun.height = mergedRun.height + run.height
        merged = true
        break
      end
    end
    if not merged then
      table.insert(mergedRuns, {x = run.x, y = run.y, width = run.width, height = run.height})
    end
  end
  
  -- Convert merged runs to path data
  -- For now, create separate paths for each run
  -- A more sophisticated algorithm would trace the actual outline
  if #mergedRuns == 1 then
    local r = mergedRuns[1]
    return string.format("M%d,%dh%dv%dh-%dz", r.x, r.y, r.width, r.height, r.width)
  else
    -- Multiple runs - combine them
    local pathParts = {}
    for _, r in ipairs(mergedRuns) do
      table.insert(pathParts, string.format("M%d,%dh%dv%dh-%dz", r.x, r.y, r.width, r.height, r.width))
    end
    return table.concat(pathParts, " ")
  end
end

-- Convert image to optimized SVG with CSS classes and paths
-- This creates the format: <style> with color classes, <g> groups with paths
local function imageToOptimizedSVGWithClasses(image, width, height, layerName, offsetX, offsetY, spriteWidth, spriteHeight)
  if not image or not width or not height then
    return nil, nil
  end
  
  offsetX = offsetX or 0
  offsetY = offsetY or 0
  
  -- Use the image's actual dimensions
  local imageWidth = image.width
  local imageHeight = image.height
  
  -- Step 1: Collect all pixels grouped by color
  local colorGroups = {}
  
  for y = 0, imageHeight - 1 do
    for x = 0, imageWidth - 1 do
      local color = getPixelColor(image, x, y)
      if color and color.a and color.a > 0 then
        local hex = rgbaToHex(color.r, color.g, color.b, color.a)
        if not colorGroups[hex] then
          colorGroups[hex] = {}
        end
        -- Store with offset applied
        table.insert(colorGroups[hex], {x = x + offsetX, y = y + offsetY})
      end
    end
  end
  
  if not next(colorGroups) then
    return nil, nil
  end
  
  -- Step 2: Create CSS classes for each color
  local cssClasses = {}
  local classMap = {} -- Maps hex color to class name
  local classCounter = 1
  
  for hex, _ in pairs(colorGroups) do
    local className
    local hexLower = string.lower(hex)
    -- Try to infer meaningful names from common colors
    if hexLower == "#ffffff" or hexLower == "#fff" then
      className = "white"
    elseif hexLower == "#000000" or hexLower == "#000" then
      className = "black"
    elseif hexLower == "#b6509e" then
      className = "gotchi-primary"
    elseif hexLower == "#cfeef4" then
      className = "gotchi-secondary"
    elseif hexLower == "#f696c6" then
      className = "gotchi-cheek"
    else
      -- Use a generic name
      className = "color" .. classCounter
      classCounter = classCounter + 1
    end
    
    classMap[hex] = className
    table.insert(cssClasses, {
      name = className,
      hex = hex
    })
  end
  
  -- Step 3: Convert pixel groups to paths by finding connected regions
  local pathGroups = {}
  
  for hex, pixels in pairs(colorGroups) do
    local className = classMap[hex]
    if not pathGroups[className] then
      pathGroups[className] = {}
    end
    
    -- Find connected regions (use sprite dimensions since pixels have offsets)
    local searchWidth = spriteWidth or width
    local searchHeight = spriteHeight or height
    local regions = findConnectedRegions(pixels, searchWidth, searchHeight)
    
    -- Convert each region to a path
    for _, region in ipairs(regions) do
      local pathData = regionToPathOutline(region, searchWidth, searchHeight)
      if pathData then
        table.insert(pathGroups[className], pathData)
      end
    end
  end
  
  return cssClasses, pathGroups
end

-- Generate CSS style block from color classes
local function generateCSS(cssClasses)
  local cssParts = {}
  for _, class in ipairs(cssClasses) do
    table.insert(cssParts, string.format(".%s{fill:%s;}", class.name, class.hex))
  end
  return table.concat(cssParts, "\n        ")
end

-- Convert sprite to optimized SVG with CSS classes and paths
local function spriteToOptimizedSVGWithClasses(sprite, frameIndex, useLayerGroups)
  frameIndex = frameIndex or 1
  useLayerGroups = useLayerGroups or false
  
  local width = sprite.width
  local height = sprite.height
  
  -- Get all visible layers for this frame
  -- Use lenient checking similar to getLayersAsSVGArray
  local layers = {}
  for i, layer in ipairs(sprite.layers) do
    if not layer then
      goto continue
    end
    
    -- Check if it's an image layer - if isImage is nil, assume it's an image layer
    local isImage = layer.isImage
    if isImage == false then
      goto continue
    end
    
    -- Check if layer is visible - if isVisible is nil, assume it's visible
    local isVisible = layer.isVisible
    if isVisible == false then
      goto continue
    end
    
    -- Try to get the cel for this frame
    local cel = layer:cel(frameIndex)
    
    -- If no cel for this frame, try frame 1 as fallback
    if not cel then
      cel = layer:cel(1)
    end
    
    -- If still no cel, skip this layer
    if not cel or not cel.image then
      goto continue
    end
    
    table.insert(layers, {
      layer = layer,
      cel = cel,
      name = layer.name or ("Layer " .. i)
    })
    
    ::continue::
  end
  
  if #layers == 0 then
    return nil
  end
  
  -- Collect all CSS classes and paths from all layers
  local allCSSClasses = {}
  local allPathGroups = {}
  local layerGroups = {}
  
  for _, layerData in ipairs(layers) do
    local cel = layerData.cel
    local celImage = cel.image
    local celWidth = celImage.width
    local celHeight = celImage.height
    local celX = cel.position.x
    local celY = cel.position.y
    
    local cssClasses, pathGroups = imageToOptimizedSVGWithClasses(
      celImage, celWidth, celHeight, layerData.name, celX, celY, width, height)
    
    if cssClasses and pathGroups then
      -- Merge CSS classes (avoid duplicates)
      local classMap = {}
      for _, css in ipairs(allCSSClasses) do
        classMap[css.name] = css.hex
      end
      
      for _, css in ipairs(cssClasses) do
        if not classMap[css.name] or classMap[css.name] ~= css.hex then
          -- Check if we need to rename to avoid conflicts
          local originalName = css.name
          local counter = 1
          while classMap[css.name] do
            css.name = originalName .. counter
            counter = counter + 1
          end
          table.insert(allCSSClasses, css)
          classMap[css.name] = css.hex
        end
      end
      
      -- Store paths for this layer
      if useLayerGroups then
        local className = escapeClassName(layerData.name)
        layerGroups[className] = pathGroups
      else
        -- Merge into main path groups
        for className, paths in pairs(pathGroups) do
          if not allPathGroups[className] then
            allPathGroups[className] = {}
          end
          for _, path in ipairs(paths) do
            table.insert(allPathGroups[className], path)
          end
        end
      end
    end
  end
  
  -- Check if we have any content to export
  local hasContent = false
  if useLayerGroups then
    for _, pathGroups in pairs(layerGroups) do
      for _, paths in pairs(pathGroups) do
        if paths and #paths > 0 then
          hasContent = true
          break
        end
      end
      if hasContent then break end
    end
  else
    for _, paths in pairs(allPathGroups) do
      if paths and #paths > 0 then
        hasContent = true
        break
      end
    end
  end
  
  if not hasContent then
    -- Fallback: if no paths were generated, try the regular export method
    return nil
  end
  
  -- Build SVG
  local svgParts = {}
  table.insert(svgParts, string.format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">', 
    width, height))
  
  -- Add style block
  if #allCSSClasses > 0 then
    table.insert(svgParts, '<style>')
    table.insert(svgParts, generateCSS(allCSSClasses))
    table.insert(svgParts, '</style>')
  end
  
  -- Add path groups
  if useLayerGroups then
    for layerName, pathGroups in pairs(layerGroups) do
      table.insert(svgParts, string.format('<g class="%s">', layerName))
      for className, paths in pairs(pathGroups) do
        if paths and #paths > 0 then
          table.insert(svgParts, string.format('<g class="%s">', className))
          for _, pathData in ipairs(paths) do
            table.insert(svgParts, string.format('<path d="%s"/>', pathData))
          end
          table.insert(svgParts, '</g>')
        end
      end
      table.insert(svgParts, '</g>')
    end
  else
    for className, paths in pairs(allPathGroups) do
      if paths and #paths > 0 then
        table.insert(svgParts, string.format('<g class="%s">', className))
        for _, pathData in ipairs(paths) do
          table.insert(svgParts, string.format('<path d="%s"/>', pathData))
        end
        table.insert(svgParts, '</g>')
      end
    end
  end
  
  table.insert(svgParts, '</svg>')
  
  return table.concat(svgParts, '')
end

-- Convert a single layer/cel to SVG content (rectangles only, no wrapper)
local function layerToSVGContent(image, width, height, offsetX, offsetY)
  if not image or not width or not height then
    return nil
  end
  
  offsetX = offsetX or 0
  offsetY = offsetY or 0
  
  local contentParts = {}
  local hasPixels = false
  
  -- Use the image's actual dimensions, not the passed width/height
  local imageWidth = image.width
  local imageHeight = image.height
  
  for y = 0, imageHeight - 1 do
    for x = 0, imageWidth - 1 do
      local color = getPixelColor(image, x, y)
      if color and color.a and color.a > 0 then
        local fillColor = rgbaToHex(color.r, color.g, color.b, color.a)
        -- Apply cel position offset
        local svgX = x + offsetX
        local svgY = y + offsetY
        table.insert(contentParts, string.format('    <rect x="%d" y="%d" width="1" height="1" fill="%s"/>', 
          svgX, svgY, fillColor))
        hasPixels = true
      end
    end
  end
  
  if not hasPixels then
    return nil
  end
  
  return table.concat(contentParts, '\n')
end

-- Convert sprite to SVG using rectangles for each pixel (simple method)
-- Can be optimized later to merge adjacent pixels
local function spriteToSVG(sprite, frameIndex, useLayerGroups)
  frameIndex = frameIndex or 1
  useLayerGroups = useLayerGroups or false
  
  local width = sprite.width
  local height = sprite.height
  
  -- Get all visible layers for this frame
  -- Use lenient checking similar to getLayersAsSVGArray
  local layers = {}
  for i, layer in ipairs(sprite.layers) do
    if not layer then
      goto continue
    end
    
    -- Check if it's an image layer - if isImage is nil, assume it's an image layer
    local isImage = layer.isImage
    if isImage == false then
      goto continue
    end
    
    -- Check if layer is visible - if isVisible is nil, assume it's visible
    local isVisible = layer.isVisible
    if isVisible == false then
      goto continue
    end
    
    -- Try to get the cel for this frame
    local cel = layer:cel(frameIndex)
    
    -- If no cel for this frame, try frame 1 as fallback
    if not cel then
      cel = layer:cel(1)
    end
    
    -- If still no cel, skip this layer
    if not cel or not cel.image then
      goto continue
    end
    
    table.insert(layers, {
      layer = layer,
      cel = cel,
      name = layer.name or ("Layer " .. i)
    })
    
    ::continue::
  end
  
  if #layers == 0 then
    return nil
  end
  
  -- Build SVG content
  local svgParts = {}
  table.insert(svgParts, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', 
    width, height, width, height))
  
  if useLayerGroups then
    -- Group layers using <g> elements with class names
    for _, layerData in ipairs(layers) do
      local className = escapeClassName(layerData.name)
      local cel = layerData.cel
      local celImage = cel.image
      local celWidth = celImage.width
      local celHeight = celImage.height
      local celX = cel.position.x
      local celY = cel.position.y
      
      local layerContent = layerToSVGContent(celImage, celWidth, celHeight, celX, celY)
      if layerContent then
        table.insert(svgParts, string.format('  <g class="%s">', className))
        table.insert(svgParts, layerContent)
        table.insert(svgParts, '  </g>')
      end
    end
  else
    -- Flatten all layers (old behavior for backward compatibility)
    for _, layerData in ipairs(layers) do
      local cel = layerData.cel
      local celImage = cel.image
      local celWidth = celImage.width
      local celHeight = celImage.height
      local celX = cel.position.x
      local celY = cel.position.y
      
      local layerContent = layerToSVGContent(celImage, celWidth, celHeight, celX, celY)
      if layerContent then
        table.insert(svgParts, layerContent)
      end
    end
  end
  
  table.insert(svgParts, '</svg>')
  
  return table.concat(svgParts, '\n')
end

-- Convert a single layer to optimized SVG content (groups similar colors)
local function layerToOptimizedSVGContent(image, width, height, offsetX, offsetY)
  if not image or not width or not height then
    return nil
  end
  
  offsetX = offsetX or 0
  offsetY = offsetY or 0
  
  -- Use the image's actual dimensions
  local imageWidth = image.width
  local imageHeight = image.height
  
  -- Group pixels by color
  local colorGroups = {}
  
  for y = 0, imageHeight - 1 do
    for x = 0, imageWidth - 1 do
      local color = getPixelColor(image, x, y)
      if color and color.a and color.a > 0 then
        local colorKey = rgbaToHex(color.r, color.g, color.b, color.a)
        if not colorGroups[colorKey] then
          colorGroups[colorKey] = {}
        end
        -- Store with offset applied
        table.insert(colorGroups[colorKey], {x = x + offsetX, y = y + offsetY})
      end
    end
  end
  
  if not next(colorGroups) then
    return nil
  end
  
  local contentParts = {}
  -- Create rectangles for each color group
  for colorKey, pixels in pairs(colorGroups) do
    for _, pixel in ipairs(pixels) do
      table.insert(contentParts, string.format('    <rect x="%d" y="%d" width="1" height="1" fill="%s"/>', 
        pixel.x, pixel.y, colorKey))
    end
  end
  
  return table.concat(contentParts, '\n')
end

-- Convert sprite to optimized SVG using path data (groups similar colors)
local function spriteToOptimizedSVG(sprite, frameIndex, useLayerGroups)
  frameIndex = frameIndex or 1
  useLayerGroups = useLayerGroups or false
  
  local width = sprite.width
  local height = sprite.height
  
  -- Get all visible layers for this frame
  -- Use lenient checking similar to getLayersAsSVGArray
  local layers = {}
  for i, layer in ipairs(sprite.layers) do
    if not layer then
      goto continue
    end
    
    -- Check if it's an image layer - if isImage is nil, assume it's an image layer
    local isImage = layer.isImage
    if isImage == false then
      goto continue
    end
    
    -- Check if layer is visible - if isVisible is nil, assume it's visible
    local isVisible = layer.isVisible
    if isVisible == false then
      goto continue
    end
    
    -- Try to get the cel for this frame
    local cel = layer:cel(frameIndex)
    
    -- If no cel for this frame, try frame 1 as fallback
    if not cel then
      cel = layer:cel(1)
    end
    
    -- If still no cel, skip this layer
    if not cel or not cel.image then
      goto continue
    end
    
    table.insert(layers, {
      layer = layer,
      cel = cel,
      name = layer.name or ("Layer " .. i)
    })
    
    ::continue::
  end
  
  if #layers == 0 then
    return nil
  end
  
  -- Build SVG
  local svgParts = {}
  table.insert(svgParts, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', 
    width, height, width, height))
  
  if useLayerGroups then
    -- Group layers using <g> elements with class names
    for _, layerData in ipairs(layers) do
      local className = escapeClassName(layerData.name)
      local cel = layerData.cel
      local celImage = cel.image
      local celWidth = celImage.width
      local celHeight = celImage.height
      local celX = cel.position.x
      local celY = cel.position.y
      
      local layerContent = layerToOptimizedSVGContent(celImage, celWidth, celHeight, celX, celY)
      if layerContent then
        table.insert(svgParts, string.format('  <g class="%s">', className))
        table.insert(svgParts, layerContent)
        table.insert(svgParts, '  </g>')
      end
    end
  else
    -- Flatten all layers
    for _, layerData in ipairs(layers) do
      local cel = layerData.cel
      local celImage = cel.image
      local celWidth = celImage.width
      local celHeight = celImage.height
      local celX = cel.position.x
      local celY = cel.position.y
      
      local layerContent = layerToOptimizedSVGContent(celImage, celWidth, celHeight, celX, celY)
      if layerContent then
        table.insert(svgParts, layerContent)
      end
    end
  end
  
  table.insert(svgParts, '</svg>')
  
  return table.concat(svgParts, '\n')
end

-- Get layers as individual SVG strings (for JSON export)
local function getLayersAsSVGArray(sprite, frameIndex, optimized)
  if not sprite then
    return {}
  end
  
  frameIndex = frameIndex or 1
  optimized = optimized or false
  
  local width = sprite.width
  local height = sprite.height
  
  -- Validate sprite dimensions
  if not width or not height or width <= 0 or height <= 0 then
    return {}
  end
  
  local layers = {}
  
  -- Get all visible layers for this frame
  -- Try to be more lenient with layer checking
  for i, layer in ipairs(sprite.layers) do
    if not layer then
      goto continue
    end
    
    -- Check if it's an image layer - if isImage is nil, assume it's an image layer
    local isImage = layer.isImage
    if isImage == false then
      goto continue
    end
    
    -- Check if layer is visible - if isVisible is nil, assume it's visible
    local isVisible = layer.isVisible
    if isVisible == false then
      goto continue
    end
    
    -- Try to get the cel for this frame
    local cel = layer:cel(frameIndex)
    
    -- If no cel for this frame, try frame 1 as fallback
    if not cel then
      cel = layer:cel(1)
    end
    
    -- If still no cel, skip this layer
    if not cel or not cel.image then
      goto continue
    end
    
    local celImage = cel.image
    local celWidth = celImage.width
    local celHeight = celImage.height
    local celX = cel.position.x
    local celY = cel.position.y
    
    local layerContent
    if optimized then
      layerContent = layerToOptimizedSVGContent(celImage, celWidth, celHeight, celX, celY)
    else
      layerContent = layerToSVGContent(celImage, celWidth, celHeight, celX, celY)
    end
    
    if layerContent then
      -- Wrap in complete SVG
      local svgParts = {}
      table.insert(svgParts, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', 
        width, height, width, height))
      table.insert(svgParts, layerContent)
      table.insert(svgParts, '</svg>')
      
      table.insert(layers, {
        name = layer.name or ("Layer " .. i),
        svg = table.concat(svgParts, '\n')
      })
    end
    
    ::continue::
  end
  
  return layers
end

-- Export sprite to SVG string
function exportSpriteToSVG(sprite, frameIndex, optimized, useLayerGroups, useCSSClasses)
  if not sprite then
    return nil
  end
  
  useLayerGroups = useLayerGroups or false
  useCSSClasses = useCSSClasses or false
  
  if useCSSClasses then
    return spriteToOptimizedSVGWithClasses(sprite, frameIndex, useLayerGroups)
  elseif optimized then
    return spriteToOptimizedSVG(sprite, frameIndex, useLayerGroups)
  else
    return spriteToSVG(sprite, frameIndex, useLayerGroups)
  end
end

return {
  exportSpriteToSVG = exportSpriteToSVG,
  getLayersAsSVGArray = getLayersAsSVGArray,
  rgbaToHex = rgbaToHex
}

