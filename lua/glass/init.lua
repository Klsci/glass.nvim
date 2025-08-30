-- glass.nvim - Universal transparency plugin with glass pane effects
-- Author: Klsci
-- License: MIT

local M = {}

-- Default configuration
local default_config = {
  glass = {
    enable = true,
    -- how strongly the overlay color is mixed with the scheme 'Normal' background:
    -- 0 = keep scheme bg, 1 = full tint color
    tint_strength = 0.55,
    -- panel opacities used for blending window content with the terminal beneath:
    panel_opacity = {
      editor = 0.0, -- editor tint strength (0 -> mostly scheme bg)
      sidebar = 0.15,
      statusline = 0.1,
      floats = 0.18, -- how opaque float backgrounds are (0..1)
      popups = 0.22,
    }
  },
  overlay = {
    enable = true,
    -- winblend value applied to each normal window (0..100) - higher = more transparent
    blend = 30,
    -- fallback tint if colorscheme doesn't provide normal bg
    tint = "#0b0b0b",
    zindex = 50, -- zindex for floats we create (we don't create a fullscreen float by default)
    cover_statusline = true,
    cover_tabline = true,
  },
  -- groups that we set to NONE by default so the terminal can show through
  make_transparent_groups = {
    'Normal', 'NormalNC', 'SignColumn', 'LineNr', 'EndOfBuffer',
    'FoldColumn', 'CursorLine', 'CursorColumn', 'ColorColumn',
  },
  -- groups we will explicitly adjust for floats/popups
  popup_groups = {
    'NormalFloat', 'Pmenu', 'PmenuSel', 'CmpNormal', 'TelescopeNormal', 'WhichKeyFloat'
  },
  exclude_schemes = {},
  enable = {
    cursorline = true,
    statusline = true,
  }
}

M.config = vim.deepcopy(default_config)

-- Utility: parse different forms of hl.bg into "#rrggbb" string
local function hl_bg_to_hex(bg)
  if not bg then return nil end
  local t = type(bg)
  if t == "string" then
    if bg:sub(1, 1) == "#" then
      -- already hex
      if #bg == 7 then return bg:lower() end
      if #bg == 9 then return bg:sub(1, 7):lower() end
      return bg:lower()
    end
    -- unknown string form: ignore
    return nil
  elseif t == "number" then
    local n = bg
    local r = math.floor(n / 65536) % 256
    local g = math.floor(n / 256) % 256
    local b = n % 256
    return string.format("#%02x%02x%02x", r, g, b)
  end
  return nil
end

-- Utility: parse "#rrggbb" to r,g,b numbers
local function hex_to_rgb(hex)
  if not hex then return nil end
  hex = hex:gsub("#", "")
  if #hex ~= 6 then return nil end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  return r, g, b
end

-- Utility: linear blend between two hex colors
local function blend_hex(a_hex, b_hex, alpha)
  -- return color = (1-alpha)*a + alpha*b
  if not a_hex and not b_hex then return nil end
  if not a_hex then a_hex = "#000000" end
  if not b_hex then b_hex = "#000000" end
  local ar, ag, ab = hex_to_rgb(a_hex)
  local br, bg, bb = hex_to_rgb(b_hex)
  if not (ar and br) then return nil end
  local r = math.floor((1 - alpha) * ar + alpha * br + 0.5)
  local g = math.floor((1 - alpha) * ag + alpha * bg + 0.5)
  local b = math.floor((1 - alpha) * ab + alpha * bb + 0.5)
  return string.format("#%02x%02x%02x", r, g, b)
end

-- Create highlight groups used for overlay/floats
local function create_overlay_highlights()
  -- Get Normal bg from current colorscheme (if any)
  local ok, normal_hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal" })
  local normal_bg = nil
  if ok and normal_hl then
    normal_bg = hl_bg_to_hex(normal_hl.bg)
  end
  local tint = M.config.overlay.tint or "#0b0b0b"
  local tint_strength = M.config.glass.tint_strength or 0.55

  -- overlay base color: mix scheme Normal bg with tint
  local overlay_color = nil
  if normal_bg then
    overlay_color = blend_hex(normal_bg, tint, tint_strength)
  else
    overlay_color = tint
  end

  -- For floats we want a slightly different overlay (usually more visible)
  local float_base = blend_hex(normal_bg or tint, tint, 0.75)

  -- Create highlight groups
  vim.api.nvim_set_hl(0, "GlassOverlayNormal", { bg = overlay_color, fg = "NONE" })
  vim.api.nvim_set_hl(0, "GlassOverlaySidebar", { bg = blend_hex(overlay_color, "#000000", 0.12), fg = "NONE" })
  vim.api.nvim_set_hl(0, "GlassOverlayFloat", { bg = float_base, fg = "NONE" })
  vim.api.nvim_set_hl(0, "GlassOverlayPopup", { bg = blend_hex(float_base, "#000000", 0.08), fg = "NONE" })
  vim.api.nvim_set_hl(0, "GlassOverlayBorder", { bg = "NONE", fg = "#4a4a4a" })

  -- Ensure Visual/Selection remains visible (don't override)
  -- We only tweak backgrounds for Non-visual groups; Visual keeps its colors
end

-- Make core groups transparent (so terminal background shows through)
local function make_core_groups_transparent()
  for _, g in ipairs(M.config.make_transparent_groups) do
    -- set to NONE so terminal bg shows through if no winblend
    pcall(vim.api.nvim_set_hl, 0, g, { bg = "NONE" })
  end
end

-- Apply per-window tint + winblend to normal windows
local function apply_win_tint_to_window(win, opts)
  opts = opts or {}
  local is_float = false
  local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
  if ok and cfg and cfg.relative and cfg.relative ~= "" then
    is_float = true
  end

  if is_float then
    -- For floats: use float-highlight and a float-specific winblend (derived from config)
    local float_opacity = M.config.glass.panel_opacity.floats or 0.18
    local wb = math.floor((1 - float_opacity) * 100) -- if floats specify how opaque they are, invert to winblend
    if wb < 0 then wb = 0 end
    if wb > 100 then wb = 100 end
    -- set winhighlight to use float groups and border
    pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:GlassOverlayFloat,FloatBorder:GlassOverlayBorder",
      { scope = "win", win = win })
    pcall(vim.api.nvim_set_option_value, "winblend", wb, { scope = "win", win = win })
  else
    -- Normal editor windows: map Normal -> GlassOverlayNormal and apply configured blend
    pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:GlassOverlayNormal,NormalNC:GlassOverlayNormal",
      { scope = "win", win = win })
    local wb = M.config.overlay.blend or 30
    pcall(vim.api.nvim_set_option_value, "winblend", wb, { scope = "win", win = win })
  end
end

-- Re-apply tint to all windows (used at startup and on colorscheme)
local function apply_tint_to_all_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    -- skip our own ephemeral windows? none created by this plugin here, so just apply to all
    local success, _ = pcall(vim.api.nvim_win_get_config, win)
    if success then
      apply_win_tint_to_window(win)
    end
  end
end

-- When a new window appears, make sure it gets the tint/blend applied
local function on_win_created_autocmd()
  local aug = vim.api.nvim_create_augroup("GlassNvimWindow", { clear = true })
  vim.api.nvim_create_autocmd({ "WinNew" }, {
    group = aug,
    callback = function()
      -- small defer to allow window config to settle
      vim.defer_fn(function()
        local win = vim.api.nvim_get_current_win()
        apply_win_tint_to_window(win)
      end, 10)
    end,
  })
end

-- When colorscheme changes: recreate overlay highlights and reapply to windows
local function on_colorscheme_autocmd()
  local aug = vim.api.nvim_create_augroup("GlassNvimColors", { clear = true })
  vim.api.nvim_create_autocmd({ "ColorScheme" }, {
    group = aug,
    callback = function()
      -- rebuild hl groups and reapply tints
      create_overlay_highlights()
      make_core_groups_transparent()
      -- reapply to windows (defer to avoid race)
      vim.defer_fn(apply_tint_to_all_windows, 10)
    end,
  })
end

-- Keep tints correct after resize
local function on_resize_autocmd()
  local aug = vim.api.nvim_create_augroup("GlassNvimResize", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized" }, {
    group = aug,
    callback = function()
      -- nothing special to resize, but reapply in case float sizes changed
      vim.defer_fn(apply_tint_to_all_windows, 10)
    end,
  })
end

-- Public setup function
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", M.config, user_config or {})

  -- force termguicolors
  vim.opt.termguicolors = true

  -- ensure core groups transparent so terminal background is visible
  make_core_groups_transparent()

  -- create overlay highlight groups (based on current colorscheme)
  create_overlay_highlights()

  -- apply win tints to current windows
  apply_tint_to_all_windows()

  -- setup autocmds
  on_colorscheme_autocmd()
  on_win_created_autocmd()
  on_resize_autocmd()

  -- commands to toggle/plugin control
  vim.api.nvim_create_user_command("GlassApply", function()
    create_overlay_highlights()
    make_core_groups_transparent()
    apply_tint_to_all_windows()
    print("Glass: applied")
  end, {})

  vim.api.nvim_create_user_command("GlassDisable", function()
    -- remove winhighlight and winblend from all windows and restore group bg=NONE
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      pcall(vim.api.nvim_set_option_value, "winhighlight", "", { scope = "win", win = win })
      pcall(vim.api.nvim_set_option_value, "winblend", 0, { scope = "win", win = win })
    end
    for _, g in ipairs(M.config.make_transparent_groups) do
      pcall(vim.api.nvim_set_hl, 0, g, { bg = "NONE" })
    end
    print("Glass: disabled")
  end, {})

  vim.api.nvim_create_user_command("GlassToggle", function()
    M.config.glass.enable = not M.config.glass.enable
    if M.config.glass.enable then
      create_overlay_highlights()
      apply_tint_to_all_windows()
      print("Glass: enabled")
    else
      vim.cmd("GlassDisable")
    end
  end, {})

  -- ensure plugin re-applies after a manual colorscheme load via vim.cmd.colorscheme
  local original_colorscheme = vim.cmd.colorscheme
  vim.cmd.colorscheme = function(s)
    original_colorscheme(s)
    vim.defer_fn(function()
      create_overlay_highlights()
      make_core_groups_transparent()
      apply_tint_to_all_windows()
    end, 10)
  end
end

-- expose helpers
M._helpers = {
  hl_bg_to_hex = hl_bg_to_hex,
  blend_hex = blend_hex,
  create_overlay_highlights = create_overlay_highlights,
  apply_tint_to_all_windows = apply_tint_to_all_windows,
}

return M
