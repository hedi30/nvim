local M = {}

local api = vim.api
local ns = api.nvim_create_namespace('opencode_cmdk')
local state_path = vim.fn.stdpath('state') .. '/opencode_cmdk.json'
local scope_node_patterns = {
  'function',
  'method',
  'class',
  'interface',
  'struct',
  'impl',
  'module',
  'object',
  'block',
}
local definition_patterns = {
  '^%s*import%s+',
  '^%s*from%s+',
  '^%s*export%s+',
  '^%s*async%s+function%s+[%w_]+',
  '^%s*function%s+[%w_]+',
  '^%s*local%s+function%s+[%w_]+',
  '^%s*[%w_%.:]+%s*=%s*function%s*%(',
  '^%s*[%w_%.:]+%s*=%s*%b()%s*=>',
  '^%s*class%s+[%w_]+',
  '^%s*interface%s+[%w_]+',
  '^%s*type%s+[%w_]+',
  '^%s*const%s+[%w_]+',
  '^%s*let%s+[%w_]+',
  '^%s*var%s+[%w_]+',
  '^%s*def%s+[%w_]+',
  '^%s*async%s+def%s+[%w_]+',
  '^%s*func%s+[%w_]+',
  '^%s*fn%s+[%w_]+',
  '^%s*struct%s+[%w_]+',
  '^%s*impl%s+',
  '^%s*module%s+[%w_]+',
}
local keyword_blocklist = {
  ['local'] = true,
  ['function'] = true,
  ['return'] = true,
  ['const'] = true,
  ['class'] = true,
  ['async'] = true,
  ['await'] = true,
  ['public'] = true,
  ['private'] = true,
  ['protected'] = true,
  ['static'] = true,
  ['export'] = true,
  ['import'] = true,
  ['from'] = true,
  ['type'] = true,
  ['interface'] = true,
  ['struct'] = true,
  ['impl'] = true,
  ['module'] = true,
  ['self'] = true,
  ['this'] = true,
  ['true'] = true,
  ['false'] = true,
  ['nil'] = true,
  ['null'] = true,
}

local state = {
  model = nil,
  variant = nil,
}

local function normalize_model(model)
  if type(model) ~= 'string' or model == '' then
    return nil
  end

  if model:find('/', 1, true) then
    return model
  end

  return 'openai/' .. model
end

local function normalize_variant(variant)
  if type(variant) ~= 'string' or variant == '' then
    return nil
  end

  return variant
end

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = 'OpenCode Cmd-K' })
  end)
end

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end

  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, '\n'))
  if not ok_decode then
    return nil
  end

  return decoded
end

local function write_json(path, value)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  vim.fn.writefile({ vim.json.encode(value) }, path)
end

local function load_state()
  local saved = read_json(state_path)
  if type(saved) == 'table' then
    if type(saved.model) == 'string' and saved.model ~= '' then
      state.model = normalize_model(saved.model)
    end
    if type(saved.variant) == 'string' and saved.variant ~= '' then
      state.variant = normalize_variant(saved.variant)
    end
  end
end

local function save_state()
  local model = normalize_model(state.model)
  local variant = normalize_variant(state.variant)
  if model == nil then
    write_json(state_path, {})
    return
  end
  write_json(state_path, { model = model, variant = variant })
end

local function active_model_label()
  local model = normalize_model(state.model)
  local variant = normalize_variant(state.variant)
  if not model then
    return 'opencode default'
  end
  if variant then
    return model .. ' [' .. variant .. ']'
  end
  return model
end

local function parse_verbose_models(output)
  local entries = {}
  local lines = vim.split(output or '', '\n', { plain = true })
  local i = 1

  while i <= #lines do
    local header = vim.trim(lines[i])
    if header ~= '' and header:find('/', 1, true) and not header:match('^%{') then
      local json_lines = {}
      i = i + 1
      local balance = 0
      local started = false

      while i <= #lines do
        local line = lines[i]
        if not started and vim.trim(line) == '' then
          i = i + 1
        else
          started = true
          table.insert(json_lines, line)
          local opens = select(2, line:gsub('{', ''))
          local closes = select(2, line:gsub('}', ''))
          balance = balance + opens - closes
          i = i + 1
          if balance == 0 and #json_lines > 0 then
            break
          end
        end
      end

      local ok, decoded = pcall(vim.json.decode, table.concat(json_lines, '\n'))
      if ok and type(decoded) == 'table' then
        decoded.full_id = header
        table.insert(entries, decoded)
      end
    else
      i = i + 1
    end
  end

  return entries
end

local function current_choice_matches(model, variant)
  return normalize_model(state.model) == normalize_model(model) and normalize_variant(state.variant) == normalize_variant(variant)
end

local function health_lines()
  local lines = {}
  local ok_level = vim.log.levels.INFO
  local warn_level = vim.log.levels.WARN
  local err_level = vim.log.levels.ERROR

  lines[#lines + 1] = { string.format('Neovim %s', vim.version and vim.version().major and (vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch) or 'unknown'), ok_level }

  if type(vim.system) == 'function' then
    lines[#lines + 1] = { 'vim.system available', ok_level }
  else
    lines[#lines + 1] = { 'vim.system missing; update Neovim stable', err_level }
  end

  local bin = get_opencode_bin()
  if bin then
    lines[#lines + 1] = { 'opencode found: ' .. bin, ok_level }
  else
    lines[#lines + 1] = { 'opencode not found on PATH or ~/.opencode/bin/opencode', err_level }
  end

  local auth = read_json(vim.fn.expand('~/.local/share/opencode/auth.json'))
  if type(auth) == 'table' then
    local providers = {}
    for name, data in pairs(auth) do
      if type(data) == 'table' then
        providers[#providers + 1] = name
      end
    end
    table.sort(providers)
    if #providers > 0 then
      lines[#lines + 1] = { 'opencode auth providers: ' .. table.concat(providers, ', '), ok_level }
    else
      lines[#lines + 1] = { 'opencode auth.json exists but has no provider entries', warn_level }
    end
  else
    lines[#lines + 1] = { 'opencode auth.json not found; run opencode provider login if needed', warn_level }
  end

  lines[#lines + 1] = { 'active model: ' .. active_model_label(), ok_level }
  lines[#lines + 1] = { 'state file: ' .. state_path, ok_level }

  return lines
end

function M.healthcheck()
  local has_health, health = pcall(require, 'vim.health')
  if not has_health then
    for _, item in ipairs(health_lines()) do
      notify(item[1], item[2])
    end
    return
  end

  health.start('OpenCode Cmd-K')
  for _, item in ipairs(health_lines()) do
    if item[2] == vim.log.levels.ERROR then
      health.error(item[1])
    elseif item[2] == vim.log.levels.WARN then
      health.warn(item[1])
    else
      health.ok(item[1])
    end
  end
end

local function get_opencode_bin()
  local bin = vim.fn.exepath('opencode')
  if bin ~= '' then
    return bin
  end

  local local_bin = vim.fn.expand('~/.opencode/bin/opencode')
  if vim.fn.executable(local_bin) == 1 then
    return local_bin
  end

  return nil
end

local function ensure_opencode(callback)
  if type(vim.system) ~= 'function' then
    notify('Neovim is too old for this Cmd-K plugin. Update to a newer stable Neovim.', vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local bin = get_opencode_bin()
  if not bin then
    notify('opencode is not installed or not on PATH.', vim.log.levels.ERROR)
    callback(nil)
    return
  end

  callback(bin)
end

local function extract_opencode_text(stdout)
  local chunks = {}
  for line in (stdout or ''):gmatch('[^\r\n]+') do
    local ok, event = pcall(vim.json.decode, line)
    if ok and type(event) == 'table' and event.type == 'text' and event.part and event.part.text then
      table.insert(chunks, event.part.text)
    end
  end

  if #chunks == 0 then
    return nil
  end

  return table.concat(chunks, '\n')
end

local function current_workdir(bufnr)
  local name = api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    local dir = vim.fs.dirname(name)
    if dir and vim.fn.isdirectory(dir) == 1 then
      return dir
    end
  end

  return vim.fn.getcwd()
end

local function trim_fences(text)
  local lines = vim.split(text or '', '\n', { plain = true })
  if #lines > 0 and lines[1]:match('^```') then
    table.remove(lines, 1)
  end
  if #lines > 0 and lines[#lines]:match('^```') then
    table.remove(lines, #lines)
  end
  return table.concat(lines, '\n')
end

local function collect_lines(bufnr, line1, line2)
  return api.nvim_buf_get_lines(bufnr, math.max(line1 - 1, 0), math.max(line2, 0), false)
end

local function format_section(title, lines)
  if not lines or #lines == 0 then
    return nil
  end
  return title .. ':\n' .. table.concat(lines, '\n')
end

local function get_local_context(bufnr, center_line, before, after)
  local total = api.nvim_buf_line_count(bufnr)
  local start_line = math.max(1, center_line - before)
  local end_line = math.min(total, center_line + after)
  return start_line, end_line, collect_lines(bufnr, start_line, end_line)
end

local function is_large_file(bufnr)
  return api.nvim_buf_line_count(bufnr) > 500
end

local function line_matches_definition(line)
  for _, pattern in ipairs(definition_patterns) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

local function get_treesitter_structure_map(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local trees = parser:parse()
  if not trees or not trees[1] then
    return nil
  end

  local total = api.nvim_buf_line_count(bufnr)
  local root = trees[1]:root()
  local seen = {}
  local items = {}

  local function add_node(node, depth)
    if #items >= 120 then
      return
    end

    local node_type = node:type()
    local matched = false
    for _, pattern in ipairs(scope_node_patterns) do
      if node_type:find(pattern, 1, true) then
        matched = true
        break
      end
    end

    if not matched then
      return
    end

    local start_row, _, end_row, _ = node:range()
    local line_nr = start_row + 1
    if line_nr < 1 or line_nr > total or seen[line_nr] then
      return
    end

    local line = api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ''
    line = vim.trim(line)
    if line == '' then
      return
    end

    seen[line_nr] = true
    items[#items + 1] = string.format('%d: %s%s [%s %d-%d]', line_nr, string.rep('  ', depth), line, node_type, line_nr, end_row + 1)
  end

  local function walk(node, depth)
    if #items >= 120 then
      return
    end

    add_node(node, depth)

    for child in node:iter_children() do
      if child:named() then
        walk(child, depth + 1)
        if #items >= 120 then
          return
        end
      end
    end
  end

  walk(root, 0)

  if #items == 0 then
    return nil
  end

  return items
end

local function get_structure_map(bufnr)
  local ts_map = get_treesitter_structure_map(bufnr)
  if ts_map and #ts_map > 0 then
    return ts_map
  end

  local total = api.nvim_buf_line_count(bufnr)
  local all_lines = collect_lines(bufnr, 1, total)
  local map = {}

  for index, line in ipairs(all_lines) do
    if line_matches_definition(line) then
      map[#map + 1] = string.format('%d: %s', index, vim.trim(line))
    end
    if #map >= 120 then
      break
    end
  end

  return map
end

local function extract_identifiers(lines)
  local seen = {}
  local identifiers = {}

  for _, line in ipairs(lines or {}) do
    for word in line:gmatch('[%a_][%w_]+') do
      if #word >= 3 and not keyword_blocklist[word] and not seen[word] then
        seen[word] = true
        identifiers[#identifiers + 1] = word
      end
      if #identifiers >= 30 then
        return identifiers
      end
    end
  end

  return identifiers
end

local function get_relevant_symbol_lines(bufnr, target_lines)
  local identifiers = extract_identifiers(target_lines)
  if #identifiers == 0 then
    return nil
  end

  local total = api.nvim_buf_line_count(bufnr)
  local all_lines = collect_lines(bufnr, 1, total)
  local matches = {}

  for index, line in ipairs(all_lines) do
    if line_matches_definition(line) then
      for _, ident in ipairs(identifiers) do
        if line:match('%f[%w_]' .. vim.pesc(ident) .. '%f[^%w_]') then
          matches[#matches + 1] = string.format('%d: %s', index, vim.trim(line))
          break
        end
      end
    end
    if #matches >= 25 then
      break
    end
  end

  if #matches == 0 then
    return nil
  end

  return matches
end

local function get_file_context(bufnr, focus_start, focus_end)
  local total = api.nvim_buf_line_count(bufnr)
  if total <= 500 then
    return collect_lines(bufnr, 1, total)
  end

  local sections = {}
  local head_end = math.min(40, total)
  vim.list_extend(sections, collect_lines(bufnr, 1, head_end))
  table.insert(sections, '...')

  local mid_start = math.max(1, focus_start - 40)
  local mid_end = math.min(total, focus_end + 40)
  vim.list_extend(sections, collect_lines(bufnr, mid_start, mid_end))

  if mid_end < total - 40 then
    table.insert(sections, '...')
    vim.list_extend(sections, collect_lines(bufnr, math.max(total - 39, 1), total))
  end

  return sections
end

local function get_current_scope(bufnr, row)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil
  end

  local trees = parser:parse()
  if not trees or not trees[1] then
    return nil
  end

  local node = trees[1]:root():named_descendant_for_range(row - 1, 0, row - 1, 0)
  while node do
    local node_type = node:type()
    for _, pattern in ipairs(scope_node_patterns) do
      if node_type:find(pattern, 1, true) then
        local start_row, _, end_row, _ = node:range()
        return start_row + 1, end_row
      end
    end
    node = node:parent()
  end

  return nil
end

local function get_enclosing_scope(bufnr, line1, line2)
  local scope_start, scope_end = get_current_scope(bufnr, math.floor((line1 + line2) / 2))
  if not scope_start or not scope_end then
    return nil
  end

  if scope_start == line1 and scope_end == line2 then
    return nil
  end

  if scope_start <= line1 and scope_end >= line2 then
    return scope_start, scope_end
  end

  return nil
end

local function get_semantic_fallback_range(bufnr, row)
  local total = api.nvim_buf_line_count(bufnr)
  local start_line = row
  local end_line = row

  while start_line > 1 do
    local prev = api.nvim_buf_get_lines(bufnr, start_line - 2, start_line - 1, false)[1] or ''
    if vim.trim(prev) == '' then
      break
    end
    start_line = start_line - 1
  end

  while end_line < total do
    local next_line = api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1] or ''
    if vim.trim(next_line) == '' then
      break
    end
    end_line = end_line + 1
  end

  return start_line, end_line
end

local function set_status(bufnr, row, text)
  if not api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  return api.nvim_buf_set_extmark(bufnr, ns, math.max(row - 1, 0), -1, {
    virt_text = { { ' ' .. text .. ' ', 'Comment' } },
    virt_text_pos = 'eol',
  })
end

local function clear_status(bufnr)
  if api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
end

local function get_visual_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local line1 = start_pos[2]
  local line2 = end_pos[2]
  if line1 == 0 or line2 == 0 then
    return nil
  end
  if line1 > line2 then
    line1, line2 = line2, line1
  end
  return line1, line2
end

local function prompt_user()
  local ok, input = pcall(vim.fn.input, 'OpenCode Edit: ')
  vim.cmd('redraw')
  if not ok then
    return nil
  end
  input = vim.trim(input or '')
  if input == '' then
    return nil
  end
  return input
end

local function replace_range(bufnr, line1, line2, lines)
  api.nvim_buf_set_lines(bufnr, line1 - 1, line2, false, lines)
end

local function insert_at(bufnr, row, lines, replace_blank)
  if replace_blank then
    api.nvim_buf_set_lines(bufnr, row - 1, row, false, lines)
  else
    api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  end
end

local function run_request(opts)
  ensure_opencode(function(bin)
    if not bin then
      clear_status(opts.bufnr)
      return
    end

    set_status(opts.bufnr, opts.status_row, active_model_label() .. ' thinking...')

    local args = {
      bin,
      'run',
      opts.prompt,
      '--format',
      'json',
    }

    local model = normalize_model(state.model)
    if model then
      table.insert(args, '--model')
      table.insert(args, model)
    end

    local variant = normalize_variant(state.variant)
    if variant then
      table.insert(args, '--variant')
      table.insert(args, variant)
    end

    vim.system(args, { text = true, cwd = current_workdir(opts.bufnr) }, function(obj)
      vim.schedule(function()
        clear_status(opts.bufnr)

        if obj.code ~= 0 then
          local message = (obj.stderr and vim.trim(obj.stderr) ~= '' and vim.trim(obj.stderr))
            or (obj.stdout and vim.trim(obj.stdout) ~= '' and vim.trim(obj.stdout))
            or 'opencode request failed'
          notify(message, vim.log.levels.ERROR)
          return
        end

        local text = extract_opencode_text(obj.stdout)
        if not text or vim.trim(text) == '' then
          notify('opencode returned no code', vim.log.levels.WARN)
          return
        end

        local cleaned = trim_fences(text)
        local lines = vim.split(cleaned, '\n', { plain = true })

        if opts.kind == 'visual' then
          replace_range(opts.bufnr, opts.line1, opts.line2, lines)
        else
          insert_at(opts.bufnr, opts.line1, lines, opts.replace_blank)
        end
      end)
    end)
  end)
end

local function build_visual_prompt(bufnr, line1, line2, instruction)
  local filetype = vim.bo[bufnr].filetype
  local selected = api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local ctx_start, ctx_end, local_context = get_local_context(bufnr, math.floor((line1 + line2) / 2), 20, 20)
  local scope_start, scope_end = get_enclosing_scope(bufnr, line1, line2)
  local scope_lines = nil
  if scope_start and scope_end and (scope_end - scope_start) <= 250 then
    scope_lines = collect_lines(bufnr, scope_start, scope_end)
  end
  local file_context = get_file_context(bufnr, scope_start or line1, scope_end or line2)
  local structure_map = is_large_file(bufnr) and get_structure_map(bufnr) or nil
  local relevant_symbols = is_large_file(bufnr) and get_relevant_symbol_lines(bufnr, selected) or nil
  local sections = {
    'You are editing code.',
    'Return only the replacement code.',
    'Do not include markdown fences or explanation.',
    'Filetype: ' .. filetype,
    'Instruction: ' .. instruction,
    string.format('Selected lines: %d-%d', line1, line2),
    format_section('Selected code', selected),
    format_section(scope_start and string.format('Enclosing scope (%d-%d)', scope_start, scope_end) or 'Enclosing scope', scope_lines),
    format_section(string.format('Nearby context (%d-%d)', ctx_start, ctx_end), local_context),
    format_section('File structure map', structure_map),
    format_section('Relevant symbol definitions', relevant_symbols),
    format_section('File context', file_context),
  }
  return table.concat(vim.tbl_filter(function(item)
    return item ~= nil
  end, sections), '\n\n')
end

local function build_insert_prompt(bufnr, row, instruction, replace_blank)
  local filetype = vim.bo[bufnr].filetype
  local start_row, end_row, context = get_local_context(bufnr, row, 20, 20)
  local scope_start, scope_end = get_current_scope(bufnr, row)
  local scope_lines = nil
  if scope_start and scope_end and (scope_end - scope_start) <= 200 then
    scope_lines = collect_lines(bufnr, scope_start, scope_end)
  end
  local file_context = get_file_context(bufnr, scope_start or row, scope_end or row)
  local structure_map = is_large_file(bufnr) and get_structure_map(bufnr) or nil
  local marker_index = row - start_row + 1
  local marker = '__CURSOR__'

  if replace_blank then
    context[marker_index] = marker
  else
    table.insert(context, marker_index + 1, marker)
  end

  local relevant_symbols = is_large_file(bufnr) and get_relevant_symbol_lines(bufnr, context) or nil

  local sections = {
    'You are inserting code into an existing file.',
    'Return only the code to insert at the marker.',
    'Do not include the marker, markdown fences, or explanation.',
    'Filetype: ' .. filetype,
    'Instruction: ' .. instruction,
    format_section('Insertion context', context),
    format_section(scope_start and string.format('Current scope (%d-%d)', scope_start, scope_end) or 'Current scope', scope_lines),
    format_section('File structure map', structure_map),
    format_section('Relevant symbol definitions', relevant_symbols),
    format_section('File context', file_context),
  }
  return table.concat(vim.tbl_filter(function(item)
    return item ~= nil
  end, sections), '\n\n')
end

local function build_scope_edit_prompt(bufnr, line1, line2, instruction)
  local filetype = vim.bo[bufnr].filetype
  local target = collect_lines(bufnr, line1, line2)
  local ctx_start, ctx_end, local_context = get_local_context(bufnr, math.floor((line1 + line2) / 2), 25, 25)
  local file_context = get_file_context(bufnr, line1, line2)
  local structure_map = is_large_file(bufnr) and get_structure_map(bufnr) or nil
  local relevant_symbols = is_large_file(bufnr) and get_relevant_symbol_lines(bufnr, target) or nil
  local sections = {
    'You are editing code around the cursor.',
    'Return only the replacement code for the target block.',
    'Do not include markdown fences or explanation.',
    'Filetype: ' .. filetype,
    'Instruction: ' .. instruction,
    string.format('Target lines: %d-%d', line1, line2),
    format_section('Target block', target),
    format_section(string.format('Nearby context (%d-%d)', ctx_start, ctx_end), local_context),
    format_section('File structure map', structure_map),
    format_section('Relevant symbol definitions', relevant_symbols),
    format_section('File context', file_context),
  }
  return table.concat(vim.tbl_filter(function(item)
    return item ~= nil
  end, sections), '\n\n')
end

function M.edit_normal()
  local bufnr = api.nvim_get_current_buf()
  local row = api.nvim_win_get_cursor(0)[1]
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
  local instruction = prompt_user()
  if not instruction then
    return
  end

  local replace_blank = vim.trim(line) == ''
  set_status(bufnr, row, active_model_label() .. ' queued...')

  if replace_blank then
    run_request({
      bufnr = bufnr,
      kind = 'insert',
      line1 = row,
      replace_blank = true,
      status_row = row,
      prompt = build_insert_prompt(bufnr, row, instruction, true),
    })
    return
  end

  local scope_start, scope_end = get_current_scope(bufnr, row)
  if not scope_start or not scope_end or scope_end < scope_start then
    scope_start, scope_end = get_semantic_fallback_range(bufnr, row)
  end

  if not scope_start or not scope_end or scope_end < scope_start then
    scope_start, scope_end = row, row
  end

  run_request({
    bufnr = bufnr,
    kind = 'visual',
    line1 = scope_start,
    line2 = scope_end,
    status_row = scope_start,
    prompt = build_scope_edit_prompt(bufnr, scope_start, scope_end, instruction),
  })
end

function M.edit_visual()
  local bufnr = api.nvim_get_current_buf()
  local line1, line2 = get_visual_range()
  if not line1 or not line2 then
    notify('No selection found', vim.log.levels.WARN)
    return
  end

  local instruction = prompt_user()
  if not instruction then
    return
  end

  set_status(bufnr, line1, active_model_label() .. ' queued...')
  run_request({
    bufnr = bufnr,
    kind = 'visual',
    line1 = line1,
    line2 = line2,
    status_row = line1,
    prompt = build_visual_prompt(bufnr, line1, line2, instruction),
  })
end

function M.pick_model()
  ensure_opencode(function(bin)
    if not bin then
      return
    end

    vim.system({ bin, 'models', '--verbose' }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          local message = (obj.stderr and vim.trim(obj.stderr) ~= '' and vim.trim(obj.stderr)) or 'Failed to fetch opencode models'
          notify(message, vim.log.levels.ERROR)
          return
        end

        local verbose_models = parse_verbose_models(obj.stdout)
        local models = {}
        for _, item in ipairs(verbose_models) do
          local full_id = item.full_id
          local variants = type(item.variants) == 'table' and item.variants or {}

          table.insert(models, {
            id = full_id,
            variant = nil,
            label = full_id .. ' [default]',
          })

          for variant_name, _ in pairs(variants) do
            table.insert(models, {
              id = full_id,
              variant = variant_name,
              label = full_id .. ' [' .. variant_name .. ']',
            })
          end
        end

        if #models == 0 then
          notify('No opencode models available', vim.log.levels.WARN)
          return
        end

        table.sort(models, function(a, b)
          return a.label < b.label
        end)

        vim.ui.select(models, {
          prompt = 'OpenCode Model',
          format_item = function(item)
            if current_choice_matches(item.id, item.variant) then
              return item.label .. ' [current]'
            end
            return item.label
          end,
        }, function(choice)
          if not choice then
            return
          end

          state.model = choice.id
          state.variant = choice.variant
          save_state()
          notify('Model set to ' .. active_model_label())
        end)
      end)
    end)
  end)
end

function M.setup()
  load_state()

  vim.keymap.set('n', '<leader>k', M.edit_normal, { noremap = true, silent = true })
  vim.keymap.set('v', '<leader>k', M.edit_visual, { noremap = true, silent = true })
  vim.keymap.set('n', '<leader>km', M.pick_model, { noremap = true, silent = true })
  vim.api.nvim_create_user_command('CmdKHealth', function()
    M.healthcheck()
  end, { desc = 'Check OpenCode Cmd-K health' })
end

return M
