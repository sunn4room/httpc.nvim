---@class httpc.Httpc
---@field run fun(pos: httpc.Pos | nil)
---@field clear fun(pos: httpc.Pos | nil)
---@field setup fun(opts: httpc.Opts | nil)

---@class httpc.Opts
---@field animation httpc.Animation | nil
---@field magics table<string, httpc.Magic> | nil
---@field patterns table<string, string> | nil

---@class httpc.Animation
---@field spinner string[] | httpc.AnimationSpinner | nil
---@field interval integer | nil

---@alias httpc.Magic fun(args: string[]): string

---@alias httpc.AnimationSpinner (([string, string])[])[]

---@class httpc.Pos
---@field buf integer
---@field row integer
---@field col integer

---@class httpc.Context
---@field spinner [ integer, integer, integer ]
---@field timer uv_timer_t
---@field process vim.SystemObj

---@class httpc.Error
---@field reason string

---@param msg string
---@param level integer | nil
local log = function(msg, level)
  vim.notify("[Httpc] " .. msg, level)
end

---@type httpc.Opts
local default_opts = {
  animation = {
    spinner = {
      { { " | ", "Comment" } },
      { { " / ", "Comment" } },
      { { " - ", "Comment" } },
      { { " \\ ", "Comment" } },
    },
    interval = 100,
  },
  magics = {
    processEnv = function(args)
      local key = args[1]
      local fallback = args[2]
      if not key then
        error({ reason = "you may forget to give a key for processEnv" })
      end
      local result = fallback
      result = vim.env[key] --[[@as string | nil]]
      if not result then
        error({ reason = "cannot get process env " .. key })
      end
      return result
    end,
    randomInt = function(args)
      local min = math.floor(tonumber(args[1]) or 0)
      local max = math.floor(tonumber(args[2]) or (min + 1))
      return tostring(math.random(min, max))
    end,
    datetime = function(args)
      return os.date(args[1]) --[[@as string]]
    end,
    timestamp = function()
      return tostring(os.time())
    end,
    urlencode = function(args)
      return select(1, string.gsub(vim.fn.join(args, " "), "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02x", string.byte(c))
      end))
    end,
  },
  patterns = {
    json = "^application/.*json.*$",
    xml = "^application/.*xml.*$",
    html = "^text/.*html.*$",
    css = "^text/.*css.*$",
    javascript = "^text/.*javascript.*$",
  },
}

---@type httpc.Opts
local user_opts = default_opts

---@param pos httpc.Pos | nil
---@return TSNode node
---@return integer buf
local get_request = function(pos)
  if not pos then
    local cursor = vim.api.nvim_win_get_cursor(0)
    pos = {
      buf = 0,
      row = cursor[1] - 1,
      col = cursor[2],
    }
  end
  if vim.api.nvim_get_option_value("filetype", { buf = pos.buf }) ~= "http" then
    error({ reason = "the filetype is not 'http'" })
  end
  local has_node, node = pcall(vim.treesitter.get_node, {
    bufnr = pos.buf,
    pos = { pos.row, pos.col },
  })
  if not has_node or not node then
    error({ reason = "request node not found" })
  end
  while node and node:type() ~= "request" do
    node = node:parent()
  end
  if not node then
    error({ reason = "request node not found" })
  end
  return node, pos.buf
end

---@type httpc.Context | nil
local context = nil

local clear_ctx = function()
  if context then
    if not context.process:is_closing() then
      context.process:kill(9)
    end
    if not context.timer:is_closing() then
      context.timer:stop()
      context.timer:close()
    end
    local spinner = context.spinner
    vim.schedule(function()
      vim.api.nvim_buf_del_extmark(unpack(spinner))
    end)
    context = nil
  end
end

---@param query vim.treesitter.Query
local add_body_highlights = function(chunks, body, query)
  local parser = vim.treesitter.get_string_parser(body, query.lang)
  local root = parser:parse(true)[1]:root()

  local groups = {}
  groups[1] = ""
  groups[#body + 1] = ""
  local stack = {}
  stack[1] = { #body, "" }
  for id, node in query:iter_captures(root, body) do
    local group = "@" .. query.captures[id]
    local _, _, s, _, _, e = node:range(true)
    while stack[#stack][1] < e do
      stack[#stack] = nil
    end
    groups[s + 1] = group
    if groups[e + 1] == nil then
      groups[e + 1] = stack[#stack][2]
    end
    stack[#stack + 1] = { e, group }
  end

  local idx = 1
  local group = groups[1]
  groups[1] = nil
  for i, g in pairs(groups) do
    table.insert(chunks, { body:sub(idx, i - 1), group })
    idx = i
    group = g
  end
end

---@param node TSNode
---@param buf integer
local run_request = function(node, buf)
  if vim.fn.executable("curl") ~= 1 then
    error({ reason = "curl is not executable" })
  end
  ---@type string[]
  local cmd = { "curl", "-i", "-s", "-S", "-w", " %{time_total}" }
  ---@type table<string, string>
  local variable_cache = {}
  ---@type table<string, string> | nil
  local env_variable_cache = nil
  ---@type fun(origin: string, cur_node: TSNode | nil): string
  local parse_variable
  parse_variable = function(origin, target_node)
    ---@param s string
    ---@return string
    return select(1, origin:gsub("{{(.-)}}", function(s)
      if s:sub(1, 1) == "$" then
        ---@type string[]
        local parts = vim.split(s:sub(2), " ")
        if #parts[1] == 0 then
          error({ reason = "you may forget to set magic function" })
        end
        local magic_fun = user_opts.magics[parts[1]] --[[@as httpc.Magic | nil]]
        if not magic_fun then
          error({ reason = "magic function " .. parts[1] .. " not found" })
        end
        ---@type string[]
        local args = {}
        local part_idx = 2
        while part_idx <= #parts do
          local arg = parts[part_idx]
          part_idx = part_idx + 1
          while arg:sub(-1) == "\\" and part_idx <= #parts do
            arg = arg:sub(1, -2) .. " " .. parts[part_idx]
            part_idx = part_idx + 1
          end
          args[#args + 1] = arg
        end
        return magic_fun(args)
      else
        if variable_cache[s] then return variable_cache[s] end
        if env_variable_cache and env_variable_cache[s] then return env_variable_cache[s] end
        local cur_node = target_node or node
        while true do
          ---@type TSNode | nil
          local prev_node = cur_node:prev_named_sibling()
          if not prev_node then
            local parent_node = cur_node:parent() --[[@as TSNode]]
            local prev_parent_node = parent_node:prev_named_sibling()
            if not prev_parent_node then break end
            local prev_parent_node_count = prev_parent_node:named_child_count()
            if prev_parent_node_count == 0 then break end
            prev_node = prev_parent_node:named_child(prev_parent_node_count - 1) --[[@as TSNode]]
          end
          cur_node = prev_node
          if cur_node:type() == "variable_declaration" then
            local identifier = cur_node:named_child(0)
            if identifier then
              local identifier_text = vim.treesitter.get_node_text(identifier, buf)
              if identifier_text == s then
                local value = cur_node:named_child(1)
                if value then
                  local value_text = parse_variable(vim.treesitter.get_node_text(value, buf), cur_node)
                  variable_cache[identifier_text] = value_text
                  return value_text
                end
              end
            end
          end
        end
        if not env_variable_cache then
          env_variable_cache = {}
          for _, env_name in ipairs({ "http-client.env.json", "http-client.env.json.user" }) do
            local env_path = vim.fn.expand("%:p:h") .. package.config:sub(1, 1) .. env_name
            if vim.fn.filereadable(env_path) == 1 then
              local env_file = assert(io.open(env_path, "r"))
              local env_content = vim.json.decode(env_file:read("*all"))
              env_file:close()
              local env = vim.b.http_client_env or "dev"
              if env_content[env] then
                for k, v in pairs(env_content[env]) do
                  env_variable_cache[k] = tostring(v)
                end
              end
            end
          end
          if env_variable_cache[s] then
            return env_variable_cache[s]
          end
        end
        error({ reason = "variable " .. s .. " not found" })
      end
    end))
  end
  local is_form_data = false
  for cnode in node:iter_children() do
    if cnode:type() == "method" then
      cmd[#cmd + 1] = "-X"
      cmd[#cmd + 1] = parse_variable(vim.treesitter.get_node_text(cnode, buf))
    elseif cnode:type() == "target_url" then
      cmd[#cmd + 1] = parse_variable(vim.treesitter.get_node_text(cnode, buf))
    elseif cnode:type() == "http_version" then
      local version = parse_variable(vim.treesitter.get_node_text(cnode, buf)):sub(6)
      if vim.tbl_contains({ "0.9", "1.0", "1.1", "2", "3" }, version) then
        cmd[#cmd + 1] = "--http" .. version
      end
    elseif cnode:type() == "header" then
      cmd[#cmd + 1] = "-H"
      cmd[#cmd + 1] = vim.treesitter.get_node_text(cnode, buf):gsub("^(.-):(.*)$", function(k, v)
        v = vim.trim(parse_variable(v))
        if k:lower() == "content-type" then
          is_form_data = v == "multipart/form-data"
        end
        return k .. ": " .. v
      end)
    elseif cnode:type() == "external_body" then
      cmd[#cmd + 1] = "-d"
      cmd[#cmd + 1] = parse_variable(vim.treesitter.get_node_text(cnode, buf):gsub("^(<%s+)", "@"))
    elseif cnode:type():match("_body$") then
      if is_form_data then
        for _, form_line in ipairs(vim.split(vim.trim(parse_variable(vim.treesitter.get_node_text(cnode, buf))), "\n")) do
          cmd[#cmd + 1] = "-F"
          cmd[#cmd + 1] = form_line
        end
      else
        cmd[#cmd + 1] = "-d"
        cmd[#cmd + 1] = vim.trim(parse_variable(vim.treesitter.get_node_text(cnode, buf)))
      end
    end
  end
  local ns = vim.api.nvim_create_namespace("httpc-" .. tostring(buf))
  local spinner = user_opts.animation.spinner --[[@as httpc.AnimationSpinner]]
  local interval = user_opts.animation.interval --[[@as integer]]
  local spinner_idx = 0
  local linenr = node:range()
  local extmark = vim.api.nvim_buf_set_extmark(buf, ns, linenr, 0, {
    virt_text_pos = "right_align",
    virt_text = spinner[1],
  })
  local timer = vim.uv.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    spinner_idx = (spinner_idx + 1) % #spinner
    vim.api.nvim_buf_set_extmark(buf, ns, linenr, 0, {
      id = extmark,
      virt_text_pos = "right_align",
      virt_text = spinner[spinner_idx + 1],
    })
  end))
  log(vim.inspect(cmd), 1)
  local process = vim.system(cmd, { text = true }, function(r)
    if r.signal == 0 then
      clear_ctx()
      vim.schedule(function()
        if r.code == 0 then
          if r.stdout and #r.stdout ~= 0 then
            local version, status, headers, body, time =
                r.stdout:match("^([^ ]+) ([^ ]+) \n(.-)\n\n(.*) ([^ ]+)$")
            local chunks = {}
            local time_str = "take " .. time .. " seconds"
            table.insert(chunks, { time_str, "MoreMsg" })
            table.insert(chunks, { "\n" .. ("-"):rep(#time_str) .. "\n", "MoreMsg" })
            table.insert(chunks, { version })
            table.insert(chunks, { " " })
            local status_kind = tonumber(status:sub(1, 1)) --[[@as integer]]
            local status_hl = {
              "DiagnosticHint",
              "DiagnosticOk",
              "DiagnosticInfo",
              "DiagnosticWarn",
              "DiagnosticError",
            }
            table.insert(chunks, { status, status_hl[status_kind] })
            table.insert(chunks, { "\n" })
            ---@type string | nil
            local content_type = nil
            for _, header in ipairs(vim.split(headers, "\n")) do
              local key, value = header:match("^(.-: )(.*)$") --[[@as string, string]]
              table.insert(chunks, { key, "Special" })
              table.insert(chunks, { value })
              table.insert(chunks, { "\n" })
              if key:lower() == "content-type: " then
                content_type = value
              end
            end
            table.insert(chunks, { "\n" })
            ---@type vim.treesitter.Query | nil
            local query = nil
            if content_type then
              for l, p in pairs(user_opts.patterns) do
                if content_type:match(p) then
                  query = vim.treesitter.query.get(l, "highlights")
                  break
                end
              end
            end
            if query then
              add_body_highlights(chunks, body, query)
            else
              table.insert(chunks, { body })
            end
            vim.api.nvim_echo(chunks, true, {})
          else
            vim.api.nvim_echo({ { "stdout is empty", "WarningMsg" } }, true, {})
          end
        else
          if r.stderr and #r.stderr ~= 0 then
            vim.api.nvim_echo({ { r.stderr, "ErrorMsg" } }, true, {})
          else
            vim.api.nvim_echo({ { "stderr is empty", "ErrorMsg" } }, true, {})
          end
        end
      end)
    end
  end)
  context = {
    spinner = { buf, ns, extmark },
    timer = timer,
    process = process,
  }
end

---@type httpc.Httpc
local M = setmetatable({
  ---@param opts httpc.Opts | nil
  setup = function(opts)
    if type(vim.tbl_get(opts or {}, "animation", "spinner", 1)) == "string" then
      ---@cast opts httpc.Opts
      opts.animation.spinner = vim.tbl_map(function(s)
        return { { s, "Comment" } }
      end, opts.animation.spinner)
    end
    user_opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  end,
}, {
  __index = function(_, k)
    local actions = {
      ---@param pos httpc.Pos | nil
      ---@return any
      run = function(pos)
        local node, buf = get_request(pos)
        clear_ctx()
        run_request(node, buf)
      end,
      ---@return any
      cancel = function()
        clear_ctx()
      end,
    }
    if actions[k] then
      ---@param pos httpc.Pos | nil
      return function(pos)
        local is_success, result = pcall(actions[k], pos)
        if not is_success then
          if type(result) == "string" then
            log(string.format("unknow error: %s.", result), 4)
          elseif type(result) == "table" then
            ---@cast result httpc.Error
            log(string.format("error: %s.", result.reason), 4)
          end
          clear_ctx()
        end
      end
    else
      if type(k) == "string" then
        log(string.format("No magic '%s'.", k), 3)
      end
      return function() end
    end
  end,
})

return M
