local system = require 'pandoc.system'

local tikz_doc_template = [[
\documentclass{standalone}
\usepackage{xcolor}
\usepackage{fontawesome5}
\usepackage{tikz}
\usepackage{svg}
\usetikzlibrary{positioning}
\usetikzlibrary{calc}
\usepackage{amssymb}
\usetikzlibrary{shapes.geometric, arrows.meta, positioning, fit, backgrounds, calc, decorations.pathmorphing, shadows.blur}
\usepackage{graphicx}
\begin{document}
\nopagecolor
%s
\end{document}
]]

local image_dir_name = 'img-gen'
local image_dir_path = system.get_working_directory() .. '/' .. image_dir_name
os.execute('mkdir -p "' .. image_dir_path .. '"')

local function tikz2image(src, filetype, outfile)
  local cwd = system.get_working_directory()
  system.with_temporary_directory('tikz2image', function (tmpdir)
    -- Write tikz.tex to current working directory (not temp dir)
    -- so relative paths in the tikz source resolve correctly
    local tex_file = cwd .. '/tikz.tex'
    local f = io.open(tex_file, 'w')
    f:write(tikz_doc_template:format(src))
    f:close()

    -- Run pdflatex in current working directory
    -- Output the PDF to temp directory
    io.stderr:write(string.format("TikZ: Running pdflatex -shell-escape -output-directory='%s' '%s'\n", tmpdir, tex_file))
    os.execute(string.format('pdflatex -shell-escape -output-directory="%s" "%s"',
                             tmpdir, tex_file))

    -- Clean up the tex file
    os.remove(tex_file)

    -- Process the output
    local pdf_file = tmpdir .. '/tikz.pdf'
    if filetype == 'pdf' then
      os.rename(pdf_file, outfile)
    else
      os.execute(string.format('pdf2svg "%s" "%s"', pdf_file, outfile))
    end
  end)
end

extension_for = {
  html = 'svg',
  html4 = 'svg',
  html5 = 'svg',
  latex = 'pdf',
  beamer = 'pdf' }

local function file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local function starts_with(start, str)
  return str:sub(1, #start) == start
end

local function file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

local function read_file(path)
  local f = io.open(path, 'r')
  if f == nil then
    io.stderr:write(string.format("TikZ: Could not open file '%s'\n", path))
    return nil
  end
  local content = f:read('*all')
  f:close()
  return content
end

local function parse_attributes(attr_string)
  -- Parse Pandoc-style attributes: {#id .class1 .class2 key=value}
  if not attr_string or attr_string == "" then
    return "", {}, {}
  end

  local id = ""
  local classes = {}
  local attributes = {}

  -- Match #id
  local id_match = attr_string:match("#([%w-]+)")
  if id_match then
    id = id_match
  end

  -- Match .classes
  for class in attr_string:gmatch("%.([%w-]+)") do
    table.insert(classes, class)
  end

  -- Match key=value pairs
  for key, value in attr_string:gmatch("([%w-]+)=([^%s}]+)") do
    table.insert(attributes, {key, value})
  end

  return id, classes, attributes
end

-- Process Divs that may contain TikZ from include.lua
function Div(el)
  -- Check if this Div contains tikz attributes
  local tikz_attrs = nil
  for _, kv in ipairs(el.attributes) do
    if kv[1] == "data-tikz-attrs" then
      tikz_attrs = kv[2]
      break
    end
  end

  if not tikz_attrs then
    return el
  end

  -- Extract the RawBlock from the Div
  if #el.content == 1 and el.content[1].t == "RawBlock" then
    local raw_block = el.content[1]
    local trimmed = raw_block.text:match("^%s*(.-)%s*$")

    if starts_with('\\begin{tikzpicture}', trimmed) then
      local filetype = extension_for[FORMAT] or 'svg'
      local fbasename = pandoc.sha1(trimmed) .. '.' .. filetype
      local fname = image_dir_path .. '/' .. fbasename

      if not file_exists(fname) then
        tikz2image(trimmed, filetype, fname)
      end

      -- Parse the attributes from include.lua
      local attr_id, attr_classes, attr_keyvals = parse_attributes(tikz_attrs)

      -- Merge with default tikz-img class
      table.insert(attr_classes, 1, "tikz-img")

      return pandoc.Para({
        pandoc.Image(
          {""},  -- caption
          image_dir_name .. '/' .. fbasename,  -- src
          "",  -- title
          pandoc.Attr(attr_id, attr_classes, attr_keyvals)
        )
      })
    end
  end

  return el
end

function RawBlock(el)
  io.stderr:write(string.format("TikZ DEBUG: RawBlock format=%s, text_start=%s\n", el.format, el.text:sub(1, 30)))

  -- Check for \tikz{content, attrs} command
  local tikz_match = el.text:match('^\\tikz%{(.+)%}$')
  if tikz_match then
    io.stderr:write(string.format("TikZ DEBUG: Found \\tikz{} command, content=%s\n", tikz_match:sub(1, 50)))

    -- Split by finding the end of the tikzpicture environment
    -- Then everything after the closing } and comma is attributes
    local content, attr_string
    local env_end = tikz_match:find('\\end{tikzpicture}')
    if env_end then
      local after_env = tikz_match:sub(env_end + #'\\end{tikzpicture}')
      -- Check if there's a comma followed by attributes
      local comma_pos = after_env:find('^%s*,')
      if comma_pos then
        content = tikz_match:sub(1, env_end + #'\\end{tikzpicture}' - 1)
        attr_string = after_env:match('^%s*,%s*(.*)$') or ""
      else
        content = tikz_match
        attr_string = ""
      end
    else
      -- No tikzpicture environment found, fall back to simple comma split
      content, attr_string = tikz_match:match('^(.-),%s*(.+)$')
      if not content then
        content = tikz_match
        attr_string = ""
      end
    end

    io.stderr:write(string.format("TikZ DEBUG: content='%s', attrs='%s'\n", content:sub(1, 30), attr_string))

    -- For now, assume content is TikZ picture code
    -- Process it like a regular TikZ block
    local trimmed = content:match("^%s*(.-)%s*$")
    if starts_with('\\begin{tikzpicture}', trimmed) then
      local filetype = extension_for[FORMAT] or 'svg'
      local fbasename = pandoc.sha1(trimmed) .. '.' .. filetype
      local fname = image_dir_path .. '/' .. fbasename

      if not file_exists(fname) then
        tikz2image(trimmed, filetype, fname)
      end

      -- Parse attributes
      local attr_id, attr_classes, attr_keyvals = parse_attributes(attr_string)
      table.insert(attr_classes, 1, "tikz-img")

      return pandoc.Para({
        pandoc.Image(
          {""},
          image_dir_name .. '/' .. fbasename,
          "",
          pandoc.Attr(attr_id, attr_classes, attr_keyvals)
        )
      })
    end
  end

  -- Trim leading/trailing whitespace for the check
  local trimmed = el.text:match("^%s*(.-)%s*$")
  if starts_with('\\begin{tikzpicture}', trimmed) then
    local filetype = extension_for[FORMAT] or 'svg'
    -- Use trimmed content for hashing and processing
    local fbasename = pandoc.sha1(trimmed) .. '.' .. filetype
    local fname = image_dir_path .. '/' .. fbasename
    if not file_exists(fname) then
      tikz2image(trimmed, filetype, fname)
    end
    return pandoc.Para({
      pandoc.Image(
        {""},  -- caption
        image_dir_name .. '/' .. fbasename,  -- src
        "",  -- title
        pandoc.Attr("", {"tikz-img"})  -- identifier, classes, attributes
      )
    })
  else
   return el
  end
end