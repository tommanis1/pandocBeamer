local system = require 'pandoc.system'
local json = require 'pandoc.json'

local js_dir_name = 'ghcjs-gen'
local js_dir_path = system.get_working_directory() .. '/' .. js_dir_name
os.execute('mkdir -p "' .. js_dir_path .. '"')

-- Cache file to store filepath -> js_filename mappings
local cache_file = js_dir_path .. '/.cache.json'

-- Keep track of unique IDs used for each haskellMain
local used_ids = {}

local function load_cache()
  local f = io.open(cache_file, 'r')
  if not f then
    return {}
  end
  local content = f:read('*all')
  f:close()

  -- Parse JSON
  local success, cache = pcall(function() return json.decode(content) end)
  if success and cache then
    return cache
  else
    return {}
  end
end

local function save_cache(cache)
  local f = io.open(cache_file, 'w')
  if f then
    f:write(json.encode(cache))
    f:close()
  end
end

local function file_exists(path)
  local f = io.open(path, 'r')
  if f then
    f:close()
    return true
  end
  return false
end

local function generate_random_name()
  -- Generate a random identifier using timestamp and random number
  local timestamp = os.time()
  local random = math.random(10000, 99999)
  return string.format("haskell_%d_%d", timestamp, random)
end

local function find_jsexe_dir(base_path)
  -- Search for .jsexe directories in the dist-newstyle build output
  -- The path structure is: dist-newstyle/build/javascript-ghcjs/ghc-VERSION/PACKAGE/x/EXECUTABLE/build/EXECUTABLE/EXECUTABLE.jsexe

  local find_cmd = string.format('find "%s/dist-newstyle" -type d -name "*.jsexe" 2>/dev/null | head -1', base_path)
  local handle = io.popen(find_cmd)
  local jsexe_dir = handle:read("*l")
  handle:close()

  if jsexe_dir and jsexe_dir ~= "" then
    return jsexe_dir .. "/all.js"
  end

  return nil
end

local function compile_haskell(filepath, cache)
  -- filepath is already absolute, use it directly
  local abs_filepath = filepath

  io.stderr:write(string.format("HaskellMain: Compiling Haskell code in '%s'\n", filepath))

  -- First, try building
  local build_cmd = string.format('cd "%s" && cabal build 2>&1', abs_filepath)
  io.stderr:write(string.format("HaskellMain: Running command: %s\n", build_cmd))

  local handle = io.popen(build_cmd)
  local output = handle:read("*a")
  local success = handle:close()

  io.stderr:write(string.format("HaskellMain: Cabal build output:\n%s\n", output))

  -- Check if output contains "Up to date"
  if output:match("Up to date") then
    -- Check if we have a cached JS file for this path
    local cached_entry = cache[abs_filepath]
    if cached_entry then
      local cached_js_path = js_dir_path .. '/' .. cached_entry
      if file_exists(cached_js_path) then
        io.stderr:write(string.format("HaskellMain: Build up to date and cached JS exists at '%s', skipping rebuild\n", cached_js_path))
        -- Return the cached file path (need to find the source to copy from, but we can skip that)
        -- Actually, we already have the cached file, so just return a flag to use cache
        return nil, nil, true, cached_entry
      end
    end

    io.stderr:write("HaskellMain: Build was up to date but no valid cache, running cabal clean and rebuilding...\n")

    -- Run cabal clean
    local clean_cmd = string.format('cd "%s" && cabal clean 2>&1', abs_filepath)
    local clean_handle = io.popen(clean_cmd)
    local clean_output = clean_handle:read("*a")
    clean_handle:close()

    io.stderr:write(string.format("HaskellMain: Cabal clean output:\n%s\n", clean_output))

    -- Rebuild
    build_cmd = string.format('cd "%s" && cabal build 2>&1', abs_filepath)
    handle = io.popen(build_cmd)
    output = handle:read("*a")
    success = handle:close()

    io.stderr:write(string.format("HaskellMain: Cabal rebuild output:\n%s\n", output))
  end

  if not success then
    io.stderr:write("HaskellMain: ERROR - cabal build failed\n")
    return nil, "Cabal build failed", false, nil
  end

  -- Find the .jsexe directory and all.js file
  local js_path = find_jsexe_dir(abs_filepath)

  if not js_path then
    io.stderr:write("HaskellMain: ERROR - Could not find .jsexe directory with all.js\n")
    return nil, "Could not find generated JavaScript file", false, nil
  end

  io.stderr:write(string.format("HaskellMain: Found all.js at: %s\n", js_path))

  return js_path, nil, false, nil
end

local function copy_js_file(source_path, target_name)
  local target_path = js_dir_path .. '/' .. target_name
  local copy_cmd = string.format('cp "%s" "%s"', source_path, target_path)

  io.stderr:write(string.format("HaskellMain: Copying JS file: %s\n", copy_cmd))
  local result = os.execute(copy_cmd)

  if result ~= 0 and result ~= true then
    io.stderr:write("HaskellMain: ERROR - Failed to copy JS file\n")
    return nil
  end

  return js_dir_name .. '/' .. target_name
end

local function generate_html(js_relative_path, element_id)
  -- Generate the HTML that:
  -- 1. Creates output div
  -- 2. Waits for Reveal.js to be ready (after slide rendering/codebox)
  -- 3. Then activates console.log capture just before loading GHCJS script
  -- 4. Restores console.log after GHCJS execution

  local html = string.format([[
<div id="%s"></div>
<script>
(function() {
    const outputElement = document.getElementById('%s');

    // Wait for Reveal.js to be ready and all slides initialized
    // This ensures codebox.js has finished processing
    function initGHCJS() {
        const originalLog = console.log;

        // Clear previous content
        outputElement.textContent = '';

        // Override console.log to capture GHCJS output
        console.log = function(...args) {
            // Still call original for debugging
            originalLog.apply(console, args);

            // Append to our output element
            outputElement.textContent += args.join(' ') + '\n';
        };

        // Load the GHCJS script
        const script = document.createElement('script');
        script.src = '%s';
        script.onload = function() {
            // Restore console.log after GHCJS script has run
            setTimeout(function() {
                console.log = originalLog;
            }, 100);
        };
        document.body.appendChild(script);
    }

    // Wait for Reveal.js if it exists, otherwise run immediately
    if (typeof Reveal !== 'undefined') {
        Reveal.on('ready', function() {
            // Give codebox.js time to finish (it runs on ready too)
            setTimeout(initGHCJS, 500);
        });
    } else {
        // No Reveal.js, wait for DOMContentLoaded
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                setTimeout(initGHCJS, 500);
            });
        } else {
            setTimeout(initGHCJS, 500);
        }
    }
})();
</script>
]], element_id, element_id, js_relative_path)

  return html
end

function RawBlock(el)
  -- Check for \haskellMain{filepath, id} command
  local haskell_match = el.text:match('^\\haskellMain%{(.-)%}$')

  if haskell_match then
    io.stderr:write(string.format("HaskellMain: Found \\haskellMain{} command\n"))

    -- Parse the arguments: filepath, id
    local filepath, element_id = haskell_match:match('^%s*([^,]+)%s*,%s*([^,]+)%s*$')

    if not filepath or not element_id then
      io.stderr:write("HaskellMain: ERROR - Invalid syntax. Expected \\haskellMain{filepath, id}\n")
      return pandoc.RawBlock('html', '<p style="color: red;">Error: Invalid \\haskellMain syntax</p>')
    end

    io.stderr:write(string.format("HaskellMain: filepath='%s', id='%s'\n", filepath, element_id))

    -- Track this ID
    table.insert(used_ids, element_id)

    -- Load cache
    local cache = load_cache()

    -- Compile the Haskell code
    local js_path, err, use_cache, cached_filename = compile_haskell(filepath, cache)

    if err then
      return pandoc.RawBlock('html', string.format('<p style="color: red;">Error compiling Haskell: %s</p>', err))
    end

    local js_relative_path

    if use_cache then
      -- Use the cached file
      io.stderr:write(string.format("HaskellMain: Using cached JS file: %s\n", cached_filename))
      js_relative_path = js_dir_name .. '/' .. cached_filename
    else
      -- Generate a unique name for the JS file
      local random_name = generate_random_name() .. '.js'

      -- Copy the JS file to our directory with the random name
      js_relative_path = copy_js_file(js_path, random_name)

      if not js_relative_path then
        return pandoc.RawBlock('html', '<p style="color: red;">Error: Failed to copy JavaScript file</p>')
      end

      -- Update cache
      cache[filepath] = random_name
      save_cache(cache)
      io.stderr:write(string.format("HaskellMain: Cached mapping: %s -> %s\n", filepath, random_name))
    end

    -- Generate the HTML
    local html = generate_html(js_relative_path, element_id)

    return pandoc.RawBlock('html', html)
  end

  return el
end
