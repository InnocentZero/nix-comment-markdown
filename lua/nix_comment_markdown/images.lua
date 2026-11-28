local api = vim.api
local rail = require("nix_comment_markdown.rail")
local NAMESPACE = "nix-comment-markdown"

local function local_path(dir, path)
  path = vim.uri_decode(path:match("^<(.*)>$") or path)
  if path == "" or path:find("[%z\r\n]") or path:match("^[%a][%w+.-]*:") or path:sub(1, 2) == "//" then
    return
  end
  path = path:sub(1, 1) == "/" and path or dir and vim.fs.joinpath(dir, path)
  path = path and vim.fs.normalize(path, { expand_env = false })
  local stat = path and vim.uv.fs_stat(path)
  return stat and stat.type == "file" and path or nil
end

local function add_rail(img, line)
  local ns, id = api.nvim_get_namespaces()["image.nvim"], img.extmark and img.extmark.id
  if not (ns and id and api.nvim_buf_is_loaded(img.buffer)) then
    return
  end
  local row, col, details = unpack(api.nvim_buf_get_extmark_by_id(img.buffer, ns, id, { details = true }))
  local lines, indent = details and details.virt_lines, rail.indent(line, true)
  if lines and not vim.deep_equal(lines[1], indent) then
    for i = 1, #lines do
      lines[i] = indent
    end
    api.nvim_buf_set_extmark(img.buffer, ns, row, col, { id = id, virt_lines = lines })
  end
end

local function new(show_rail)
  local ok, image = pcall(require, "image")
  if not ok then
    vim.notify("nix-comment-markdown: `images = true` needs image.nvim", vim.log.levels.WARN)
    return nil
  end
  local function clear(buf, keep)
    for _, img in ipairs(image.get_images({ buffer = buf, namespace = NAMESPACE })) do
      if keep and keep[img.id] then
        keep[img.id] = nil
      else
        img:clear()
      end
    end
  end
  local function sync(buf, links, raw_row)
    if not image.is_enabled() then
      return
    end
    local file, wanted = api.nvim_buf_get_name(buf), {}
    local dir = file ~= "" and vim.fs.dirname(file) or nil
    for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
      for row, link in
        pairs(api.nvim_win_get_buf(win) == buf and api.nvim_win_get_config(win).relative == "" and links or {})
      do
        local path, x = row ~= raw_row and local_path(dir, link.path), rail.width(link.line, show_rail)
        if path then
          local id = ("%s:%d:%d:%d:%d:%s"):format(NAMESPACE, buf, win, row, x, path)
          wanted[id] = { path, link.line, { window = win, x = x, y = row, with_virtual_padding = true } }
        end
      end
    end
    clear(buf, wanted)
    for id, job in pairs(wanted) do
      local opts = vim.tbl_extend("force", job[3], { id = id, buffer = buf, namespace = NAMESPACE })
      local loaded, img = pcall(image.from_file, job[1], opts)
      if loaded and img and show_rail then
        local render = img.render
        img.render = function(self, ...)
          local rendered = render(self, ...)
          add_rail(self, job[2])
          return rendered
        end
      end
      if loaded and img then
        img:render()
      end
    end
  end
  return { sync = sync, clear = clear }
end

return { new = new }
