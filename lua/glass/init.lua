-- lua/glass/init.lua
-- glass.nvim - Universal transparency plugin with glass pane effects (reworked)
-- Author: Klsci
-- License: MIT

local M = {}

-- Default configuration
local default_config = {
  glass = {
    enable = true,
    -- global perceived opacity for highlight tinting (0..1)
    opacity = 0.30,
    frosted_borders = true,
    panel_opacity = {
      editor = 0.0,
      sidebar = 0.15,
      statusline = 0.10,
      floats = 0.20,
      popups = 0.25,
    }
  },

  -- overlay: fullscreen frosted float (only when nvim is open)
  overlay = {
    enable = true,
    blend = 30,       -- 0..100: winblend for overlay
    tint = "#0b0b0b", -- base tint (will be combined with colorscheme)
    zindex = 10,
    cover_statusline = true,
    cover_tabline = true,
    gradient_lines = 12, -- number of gradient bands to simulate blur
  },

  -- groups to tint for the "transparent base" (will be tinted according to panel_opacity.editor)
  groups = {
    "Normal", "NormalNC", "SignColumn", "LineNr", "EndOfBuffer",
    "StatusLine", "StatusLineNC", "VertSplit", "WinSeparator",
    "CursorLine", "CursorColumn"
  },

  extra_groups = {
    "NormalFloat", "FloatBorder", "Pmenu", "PmenuSel", "CmpNormal",
    "TelescopeNormal", "TelescopeBorder", "WhichKeyFloat", "LazyNormal",
  },

  exclude_groups = {},
  exclude_schemes = {},

  enable = {
    cursorline = true,
    statusline = true,
    tabline = true,
    winbar = true,
  },
}

M.config = default_config

-- internal overlay state
local overlay_state = { buf = nil, win = nil, shown = false }

-- helpers: robust color parsing
local function color_to_rgb_tuple(color)
  -- Accept either number (0xRRGGBB) or string "#rrggbb"
  if not color then return nil end
  if type(color) == "string" then
    local s = color:gsub("#", "")
    if #s == 6 then
      local r = tonumber(s:sub(1, 2), 16)
      local g = tonumber(s:sub(3, 4), 16)
      local b = tonumber(s:sub(5, 6), 16)
      return r, g, b
    end
    return nil
  end
  if type(color) == "number" then
    -- ensure we work with up to 24-bit number
    local n = color
    local r = math.floor(n / 0x10000) % 0x100
    local g = math.floor(n / 0x100) % 0x100
    local b = n % 0x100
    return r, g, b
  end
  return nil
end

local function rgb_to_hex(r, g, b)
  r = math.max(0, math.min(255, math.floor(r)))
  g = math.max(0, math.min(255, math.floor(g)))
  b = math.max(0, math.min(255, math.floor(b)))
  return string.format("#%02x%02x%02x", r, g, b)
end

-- blend two RGB tuples: return rgb blended of fg over bg with alpha (0..1)
local function blend_rgb(fg_r, fg_g, fg_b, bg_r, bg_g, bg_b, alpha)
  local inv = 1 - alpha
  return fg_r * alpha + bg_r * inv,
      fg_g * alpha + bg_g * inv,
      fg_b * alpha + bg_b * inv
end

-- compute tint color that matches colorscheme: take Normal.bg or fallback to overlay tint
local function pick_base_tint()
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, "Normal", true)
  if ok and hl and hl.background then
    -- hl.background may be number
    local r, g, b = color_to_rgb_tuple(hl.background)
    if r and g and b then
      -- mix with user tint to keep a slight glass darkness
      local tr, tg, tb = color_to_rgb_tuple(M.config.overlay.tint)
      tr = tr or 0; tg = tg or 0; tb = tb or 0
      -- blend the scheme bg slightly towards the overlay tint (alpha 0.25)
      local br, bg, bb = blend_rgb(tr, tg, tb, r, g, b, 0.25)
      return rgb_to_hex(br, bg, bb)
    end
  end
  return M.config.overlay.tint
end

-- create or return overlay buffer
local function ensure_overlay_buf()
  if overlay_state.buf and vim.api.nvim_buf_is_valid(overlay_state.buf) then
    return overlay_state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true) -- scratch, not listed
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  overlay_state.buf = buf
  return buf
end

-- create gradient band highlights on the fly
local function ensure_overlay_highlights(base_hex)
  -- create N gradient highlights (number depends on config.gradient_lines)
  local bands = M.config.overlay.gradient_lines or 8
  local base_r, base_g, base_b = color_to_rgb_tuple(base_hex)
  base_r = base_r or 0; base_g = base_g or 0; base_b = base_b or 0
  for i = 1, bands do
    -- compute alpha for band (centered darkening)
    local t = i / bands
    local alpha = 0.10 + (0.45 * (1 - math.abs(t - 0.5) * 2))               -- subtle bulge in center
    local r, g, b = blend_rgb(base_r, base_g, base_b, 255, 255, 255, alpha) -- blend toward white slightly
    local hex = rgb_to_hex(r, g, b)
    local name = ("GlassOverlayBand%d"):format(i)
    pcall(vim.api.nvim_set_hl, 0, name, { bg = hex, fg = "NONE" })
  end
  -- some utility highlights
  pcall(vim.api.nvim_set_hl, 0, "GlassOverlayNormal", { bg = base_hex, fg = "NONE" })
  pcall(vim.api.nvim_set_hl, 0, "GlassOverlayWinSep", { fg = "#2a2a2a", bg = "NONE" })
end

-- draw the overlay: fill buffer with blank lines and per-line band highlights to simulate blur
local function draw_overlay()
  if not M.config.overlay.enable then return end
  if not M.config.glass.enable then return end

  local buf = ensure_overlay_buf()
  -- sizing
  local cols = vim.o.columns or vim.api.nvim_get_option("columns")
  local rows = vim.o.lines or vim.api.nvim_get_option("lines")
  local top = 0
  local height = rows
  if not M.config.overlay.cover_tabline and (vim.o.showtabline or 0) > 0 then
    top = 1; height = math.max(1, height - 1)
  end
  if not M.config.overlay.cover_statusline and (vim.o.laststatus or 0) > 0 then
    height = math.max(1, height - 1)
  end

  -- fill content (spaces so background highlight applied)
  local line = string.rep(" ", cols)
  local content = {}
  for i = 1, height do content[i] = line end
  -- ensure buffer has those lines
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  local config = {
    relative = "editor",
    row = top,
    col = 0,
    width = cols,
    height = height,
    style = "minimal",
    focusable = false,
    zindex = M.config.overlay.zindex or 10,
    noautocmd = true,
  }

  if overlay_state.win and vim.api.nvim_win_is_valid(overlay_state.win) then
    pcall(vim.api.nvim_win_set_config, overlay_state.win, config)
  else
    overlay_state.win = vim.api.nvim_open_win(buf, false, config)
  end

  -- pick base tint from colorscheme
  local base = pick_base_tint()
  ensure_overlay_highlights(base)

  -- apply band highlights per-line to create blur illusion
  local bands = M.config.overlay.gradient_lines or 12
  if bands < 1 then bands = 1 end
  for i = 0, height - 1 do
    -- map line to band index (0..bands-1)
    local band_idx = math.floor((i / math.max(1, height - 1)) * (bands - 1)) + 1
    local hname = ("GlassOverlayBand%d"):format(band_idx)
    -- add highlight to line: ns id  -1 uses default ns (safe)
    pcall(vim.api.nvim_buf_add_highlight, buf, -1, hname, i, 0, -1)
  end

  -- set win options
  pcall(vim.api.nvim_win_set_option, overlay_state.win, "winblend", M.config.overlay.blend or 30)
  pcall(vim.api.nvim_win_set_option, overlay_state.win, "winhighlight",
    "Normal:GlassOverlayNormal,WinSeparator:GlassOverlayWinSep")
  overlay_state.shown = true
end

local function remove_overlay()
  if overlay_state.win and vim.api.nvim_win_is_valid(overlay_state.win) then
    pcall(vim.api.nvim_win_close, overlay_state.win, true)
  end
  overlay_state.win = nil
  overlay_state.shown = false
end

-- Auto-hide overlay in Visual mode so selection is visible
local function on_mode_changed(old, new)
  if not overlay_state then return end
  if new:match("v") or new:match("V") or new:match("<C-v>") then
    -- entered visual modes -> hide overlay
    if overlay_state.shown then
      remove_overlay()
      overlay_state._was_shown_for_visual = true
    end
  else
    -- left visual -> restore if it was previously shown
    if overlay_state._was_shown_for_visual then
      draw_overlay()
      overlay_state._was_shown_for_visual = false
    end
  end
end

-- Apply glass to highlight groups (makes base buffer "transparent-ish")
local function apply_group_tint(group, opacity)
  if vim.tbl_contains(M.config.exclude_groups or {}, group) then return end
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group })
  if not ok then return end
  local new = vim.deepcopy(hl)
  if opacity and opacity > 0 then
    -- use Normal.bg as base, then darken by opacity toward overlay tint
    local base_hex = pick_base_tint()
    local br, bg, bb = color_to_rgb_tuple(base_hex)
    local r, g, b = color_to_rgb_tuple(hl.bg or hl.background or base_hex)
    r = r or br; g = g or bg; b = b or bb
    local nr, ng, nb = blend_rgb(br or 0, bg or 0, bb or 0, r, g, b, opacity)
    new.bg = rgb_to_hex(nr, ng, nb)
    new.blend = math.floor((1 - opacity) * 100)
  else
    new.bg = "NONE"
    new.blend = 0
  end
  -- set safely
  pcall(vim.api.nvim_set_hl, 0, group, new)
end

-- Apply to floats/popups: iterate windows, set their winblend and winhighlight
local function adjust_floating_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
    if ok and cfg and cfg.relative and cfg.relative ~= "" then
      -- floating window
      pcall(vim.api.nvim_win_set_option, win, "winblend", math.floor(M.config.glass.panel_opacity.floats * 100))
      pcall(vim.api.nvim_win_set_option, win, "winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder")
    end
  end
end

-- Main apply function: tints base groups and sets floats
local function apply_transparency()
  if vim.tbl_contains(M.config.exclude_schemes or {}, vim.g.colors_name or "") then return end
  if not M.config.glass.enable then
    -- reset: set groups to NONE
    for _, g in ipairs(M.config.groups or {}) do
      pcall(vim.api.nvim_set_hl, 0, g, { bg = "NONE" })
    end
    return
  end

  local editor_op = M.config.glass.panel_opacity.editor or 0.0
  for _, g in ipairs(M.config.groups or {}) do
    apply_group_tint(g, editor_op)
  end

  -- extra groups (floats/popups)
  local floats_op = M.config.glass.panel_opacity.floats or 0.2
  for _, g in ipairs(M.config.extra_groups or {}) do
    apply_group_tint(g, floats_op)
  end

  if M.config.glass.frosted_borders then
    pcall(vim.api.nvim_set_hl, 0, "FloatBorder", { bg = "NONE", fg = "#4a4a4a" })
    pcall(vim.api.nvim_set_hl, 0, "WinSeparator", { bg = "NONE", fg = "#2a2a2a" })
  end

  -- set global blending defaults for popups (pumblend)
  pcall(vim.opt, "termguicolors", true)
  pcall(vim.opt, "pumblend", math.floor((M.config.glass.panel_opacity.popups or 0.25) * 100))
  pcall(vim.opt, "winblend", math.floor((M.config.glass.panel_opacity.floats or 0.2) * 100))

  -- adjust any existing floating windows immediately
  adjust_floating_windows()
end

-- public API: setup
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- ensure termguicolors
  vim.opt.termguicolors = true

  -- hook colorscheme changes
  local orig_cs = vim.cmd.colorscheme
  vim.cmd.colorscheme = function(s)
    orig_cs(s)
    vim.defer_fn(function()
      apply_transparency()
      if M.config.overlay.enable then draw_overlay() end
      adjust_floating_windows()
    end, 20)
  end

  -- autogroup
  local aug = vim.api.nvim_create_augroup("GlassNvim", { clear = true })

  -- redraw overlay on resize
  vim.api.nvim_create_autocmd("VimResized",
    { group = aug, callback = function() if M.config.overlay.enable then draw_overlay() end end })

  -- colorscheme change
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = aug,
    callback = function()
      apply_transparency()
      if M.config.overlay.enable then draw_overlay() end
    end
  })

  -- create overlay on startup (defer to UI readiness)
  vim.defer_fn(function()
    apply_transparency()
    if M.config.overlay.enable then draw_overlay() end
    adjust_floating_windows()
  end, 50)

  -- when new windows open (floating windows), adjust them
  vim.api.nvim_create_autocmd({ "WinNew", "BufWinEnter" }, {
    group = aug,
    callback = function()
      adjust_floating_windows()
    end,
  })

  -- hide overlay on visual mode so selection is visible; restore after
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = aug,
    pattern = "*",
    callback = function()
      local new = vim.fn.mode()
      on_mode_changed(nil, new)
    end,
  })

  -- commands
  vim.api.nvim_create_user_command("GlassOverlayToggle", {
    desc = "Toggle glass overlay",
    callback = function()
      M.config.overlay.enable = not M.config.overlay.enable
      if not M.config.overlay.enable then remove_overlay() else draw_overlay() end
    end,
  })
  vim.api.nvim_create_user_command("GlassApply", {
    desc = "Reapply glass settings",
    callback = function()
      apply_transparency()
      adjust_floating_windows()
      if M.config.overlay.enable then draw_overlay() end
    end,
  })

  -- mark enabled
  vim.g.glass_enabled = M.config.glass.enable
end

-- convenience API
function M.enable()
  M.config.glass.enable = true; apply_transparency(); if M.config.overlay.enable then draw_overlay() end
end

function M.disable()
  M.config.glass.enable = false; remove_overlay(); apply_transparency()
end

function M.toggle()
  M.config.glass.enable = not M.config.glass.enable;

  if M.config.glass.enable then M.enable() else M.disable() end
end

return M
