local M = {}

local cmp = require("cmp")
local sources = require("cmp2lsp.sources")

M.create_abstracted_context = function(request)
  local line_num = request.position.line
  local col_num = request.position.character
  local buf = vim.uri_to_bufnr(request.textDocument.uri)
  local full_line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]
  local before_char = (request.context and request.context.triggerCharacter) or full_line:sub(col_num, col_num + 1)
  return {
    context = {
      cursor = {
        row = request.position.line,
        col = col_num + 1,
      },
      line = full_line,
      line_before_cursor = full_line:sub(1, col_num + 1),
      bufnr = buf,
      before_char = before_char,
      -- throwaway values to appease some plugins that expect them (neorg)
      prev_context = {
        cursor = {
          row = request.position.line,
          col = col_num + 1,
        },
        line = full_line,
        line_before_cursor = full_line:sub(1, col_num + 1),
        bufnr = buf,
        before_char = before_char,
      },
    },
    completion_context = {
      triggerKind = 0,
    },
  }
end

M.setup = function(_opts)
  local build_trigger_chars = function()
    local chars = {}
    local function set_insert(t, i)
      if not vim.tbl_contains(t, i) then
        table.insert(t, i)
      end
    end
    for _, source in ipairs(sources) do
      for _, c in ipairs(source.get_trigger_characters()) do
        set_insert(chars, c)
      end
    end
    return chars
  end

  local handlers = {
    ["initialize"] = function(_params, callback, _notify_reply_callback)
      local initializeResult = {
        capabilities = {
          renameProvider = {
            prepareProvider = true,
          },
          completionProvider = {
            triggerCharacters = build_trigger_chars(),
            resolveProvider = false,
            completionItem = {
              labelDetailsSupport = true,
            },
          },
        },
        serverInfo = {
          name = "cmp2lsp",
          version = "0.0.1",
        },
      }

      callback(nil, initializeResult)
    end,

    ["textDocument/completion"] = function(request, callback, _)
      local abstracted_context = M.create_abstracted_context(request)
      for _, source in ipairs(sources) do
        if vim.tbl_contains(source.get_trigger_characters(), abstracted_context.context.before_char) then
          source.complete(abstracted_context, function(items)
            callback(nil, items)
          end)
        end
      end
    end,
  }

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "*",
    callback = function()
      M.start_lsp(handlers)
    end,
  })
end

M.start_lsp = function(handlers)
  vim.lsp.start({
    name = "cmp2lsp",
    cmd = function(_dispatchers)
      local members = {
        trace = "messages",
        request = function(method, params, callback, notify_reply_callback)
          if handlers[method] then
            handlers[method](params, callback, notify_reply_callback)
          else
            -- fail silently
          end
        end,
        notify = function(_method, _params) end,
        is_closing = function() end,
        terminate = function() end,
      }
      return members
    end,
    filetypes = { "norg" },
    root_dir = vim.fn.getcwd(),
  })
end

return M
