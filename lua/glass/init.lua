-- glass.nvim - Universal transparency plugin with glass pane effects
-- Author: Klsci
-- License: MIT

local M = {}

-- Default configuration
local default_config = {
  glass = {
    enable = true,
    opacity = 0.3,
    blur_background = true,
    frosted_borders = true,
    panel_opacity = {
      editor = 0.0,
      sidebar = 0.15,
      statusline = 0.1,
      floats = 0.2,
      popups = 0.25,
    }
  },
  overlay = {
    enable = true,
    blend = 30,       -- 0..100 higher = more transparent
    tint = "#0b0b0b", -- slight dark tint for glass feel
    zindex = 10,      -- keep under plugin floats
    cover_statusline = true,
    cover_tabline = true,
  },
  groups = {
    'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
    'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
    'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
    'SignColumn', 'CursorColumn', 'CursorLine', 'TabLine', 'TabLineSel', 'TabLineFill',
    'StatusLine', 'StatusLineNC', 'VertSplit', 'WinSeparator', 'Visual', 'VisualNOS',
    'Folded', 'FoldColumn', 'DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText',
    'SignColumn', 'Conceal', 'EndOfBuffer', 'SearchResult'
  },
  extra_groups = {
    'NormalFloat', 'FloatBorder', 'Pmenu', 'PmenuSel', 'PmenuSbar', 'PmenuThumb',
    'TelescopeNormal', 'TelescopeBorder', 'TelescopePromptNormal', 'TelescopePromptBorder',
    'TelescopePromptTitle', 'TelescopePreviewTitle', 'TelescopeResultsTitle',
    'NvimTreeNormal', 'NvimTreeNormalNC', 'NvimTreeRootFolder', 'NeoTreeNormal', 'NeoTreeNormalNC',
    'WhichKey', 'WhichKeyFloat', 'WhichKeyGroup', 'WhichKeyDesc',
    'GitSignsAdd', 'GitSignsChange', 'GitSignsDelete',
    'LspDiagnosticsDefaultError', 'LspDiagnosticsDefaultWarning', 'LspDiagnosticsDefaultInformation',
    'LspDiagnosticsDefaultHint',
    'DiagnosticError', 'DiagnosticWarn', 'DiagnosticInfo', 'DiagnosticHint',
    'CmpNormal', 'CmpBorder', 'CmpDocumentation', 'CmpDocumentationBorder',
    'NotifyBackground', 'NotifyERRORBody', 'NotifyWARNBody', 'NotifyINFOBody', 'NotifyDEBUGBody', 'NotifyTRACEBody',
    'MasonNormal', 'MasonHeader', 'MasonHighlight',
    'LazyNormal', 'LazyButton', 'LazyButtonActive',
  },
  exclude_groups = {},
  exclude_schemes = {},
  enable = {
    cursorline = true,
    statusline = true,
    tabline = true,
    winbar = true,
  }
}

M.config = default_config
local original_colorscheme = vim.cmd.colorscheme

----------------------------------------------------
-- Glass Overlay State
----------------------------------------------------
local overlay_state = { buf = nil, win = nil }

local function ensure_overlay_buf()
  if overlay_state.buf and vim.api.nvim_buf_is_valid(overlay_state.buf) then return overlay_state.buf end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  overlay_state.buf = buf
  return buf
end

local function ensure_overlay_hl()
  vim.api.nvim_set_hl(0, "GlassOverlayNormal", { bg = M.config.overlay.tint, fg = "NONE" })
end

local function draw_overlay()
  if not M.config.overlay.enable then return end
  ensure_overlay_hl()
  local buf = ensure_overlay_buf()

  local cols = vim.o.columns
  local lines = vim.o.lines
  local top = 0
  local height = lines
  if not M.config.overlay.cover_tabline and vim.o.showtabline > 0 then
    top = 1
    height = height - 1
  end
  if not M.config.overlay.cover_statusline and vim.o.laststatus > 0 then
    height = height - 1
  end

  local line = string.rep(" ", cols)
  local content = {}
  for _ = 1, height do
    table.insert(content, line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  if overlay_state.win and vim.api.nvim_win_is_valid(overlay_state.win) then
    vim.api.nvim_win_set_config(overlay_state.win, {
      relative = "editor",
      row = top,
      col = 0,
      width = cols,
      height = height,
      zindex = M.config.overlay.zindex,
      focusable = false,
    })
  else
    overlay_state.win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = top,
      col = 0,
      width = cols,
      height = height,
      zindex = M.config.overlay.zindex,
      focusable = false,
      style = "minimal",
      noautocmd = true,
    })
  end

  vim.api.nvim_set_option_value("winhighlight", "Normal:GlassOverlayNormal", { win = overlay_state.win })
  vim.api.nvim_set_option_value("winblend", M.config.overlay.blend, { win = overlay_state.win })
end

local function remove_overlay()
  if overlay_state.win and vim.api.nvim_win_is_valid(overlay_state.win) then
    pcall(vim.api.nvim_win_close, overlay_state.win, true)
  end
  overlay_state.win = nil
end

----------------------------------------------------
-- Highlight Glass Logic
----------------------------------------------------
local function hex_to_rgb(hex)
  if not hex then return nil end
  hex = string.format("%06x", hex)
  return tonumber(hex:sub(1, 2), 16),
      tonumber(hex:sub(3, 4), 16),
      tonumber(hex:sub(5, 6), 16)
end

local function apply_opacity(color, opacity)
  if not color then return nil end
  local r, g, b = hex_to_rgb(color)
  return string.format("#%02x%02x%02x", r * opacity, g * opacity, b * opacity)
end

local function create_glass(group, opacity)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
  if not ok or not hl then return end
  local new_hl = vim.tbl_extend("force", hl, {})
  if opacity > 0 then
    new_hl.bg = apply_opacity(hl.bg, opacity) or nil
    new_hl.blend = math.floor((1 - opacity) * 100)
  else
    new_hl.bg = nil
    new_hl.blend = 0
  end
  vim.api.nvim_set_hl(0, group, new_hl)
end

local function apply_transparency()
  if vim.tbl_contains(M.config.exclude_schemes, vim.g.colors_name or "") then return end
  if M.config.glass.enable then
    for _, group in ipairs(M.config.groups) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.editor)
      end
    end
    for _, group in ipairs(M.config.extra_groups) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.floats)
      end
    end
    if M.config.glass.frosted_borders then
      vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE", fg = "#4a4a4a" })
      vim.api.nvim_set_hl(0, "WinSeparator", { bg = "NONE", fg = "#2a2a2a" })
    end
  end
  vim.opt.winblend = math.floor(M.config.glass.panel_opacity.floats * 100)
  vim.opt.pumblend = math.floor(M.config.glass.panel_opacity.popups * 100)
  vim.opt.termguicolors = true
end

----------------------------------------------------
-- Setup
----------------------------------------------------
function M.setup(user)
  M.config = vim.tbl_deep_extend("force", default_config, user or {})
  vim.cmd.colorscheme = function(scheme)
    original_colorscheme(scheme)
    vim.defer_fn(function()
      apply_transparency()
      draw_overlay()
    end, 10)
  end
  local aug = vim.api.nvim_create_augroup("GlassNvim", { clear = true })
  vim.api.nvim_create_autocmd({ "ColorScheme" }, {
    group = aug,
    callback = function()
      apply_transparency()
      draw_overlay()
    end
  })
  vim.api.nvim_create_autocmd({ "VimResized" }, { group = aug, callback = draw_overlay })

  apply_transparency()
  draw_overlay()

  vim.api.nvim_create_user_command("GlassOverlayToggle", function()
    if M.config.overlay.enable then
      M.config.overlay.enable = false
      remove_overlay()
    else
      M.config.overlay.enable = true
      draw_overlay()
    end
  end, { desc = "Toggle glass overlay" })
end

return M
