local M = {}

local api = vim.api
local title = 'Pi Cmd-K'
local ns = api.nvim_create_namespace('pi_cmdk')
local state_path = vim.fn.stdpath('state') .. '/pi_cmdk.json'
local pi_cmdk_system_prompt = table.concat({
  'You are a precise code editing engine embedded in Neovim.',
  'Return only the requested code.',
  'Do not include markdown fences, explanations, preambles, or apologies.',
  'Preserve the surrounding style, indentation, and language semantics.',
  'Do not include unchanged surrounding code unless it is part of the requested replacement range.',
  'If the instruction is impossible or ambiguous, return the original code unchanged.',
}, '\n')
local pi_default_model = 'opencode-go/kimi-k2.6'
local pi_thinking_levels = { 'off', 'minimal', 'low', 'medium', 'high', 'xhigh' }
local pi_default_thinking = nil
local pi_thinking_level_set = {}
for _, level in ipairs(pi_thinking_levels) do
  pi_thinking_level_set[level] = true
end
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
  thinking = nil,
  current_request = nil,
  history = {},
}

local function normalize_model(model)
  if type(model) ~= 'string' then
    return nil
  end

  model = vim.trim(model)
  if model == '' then
    return nil
  end

  return model
end

local function normalize_thinking(thinking)
  if type(thinking) ~= 'string' then
    return nil
  end

  thinking = vim.trim(thinking)
  if thinking == '' or thinking == 'default' then
    return nil
  end

  if pi_thinking_level_set[thinking] then
    return thinking
  end

  return nil
end

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = title })
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
    state.model = normalize_model(saved.model)
    state.thinking = normalize_thinking(saved.thinking or saved.variant)
  end
end

local function save_state()
  write_json(state_path, {
    model = normalize_model(state.model),
    thinking = normalize_thinking(state.thinking),
  })
end

local function active_model_label()
  local model = normalize_model(state.model) or pi_default_model
  local thinking = normalize_thinking(state.thinking)
  return thinking and (model .. ' [' .. thinking .. ']') or model
end

local function parse_pi_models(output)
  local entries = {}
  local seen = {}

  for _, line in ipairs(vim.split(output or '', '\n', { plain = true })) do
    local provider, model, _, _, thinking = line:match('^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)')
    if provider and provider ~= 'provider' and model ~= 'model' then
      local id = provider .. '/' .. model
      if not seen[id] then
        seen[id] = true
        entries[#entries + 1] = {
          id = id,
          supports_thinking = thinking == 'yes',
        }
      end
    end
  end

  return entries
end

local function current_choice_matches(model, thinking)
  return normalize_model(state.model) == normalize_model(model) and normalize_thinking(state.thinking) == normalize_thinking(thinking)
end

local function get_pi_bin()
  local bin = vim.fn.exepath('pi')
  if bin ~= '' then
    return bin
  end

  return nil
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

  local bin = get_pi_bin()
  if bin then
    lines[#lines + 1] = { 'pi found: ' .. bin, ok_level }
  else
    lines[#lines + 1] = { 'pi not found on PATH', err_level }
  end

  local auth = read_json(vim.fn.expand('~/.pi/agent/auth.json'))
  if type(auth) == 'table' then
    local providers = {}
    for name, data in pairs(auth) do
      if type(data) == 'table' then
        providers[#providers + 1] = name
      end
    end
    table.sort(providers)
    if #providers > 0 then
      lines[#lines + 1] = { 'pi auth providers: ' .. table.concat(providers, ', '), ok_level }
    else
      lines[#lines + 1] = { 'pi auth.json exists but has no provider entries', warn_level }
    end
  else
    lines[#lines + 1] = { 'pi auth.json not found; run pi /login or configure an API key if needed', warn_level }
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

  health.start(title)
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

local function ensure_pi(callback)
  if type(vim.system) ~= 'function' then
    notify('Neovim is too old for this Cmd-K plugin. Update to a newer stable Neovim.', vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local bin = get_pi_bin()
  if not bin then
    notify('pi is not installed or not on PATH.', vim.log.levels.ERROR)
    callback(nil)
    return
  end

  callback(bin)
end

local function extract_pi_text(stdout)
  local text = stdout or ''
  if vim.trim(text) == '' then
    return nil
  end

  return text:gsub('%s+$', '')
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
  local col1 = start_pos[3]
  local line2 = end_pos[2]
  local col2 = end_pos[3]
  if line1 == 0 or line2 == 0 then
    return nil
  end

  if line1 > line2 or (line1 == line2 and col1 > col2) then
    line1, line2 = line2, line1
    col1, col2 = col2, col1
  end

  return {
    line1 = line1,
    line2 = line2,
    col1 = math.max(col1, 1),
    col2 = math.max(col2, 1),
    mode = vim.fn.visualmode(),
  }
end

local function prompt_user()
  local ok, input = pcall(vim.fn.input, 'Pi Edit: ')
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

local function is_charwise_visual(opts)
  return opts and opts.mode == 'v' and opts.col1 and opts.col2
end

local function charwise_cols(opts)
  local start_line = api.nvim_buf_get_lines(opts.bufnr, opts.line1 - 1, opts.line1, false)[1] or ''
  local end_line = api.nvim_buf_get_lines(opts.bufnr, opts.line2 - 1, opts.line2, false)[1] or ''
  local start_col = math.min(math.max(opts.col1 - 1, 0), #start_line)
  local end_col = math.min(math.max(opts.col2, 0), #end_line)
  return start_col, end_col
end

local function get_target_lines(opts)
  if opts.kind == 'visual' then
    if is_charwise_visual(opts) then
      local start_col, end_col = charwise_cols(opts)
      return api.nvim_buf_get_text(opts.bufnr, opts.line1 - 1, start_col, opts.line2 - 1, end_col, {})
    end
    return collect_lines(opts.bufnr, opts.line1, opts.line2)
  end

  if opts.replace_blank then
    return collect_lines(opts.bufnr, opts.line1, opts.line1)
  end

  return {}
end

local function replace_range(opts, lines)
  if is_charwise_visual(opts) then
    local start_col, end_col = charwise_cols(opts)
    api.nvim_buf_set_text(opts.bufnr, opts.line1 - 1, start_col, opts.line2 - 1, end_col, lines)
  else
    api.nvim_buf_set_lines(opts.bufnr, opts.line1 - 1, opts.line2, false, lines)
  end
end

local function insert_at(bufnr, row, lines, replace_blank)
  if replace_blank then
    api.nvim_buf_set_lines(bufnr, row - 1, row, false, lines)
  else
    api.nvim_buf_set_lines(bufnr, row, row, false, lines)
  end
end

local function remember_history(opts, generated_lines)
  local entry = {
    time = os.date('%Y-%m-%d %H:%M:%S'),
    file = api.nvim_buf_is_valid(opts.bufnr) and api.nvim_buf_get_name(opts.bufnr) or '',
    kind = opts.kind,
    line1 = opts.line1,
    line2 = opts.line2,
    prompt = opts.prompt,
    original = opts.original_lines or {},
    generated = generated_lines,
  }
  table.insert(state.history, 1, entry)
  while #state.history > 20 do
    table.remove(state.history)
  end
end

local function apply_generated(opts, lines)
  if not api.nvim_buf_is_valid(opts.bufnr) then
    notify('Target buffer no longer exists', vim.log.levels.WARN)
    return false
  end

  if api.nvim_buf_get_changedtick(opts.bufnr) ~= opts.changedtick then
    notify('Buffer changed while Pi was thinking; skipped stale edit. Retry Cmd-K.', vim.log.levels.WARN)
    return false
  end

  if opts.kind == 'visual' then
    replace_range(opts, lines)
  else
    insert_at(opts.bufnr, opts.line1, lines, opts.replace_blank)
  end
  remember_history(opts, lines)
  return true
end

local function run_request(opts)
  ensure_pi(function(bin)
    if not bin then
      clear_status(opts.bufnr)
      return
    end

    if state.current_request then
      notify('Pi Cmd-K request already running. Use :CmdKCancel first.', vim.log.levels.WARN)
      return
    end

    opts.changedtick = opts.changedtick or api.nvim_buf_get_changedtick(opts.bufnr)
    opts.original_lines = opts.original_lines or get_target_lines(opts)

    set_status(opts.bufnr, opts.status_row, active_model_label() .. ' thinking...')

    local args = {
      bin,
      '--print',
      '--no-session',
      '--no-tools',
      '--no-context-files',
      '--no-skills',
      '--no-prompt-templates',
      '--no-extensions',
      '--system-prompt',
      pi_cmdk_system_prompt,
    }

    local model = normalize_model(state.model) or pi_default_model
    if model then
      table.insert(args, '--model')
      table.insert(args, model)
    end

    local thinking = normalize_thinking(state.thinking) or pi_default_thinking
    if thinking then
      table.insert(args, '--thinking')
      table.insert(args, thinking)
    end

    table.insert(args, opts.prompt)

    local request = { bufnr = opts.bufnr, cancelled = false, job = nil }
    state.current_request = request
    request.job = vim.system(args, { text = true, cwd = current_workdir(opts.bufnr), env = { PI_SKIP_VERSION_CHECK = '1', PI_TELEMETRY = '0' } }, function(obj)
      vim.schedule(function()
        if state.current_request == request then
          state.current_request = nil
        end
        clear_status(opts.bufnr)

        if request.cancelled then
          return
        end

        if obj.code ~= 0 then
          local message = (obj.stderr and vim.trim(obj.stderr) ~= '' and vim.trim(obj.stderr))
            or (obj.stdout and vim.trim(obj.stdout) ~= '' and vim.trim(obj.stdout))
            or 'pi request failed'
          notify(message, vim.log.levels.ERROR)
          return
        end

        local text = extract_pi_text(obj.stdout)
        if not text or vim.trim(text) == '' then
          notify('pi returned no code', vim.log.levels.WARN)
          return
        end

        local cleaned = trim_fences(text)
        local lines = vim.split(cleaned, '\n', { plain = true })
        apply_generated(opts, lines)
      end)
    end)
  end)
end

function M.cancel()
  local request = state.current_request
  if not request then
    notify('No Pi Cmd-K request running', vim.log.levels.INFO)
    return
  end

  request.cancelled = true
  if request.job and type(request.job.kill) == 'function' then
    pcall(function()
      request.job:kill(15)
    end)
  end
  state.current_request = nil
  clear_status(request.bufnr)
  notify('Cancelled Pi Cmd-K request')
end

function M.show_history()
  if #state.history == 0 then
    notify('No Pi Cmd-K history yet')
    return
  end

  local lines = {}
  for index, entry in ipairs(state.history) do
    lines[#lines + 1] = string.format('#%d %s %s:%s-%s %s', index, entry.time, entry.file ~= '' and entry.file or '[No Name]', entry.line1 or '?', entry.line2 or entry.line1 or '?', entry.kind or '')
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Prompt:'
    vim.list_extend(lines, vim.split(entry.prompt or '', '\n', { plain = true }))
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Original:'
    vim.list_extend(lines, entry.original or {})
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Generated:'
    vim.list_extend(lines, entry.generated or {})
    lines[#lines + 1] = string.rep('-', 80)
    lines[#lines + 1] = ''
  end

  vim.cmd('vnew')
  local bufnr = api.nvim_get_current_buf()
  pcall(api.nvim_buf_set_name, bufnr, 'Pi Cmd-K History ' .. os.time())
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].buftype = 'nofile'
  vim.bo[bufnr].bufhidden = 'wipe'
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = 'markdown'
  vim.bo[bufnr].modifiable = false
end

local function build_visual_prompt(bufnr, range, instruction)
  local filetype = vim.bo[bufnr].filetype
  local line1 = range.line1
  local line2 = range.line2
  local large = is_large_file(bufnr)
  local selected = get_target_lines({
    bufnr = bufnr,
    kind = 'visual',
    line1 = line1,
    line2 = line2,
    col1 = range.col1,
    col2 = range.col2,
    mode = range.mode,
  })
  local ctx_start, ctx_end, local_context = get_local_context(bufnr, math.floor((line1 + line2) / 2), 20, 20)
  if not large then
    local_context = nil
  end
  local scope_start, scope_end = get_enclosing_scope(bufnr, line1, line2)
  local scope_lines = nil
  if large and scope_start and scope_end and (scope_end - scope_start) <= 250 then
    scope_lines = collect_lines(bufnr, scope_start, scope_end)
  end
  local file_context = get_file_context(bufnr, scope_start or line1, scope_end or line2)
  local structure_map = large and get_structure_map(bufnr) or nil
  local relevant_symbols = large and get_relevant_symbol_lines(bufnr, selected) or nil
  local selection_label = is_charwise_visual(range) and string.format('Selected range: %d:%d-%d:%d', line1, range.col1, line2, range.col2) or string.format('Selected lines: %d-%d', line1, line2)
  local sections = {
    'You are editing code.',
    'Return only the replacement code.',
    'Do not include markdown fences or explanation.',
    'Filetype: ' .. filetype,
    'Instruction: ' .. instruction,
    selection_label,
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
  local large = is_large_file(bufnr)
  local scope_start, scope_end = get_current_scope(bufnr, row)
  local scope_lines = nil
  if large and scope_start and scope_end and (scope_end - scope_start) <= 200 then
    scope_lines = collect_lines(bufnr, scope_start, scope_end)
  end
  local file_context = get_file_context(bufnr, scope_start or row, scope_end or row)
  local structure_map = large and get_structure_map(bufnr) or nil
  local marker_index = row - start_row + 1
  local marker = '__CURSOR__'

  if replace_blank then
    context[marker_index] = marker
  else
    table.insert(context, marker_index + 1, marker)
  end

  local relevant_symbols = large and get_relevant_symbol_lines(bufnr, context) or nil

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
  local large = is_large_file(bufnr)
  local ctx_start, ctx_end, local_context = get_local_context(bufnr, math.floor((line1 + line2) / 2), 25, 25)
  if not large then
    local_context = nil
  end
  local file_context = get_file_context(bufnr, line1, line2)
  local structure_map = large and get_structure_map(bufnr) or nil
  local relevant_symbols = large and get_relevant_symbol_lines(bufnr, target) or nil
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
  local range = get_visual_range()
  if not range then
    notify('No selection found', vim.log.levels.WARN)
    return
  end

  local instruction = prompt_user()
  if not instruction then
    return
  end

  set_status(bufnr, range.line1, active_model_label() .. ' queued...')
  run_request({
    bufnr = bufnr,
    kind = 'visual',
    line1 = range.line1,
    line2 = range.line2,
    col1 = range.col1,
    col2 = range.col2,
    mode = range.mode,
    status_row = range.line1,
    prompt = build_visual_prompt(bufnr, range, instruction),
  })
end

function M.pick_model()
  ensure_pi(function(bin)
    if not bin then
      return
    end

    vim.system({ bin, '--list-models' }, { text = true, env = { PI_SKIP_VERSION_CHECK = '1', PI_TELEMETRY = '0' } }, function(obj)
      vim.schedule(function()
        if obj.code ~= 0 then
          local message = (obj.stderr and vim.trim(obj.stderr) ~= '' and vim.trim(obj.stderr)) or 'Failed to fetch pi models'
          notify(message, vim.log.levels.ERROR)
          return
        end

        local entries = parse_pi_models((obj.stdout or '') .. '\n' .. (obj.stderr or ''))
        local models = {
          {
            id = nil,
            thinking = nil,
            label = pi_default_thinking and (pi_default_model .. ' [' .. pi_default_thinking .. ']') or (pi_default_model .. ' [default]'),
          },
        }

        for _, item in ipairs(entries) do
          table.insert(models, {
            id = item.id,
            thinking = nil,
            label = pi_default_thinking and (item.id .. ' [' .. pi_default_thinking .. ']') or (item.id .. ' [default]'),
          })

          if item.supports_thinking then
            for _, level in ipairs(pi_thinking_levels) do
              if level ~= pi_default_thinking then
                table.insert(models, {
                  id = item.id,
                  thinking = level,
                  label = item.id .. ' [' .. level .. ']',
                })
              end
            end
          end
        end

        if #models == 1 then
          notify('No pi models available', vim.log.levels.WARN)
          return
        end

        table.sort(models, function(a, b)
          if a.id == nil then
            return true
          end
          if b.id == nil then
            return false
          end
          return a.label < b.label
        end)

        vim.ui.select(models, {
          prompt = 'Pi Model',
          format_item = function(item)
            if current_choice_matches(item.id, item.thinking) then
              return item.label .. ' [current]'
            end
            return item.label
          end,
        }, function(choice)
          if not choice then
            return
          end

          state.model = choice.id
          state.thinking = choice.thinking
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
  vim.keymap.set('n', '<leader>kc', M.cancel, { noremap = true, silent = true, desc = 'Cancel Pi Cmd-K' })
  vim.keymap.set('n', '<leader>kh', M.show_history, { noremap = true, silent = true, desc = 'Pi Cmd-K history' })
  vim.api.nvim_create_user_command('CmdKHealth', function()
    M.healthcheck()
  end, { desc = 'Check Pi Cmd-K health' })
  vim.api.nvim_create_user_command('CmdKCancel', function()
    M.cancel()
  end, { desc = 'Cancel running Pi Cmd-K request' })
  vim.api.nvim_create_user_command('CmdKHistory', function()
    M.show_history()
  end, { desc = 'Show Pi Cmd-K edit history' })
end

return M
