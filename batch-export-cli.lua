-- Headless SVG JSON export for one .aseprite file
-- Usage:
--   aseprite -b --script-param input=/path/file.aseprite \
--            --script-param output=/path/out.json \
--            --script batch-export-cli.lua

local function scriptRoot()
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source
    if string.sub(source, 1, 1) == "@" then
      source = string.sub(source, 2)
    end
    return app.fs.filePath(source)
  end
  return app.fs.currentPath
end

local ROOT = scriptRoot()

local function param(name, default)
  if app.params and app.params[name] ~= nil and app.params[name] ~= "" then
    return app.params[name]
  end
  return default
end

local function jsonEscape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function ensureDir(path)
  if path and path ~= "" and not app.fs.isDirectory(path) then
    os.execute(string.format('mkdir -p %q', path))
  end
end

local genPath = app.fs.joinPath(ROOT, "svg-generator.lua")
if not app.fs.isFile(genPath) then
  error("Missing svg-generator.lua at " .. genPath)
end
local svgGenerator = dofile(genPath)

local inputPath = param("input")
local outputPath = param("output")
local optimized = param("optimized", "1") ~= "0"
local useCss = param("css", "1") ~= "0"
local frameIndex = tonumber(param("frame", "1")) or 1

if not inputPath or inputPath == "" then
  error("Missing --script-param input=/path/to.aseprite")
end
if not app.fs.isFile(inputPath) then
  error("Input not found: " .. inputPath)
end

if not outputPath or outputPath == "" then
  outputPath = inputPath:gsub("%.aseprite$", "") .. ".svg.json"
end

print("Exporting: " .. inputPath)
print("Output: " .. outputPath)

local sprite = app.open(inputPath)
if not sprite then
  error("Failed to open: " .. inputPath)
end

app.activeSprite = sprite
if frameIndex < 1 then frameIndex = 1 end
if frameIndex > #sprite.frames then frameIndex = 1 end

local layers = svgGenerator.getLayersAsSVGArray(sprite, frameIndex, optimized, useCss, nil)
local combined = svgGenerator.exportSpriteToSVG(sprite, frameIndex, optimized, true, useCss, nil)

local parts = {}
table.insert(parts, "{")
table.insert(parts, string.format('  "source": "%s",', jsonEscape(inputPath)))
table.insert(parts, string.format('  "width": %d,', sprite.width))
table.insert(parts, string.format('  "height": %d,', sprite.height))
table.insert(parts, string.format('  "frame": %d,', frameIndex))
table.insert(parts, string.format('  "svg": %s,', combined and ('"' .. jsonEscape(combined) .. '"') or "null"))
table.insert(parts, '  "layers": [')
for i, layer in ipairs(layers) do
  local comma = (i < #layers) and "," or ""
  table.insert(parts, string.format(
    '    {"name": "%s", "svg": "%s"}%s',
    jsonEscape(layer.name),
    jsonEscape(layer.svg),
    comma
  ))
end
table.insert(parts, "  ]")
table.insert(parts, "}")

ensureDir(app.fs.filePath(outputPath))
local f = io.open(outputPath, "w")
if not f then
  error("Cannot write: " .. outputPath)
end
f:write(table.concat(parts, "\n"))
f:close()

pcall(function()
  app.activeSprite = sprite
  app.command.CloseFile()
end)

print("OK: " .. outputPath)
print("BATCH_EXPORT_OK")
