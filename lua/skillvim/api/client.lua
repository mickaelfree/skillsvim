local M = {}

--- Provider configurations
M.providers = {
  anthropic = {
    url = "https://api.anthropic.com/v1/messages",
    build_headers = function(api_key)
      return {
        "Content-Type: application/json",
        "x-api-key: " .. api_key,
        "anthropic-version: 2023-06-01",
      }
    end,
    build_body = function(request, config)
      return {
        model = request.model or config.options.model,
        max_tokens = request.max_tokens or config.options.max_tokens,
        system = request.system or nil,
        messages = request.messages,
        stream = true,
      }
    end,
    parse_event = M._handle_anthropic_event,
    stop_event = "message_stop",
  },
  groq = {
    url = "https://api.groq.com/openai/v1/chat/completions",
    build_headers = function(api_key)
      return {
        "Content-Type: application/json",
        "Authorization: Bearer " .. api_key,
      }
    end,
    build_body = function(request, config)
      local messages = {}
      -- OpenAI format: system message goes as first message
      if request.system then
        table.insert(messages, { role = "system", content = request.system })
      end
      for _, msg in ipairs(request.messages) do
        table.insert(messages, msg)
      end
      return {
        model = request.model or config.options.model,
        max_tokens = request.max_tokens or config.options.max_tokens,
        messages = messages,
        stream = true,
      }
    end,
    stop_event = "[DONE]",
  },
}

--- Send a streaming request
--- @param request table {model, max_tokens, system, messages}
--- @param callbacks table {on_start, on_delta, on_complete, on_error}
--- @return vim.SystemObj|nil handle
function M.stream(request, callbacks)
  local config = require("skillvim.config")
  local api_key = config.get_api_key()
  local provider_name = config.options.provider or "anthropic"

  if not api_key then
    vim.schedule(function()
      if callbacks.on_error then
        callbacks.on_error("[skillvim] No API key configured.")
      end
    end)
    return nil
  end

  local provider = M.providers[provider_name]
  if not provider then
    vim.schedule(function()
      if callbacks.on_error then
        callbacks.on_error("[skillvim] Unknown provider: " .. provider_name)
      end
    end)
    return nil
  end

  local headers = provider.build_headers(api_key)
  local body_table = provider.build_body(request, config)
  local body = vim.json.encode(body_table)

  local accumulated = ""
  local sse_buffer = ""
  local response_meta = {
    model = nil,
    input_tokens = 0,
    output_tokens = 0,
    stop_reason = nil,
  }
  local complete_fired = false

  -- Build curl args
  local curl_args = { "curl", "-s", "-N", "-X", "POST", provider.url }
  for _, h in ipairs(headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, h)
  end
  table.insert(curl_args, "-d")
  table.insert(curl_args, body)

  local handle = vim.system(curl_args, {
    stdout = function(err, data)
      if err then
        vim.schedule(function()
          if callbacks.on_error then
            callbacks.on_error(err)
          end
        end)
        return
      end
      if not data or #data == 0 then
        return
      end

      sse_buffer = sse_buffer .. data
      local events, remainder = M._parse_sse_buffer(sse_buffer)
      sse_buffer = remainder

      for _, event in ipairs(events) do
        if provider_name == "anthropic" then
          local delta_text = M._handle_anthropic_event(event, response_meta, callbacks)
          if delta_text then
            accumulated = accumulated .. delta_text
          end
          if event.event_type == "message_stop" and not complete_fired then
            complete_fired = true
            local acc = accumulated
            vim.schedule(function()
              if callbacks.on_complete then
                callbacks.on_complete({
                  content = acc,
                  model = response_meta.model,
                  stop_reason = response_meta.stop_reason,
                  usage = {
                    input_tokens = response_meta.input_tokens,
                    output_tokens = response_meta.output_tokens,
                  },
                })
              end
            end)
          end
        else
          -- OpenAI-compatible (Groq)
          local delta_text = M._handle_openai_event(event, response_meta, callbacks)
          if delta_text then
            accumulated = accumulated .. delta_text
          end
          if event.done and not complete_fired then
            complete_fired = true
            local acc = accumulated
            vim.schedule(function()
              if callbacks.on_complete then
                callbacks.on_complete({
                  content = acc,
                  model = response_meta.model,
                  stop_reason = response_meta.stop_reason,
                  usage = {
                    input_tokens = response_meta.input_tokens,
                    output_tokens = response_meta.output_tokens,
                  },
                })
              end
            end)
          end
        end
      end
    end,
  }, function(result)
    -- On exit: fire on_complete if not yet fired (e.g. Groq sometimes ends without [DONE])
    if not complete_fired and #accumulated > 0 then
      complete_fired = true
      local acc = accumulated
      vim.schedule(function()
        if callbacks.on_complete then
          callbacks.on_complete({
            content = acc,
            model = response_meta.model,
            stop_reason = response_meta.stop_reason or "end_turn",
            usage = {
              input_tokens = response_meta.input_tokens,
              output_tokens = response_meta.output_tokens,
            },
          })
        end
      end)
    end

    if result.code ~= 0 then
      local err_msg = result.stderr or ""
      if #err_msg == 0 then
        err_msg = "curl exited with code " .. result.code
      end
      if result.stdout and #result.stdout > 0 then
        local ok, json = pcall(vim.json.decode, result.stdout)
        if ok and json and json.error then
          err_msg = json.error.message or json.error.type or err_msg
        end
      end
      vim.schedule(function()
        if callbacks.on_error then
          callbacks.on_error(err_msg)
        end
      end)
    end
  end)

  return handle
end

--- Send a non-streaming request
--- @param request table
--- @param callback fun(response: table|nil, err: string|nil)
function M.send(request, callback)
  local config = require("skillvim.config")
  local api_key = config.get_api_key()
  local provider_name = config.options.provider or "anthropic"

  if not api_key then
    callback(nil, "[skillvim] No API key configured.")
    return
  end

  local provider = M.providers[provider_name]
  if not provider then
    callback(nil, "[skillvim] Unknown provider: " .. provider_name)
    return
  end

  local headers = provider.build_headers(api_key)
  local body_table = provider.build_body(request, config)
  body_table.stream = false
  local body = vim.json.encode(body_table)

  local curl_args = { "curl", "-s", "-X", "POST", provider.url }
  for _, h in ipairs(headers) do
    table.insert(curl_args, "-H")
    table.insert(curl_args, h)
  end
  table.insert(curl_args, "-d")
  table.insert(curl_args, body)

  vim.system(curl_args, {}, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, result.stderr or "Request failed")
        return
      end

      local ok, json = pcall(vim.json.decode, result.stdout)
      if not ok then
        callback(nil, "Failed to parse response")
        return
      end

      if json.error then
        callback(nil, json.error.message or json.error.type)
        return
      end

      local content = ""
      if provider_name == "anthropic" then
        if json.content and #json.content > 0 then
          for _, block in ipairs(json.content) do
            if block.type == "text" then
              content = content .. block.text
            end
          end
        end
      else
        -- OpenAI format
        if json.choices and #json.choices > 0 then
          content = json.choices[1].message and json.choices[1].message.content or ""
        end
      end

      callback({
        content = content,
        model = json.model,
        stop_reason = json.stop_reason or (json.choices and json.choices[1] and json.choices[1].finish_reason),
        usage = json.usage,
      })
    end)
  end)
end

--- Parse an SSE buffer into complete events + remainder
--- @param buffer string
--- @return table[] events, string remainder
function M._parse_sse_buffer(buffer)
  local events = {}
  local remainder = buffer

  while true do
    local event_end = remainder:find("\n\n")
    if not event_end then
      break
    end

    local event_block = remainder:sub(1, event_end - 1)
    remainder = remainder:sub(event_end + 2)

    local event = M._parse_sse_event(event_block)
    if event then
      table.insert(events, event)
    end
  end

  return events, remainder
end

--- Parse a single SSE event block
--- @param block string
--- @return table|nil
function M._parse_sse_event(block)
  local event_type = nil
  local data_lines = {}

  for line in block:gmatch("[^\n]+") do
    local etype = line:match("^event:%s*(.+)")
    if etype then
      event_type = vim.trim(etype)
    end

    local dline = line:match("^data:%s*(.*)$")
    if dline then
      table.insert(data_lines, dline)
    end
  end

  if #data_lines == 0 then
    return nil
  end

  local data_str = table.concat(data_lines, "")

  -- OpenAI [DONE] marker
  if vim.trim(data_str) == "[DONE]" then
    return { event_type = "[DONE]", data = {}, done = true }
  end

  local ok, data = pcall(vim.json.decode, data_str)
  if not ok then
    return nil
  end

  return {
    event_type = event_type or data.type or "unknown",
    data = data,
    done = false,
  }
end

--- Handle Anthropic SSE event
--- @param event table
--- @param meta table
--- @param callbacks table
--- @return string|nil delta_text
function M._handle_anthropic_event(event, meta, callbacks)
  local etype = event.event_type
  local data = event.data

  if etype == "message_start" then
    if data.message then
      meta.model = data.message.model
      if data.message.usage then
        meta.input_tokens = data.message.usage.input_tokens or 0
      end
    end
    if callbacks.on_start then
      vim.schedule(function()
        callbacks.on_start()
      end)
    end
    return nil
  elseif etype == "content_block_delta" then
    if data.delta and data.delta.type == "text_delta" then
      local text = data.delta.text or ""
      if callbacks.on_delta and #text > 0 then
        vim.schedule(function()
          callbacks.on_delta(text)
        end)
      end
      return text
    end
    return nil
  elseif etype == "message_delta" then
    if data.delta then
      meta.stop_reason = data.delta.stop_reason
    end
    if data.usage then
      meta.output_tokens = data.usage.output_tokens or 0
    end
    return nil
  elseif etype == "error" then
    local err_msg = "API error"
    if data.error then
      err_msg = data.error.message or data.error.type or err_msg
    end
    if callbacks.on_error then
      vim.schedule(function()
        callbacks.on_error(err_msg)
      end)
    end
    return nil
  end

  return nil
end

--- Handle OpenAI-compatible SSE event (Groq, OpenAI, etc.)
--- @param event table
--- @param meta table
--- @param callbacks table
--- @return string|nil delta_text
function M._handle_openai_event(event, meta, callbacks)
  if event.done then
    return nil
  end

  local data = event.data
  if not data then
    return nil
  end

  -- Extract model
  if data.model and not meta.model then
    meta.model = data.model
  end

  -- Extract usage (Groq includes it in the final chunk)
  if data.usage then
    meta.input_tokens = data.usage.prompt_tokens or data.usage.input_tokens or 0
    meta.output_tokens = data.usage.completion_tokens or data.usage.output_tokens or 0
  end
  -- Groq also uses x_groq.usage
  if data.x_groq and data.x_groq.usage then
    meta.input_tokens = data.x_groq.usage.prompt_tokens or 0
    meta.output_tokens = data.x_groq.usage.completion_tokens or 0
  end

  -- Extract delta text
  if data.choices and #data.choices > 0 then
    local choice = data.choices[1]

    if choice.finish_reason then
      meta.stop_reason = choice.finish_reason
    end

    if choice.delta and choice.delta.content then
      local text = choice.delta.content
      if #text > 0 then
        if callbacks.on_delta then
          vim.schedule(function()
            callbacks.on_delta(text)
          end)
        end
        return text
      end
    end
  end

  -- First event = on_start
  if not meta._started then
    meta._started = true
    if callbacks.on_start then
      vim.schedule(function()
        callbacks.on_start()
      end)
    end
  end

  return nil
end

--- Cancel an in-flight request
--- @param handle vim.SystemObj|nil
function M.cancel(handle)
  if handle then
    pcall(function()
      handle:kill(9)
    end)
  end
end

return M
