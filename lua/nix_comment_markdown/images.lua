local namespace = "nix-comment-markdown"
local api = vim.api
local rail = require("nix_comment_markdown.rail")
local empty = {}

local function local_path(dir, path)
  path = vim.uri_decode(path:match("^<(.*)>$") or path)
  if path == "" or path:find("[%z\r\n]") or path:match("^[%a][%w+.-]*:") or path:sub(1, 2) == "//" then
    return
  end
  if path:sub(1, 1) ~= "/" then
    if not dir then
      return
    end
    path = vim.fs.joinpath(dir, path)
  end
  path = vim.fs.normalize(path, { expand_env = false })
  local stat = vim.uv.fs_stat(path)
  return stat and stat.type == "file" and path or nil
end

local function decorate_padding(img, prefix)
  local ns = api.nvim_get_namespaces()["image.nvim"]
  local id = img.extmark and img.extmark.id
  if not (ns and id and api.nvim_buf_is_loaded(img.buffer)) then
    return
  end
  local row, col, details = unpack(api.nvim_buf_get_extmark_by_id(img.buffer, ns, id, { details = true }))
  local lines = details and details.virt_lines
  local chunks = lines and rail.prefix(prefix, true)
  if not lines or vim.deep_equal(lines[1], chunks) then
    return
  end
  for i = 1, #lines do
    lines[i] = chunks
  end
  api.nvim_buf_set_extmark(img.buffer, ns, row, col, { id = id, virt_lines = lines })
end

local function add_image(image, path, opts, prefix)
  local ok, img = pcall(image.from_file, path, opts)
  if not ok or not img then
    return
  end
  if prefix then
    local render = img.render
    function img:render(...)
      render(self, ...)
      decorate_padding(self, prefix)
    end
  end
  img:render()
end

return function(show_rail)
  local ok, image = pcall(require, "image")
  if not ok then
    return
  end

  return function(buf, links)
    if links and not image.is_enabled() then
      return
    end
    local current, missing = {}, {}
    local file = api.nvim_buf_get_name(buf)
    local dir = file ~= "" and vim.fs.dirname(file) or nil
    for _, img in ipairs(image.get_images({ buffer = buf, namespace = namespace })) do
      current[img.id] = img
    end
    local wins = vim.tbl_filter(function(win)
      return api.nvim_win_get_buf(win) == buf and api.nvim_win_get_config(win).relative == ""
    end, links and api.nvim_tabpage_list_wins(0) or empty)
    for row, link in pairs(#wins > 0 and links or empty) do
      local path = local_path(dir, link.path)
      local x = #link.prefix.raw
      for _, win in ipairs(path and wins or empty) do
        local id = ("%s:%d:%d:%d:%d:%s"):format(namespace, buf, win, row, x, path)
        if current[id] then
          current[id] = nil
        else
          local opts = { id = id, buffer = buf, namespace = namespace, window = win, x = x, y = row }
          opts.with_virtual_padding = true
          missing[#missing + 1] = { path, opts, show_rail and link.prefix }
        end
      end
    end
    for _, img in pairs(current) do
      img:clear()
    end
    for _, job in ipairs(missing) do
      add_image(image, unpack(job, 1, 3))
    end
  end
end
