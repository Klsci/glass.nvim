-- glass.nvim - Universal transparency plugin with glass pane effects
-- Author: Klsci
-- License: MIT

local M = {}

-- Default configuration
local default_config = {
  -- Glass pane effect settings
  glass = {
    enable = true,
    opacity = 0.3,
    blur_background = true,
    frosted_borders = true,
    panel_opacity = {
      editor = 0.0,     -- Main editor completely transparent
      sidebar = 0.15,   -- Sidebar slightly less
      statusline = 0.1, -- Status line not too distracting but readable
      floats = 0.2,     -- Floating windows distinct for focus
      popups = 0.25,    -- Popups most visible
    }
  },
  -- Groups that should always be transparent
  groups = {
    'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
    'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
    'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
    'SignColumn', 'CursorColumn', 'CursorLine', 'TabLine', 'TabLineSel', 'TabLineFill',
    'StatusLine', 'StatusLineNC', 'VertSplit', 'WinSeparator', 'Visual', 'VisualNOS',
    'Folded', 'FoldColumn', 'DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText',
    'SignColumn', 'Conceal', 'EndOfBuffer', 'SearchResult'
  },
  -- Extra groups (plugin-specific)
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
  -- Exclude certain groups from transparency
  exclude_groups = {},
  -- Exclude specific colorschemes from auto-transparency
  exclude_schemes = {},
  -- Enable/disable features
  enable = {
    cursorline = true,
    statusline = true,
    tabline = true,
    winbar = true,
  }
}

-- Module state
M.config = default_config
local original_colorscheme = vim.cmd.colorscheme

local function hex_to_rgb(color)
  local r = bit.band(bit.rshift(color, 16), 0xFF)
  local g = bit.band(bit.rshift(color, 8), 0xFF)
  local b = bit.band(color, 0xFF)
  return r, g, b
end

-- blend color with black based on opacity
local function apply_opacity(color, opacity)
  if not color then return nil end
  local r, g, b = hex_to_rgb(color)
  local new_r = math.floor(r * opacity)
  local new_g = math.floor(g * opacity)
  local new_b = math.floor(b * opacity)
  local bit = require("bit")
  return bit.bor(bit.lshift(new_r, 16), bit.lshift(new_g, 8), new_b)
end


-- Function to create glass effect for a highlight group
-- local function create_glass(group_name, opacity_level, border_color)
--   local success, hl_info = pcall(vim.api.nvim_get_hl, 0, { name = group_name })
--   if success and hl_info then
--     -- Create a new highlight table with the correct structure
--     local new_hl = {
--       fg = hl_info.fg,
--       bg = hl_info.bg,
--       sp = hl_info.sp,
--       bold = hl_info.bold,
--       italic = hl_info.italic,
--       underline = hl_info.underline,
--       undercurl = hl_info.undercurl,
--       underdouble = hl_info.underdouble,
--       underdotted = hl_info.underdotted,
--       underdashed = hl_info.underdashed,
--       strikethrough = hl_info.strikethrough,
--       reverse = hl_info.reverse,
--       standout = hl_info.standout,
--     }
--
--     -- Override background color if opacity is specified
--     if opacity_level > 0 then
--       local overlay_colors = {
--         [0.05] = 0x050505, -- Minimal tint
--         [0.08] = 0x080808, -- Status line
--         [0.1] = 0x0a0a0a,  -- Very subtle
--         [0.12] = 0x0c0c0c, -- Sidebar subtle
--         [0.15] = 0x0f0f0f, -- Sidebar normal
--         [0.18] = 0x121212, -- Float subtle
--         [0.2] = 0x141414,  -- Float normal
--         [0.22] = 0x161616, -- Popup subtle
--         [0.25] = 0x1a1a1a, -- Popup normal
--         [0.3] = 0x1e1e1e,  -- Strong glass
--       }
--       new_hl.bg = overlay_colors[opacity_level] or 0x0f0f0f
--     end
--
-- Add border if specified
-- if border_color and M.config.glass.frosted_borders then
--   new_hl.border = border_color
-- end
--
--     vim.api.nvim_set_hl(0, group_name, new_hl)
--   end
-- end
--

local function create_glass(group_name, opacity)
  local success, hl_info = pcall(vim.api.nvim_get_hl, 0, { name = group_name })
  if not success or not hl_info then
    return
  end

  local new_hl = vim.tbl_extend("force", hl_info, {})

  if opacity > 0 then
    new_hl.bg = apply_opacity(hl_info.bg, opacity) or nil
    new_hl.blend = math.floor((1 - opacity) * 100)
  else
    new_hl.bg = nil
    new_hl.blend = 0
  end

  vim.api.nvim_set_hl(0, group_name, new_hl)
end

-- Main transparency function
local function apply_transparency()
  -- Skip if current colorscheme is in exclude list
  local current_scheme = vim.g.colors_name or ""
  if vim.tbl_contains(M.config.exclude_schemes, current_scheme) then
    return
  end

  if M.config.glass.enable then
    -- Apply glass effects
    -- Main editor area
    for _, group in ipairs({ 'Normal', 'NormalNC', 'SignColumn', 'LineNr', 'EndOfBuffer' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.editor)
      end
    end

    -- Sidebar elements
    for _, group in ipairs({ 'NvimTreeNormal', 'NeoTreeNormal', 'NvimTreeNormalNC', 'NeoTreeNormalNC' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.sidebar)
      end
    end

    -- Status line
    if M.config.enable.statusline then
      for _, group in ipairs({ 'StatusLine', 'StatusLineNC' }) do
        if not vim.tbl_contains(M.config.exclude_groups, group) then
          create_glass(group, M.config.glass.panel_opacity.statusline)
        end
      end
    end

    -- Tab line
    if M.config.enable.tabline then
      for _, group in ipairs({ 'TabLine', 'TabLineFill', 'TabLineSel' }) do
        if not vim.tbl_contains(M.config.exclude_groups, group) then
          create_glass(group, M.config.glass.panel_opacity.statusline)
        end
      end
    end

    -- Floating windows
    for _, group in ipairs({ 'NormalFloat', 'TelescopeNormal', 'WhichKeyFloat', 'LspFloatWinNormal', 'LazyNormal' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.floats)
      end
    end

    -- Popup menus
    for _, group in ipairs({ 'Pmenu', 'PmenuSel', 'CmpNormal' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, M.config.glass.panel_opacity.popups)
      end
    end

    -- Handling for borders to create frosted glass effect
    if M.config.glass.frosted_borders then
      vim.api.nvim_set_hl(0, "FloatBorder", {
        bg = "NONE",
        fg = "#4a4a4a"
      })
      vim.api.nvim_set_hl(0, "TelescopeBorder", {
        bg = "NONE",
        fg = "#4a4a4a"
      })
      vim.api.nvim_set_hl(0, "VertSplit", {
        bg = "NONE",
        fg = "#2a2a2a"
      })
      vim.api.nvim_set_hl(0, "WinSeparator", {
        bg = "NONE",
        fg = "#2a2a2a"
      })
    end
  else
    -- Fallback to simple transparency
    for _, group in ipairs(M.config.groups) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass(group, 0) -- Fully transparent
      end
    end
  end

  -- Apply transparency to extra groups
  for _, group in ipairs(M.config.extra_groups) do
    if not vim.tbl_contains(M.config.exclude_groups, group) then
      create_glass(group, M.config.glass.panel_opacity.floats)
    end
  end

  -- Special cursor line handling for glass effect
  if M.config.enable.cursorline then
    vim.api.nvim_set_hl(0, "CursorLine", {
      bg = "#0f0f0f",
    })
    vim.api.nvim_set_hl(0, "CursorLineNr", {
      bg = "none",
    })
  end

  -- Configure blending for floating elements
  vim.opt.winblend = math.floor(M.config.glass.panel_opacity.floats * 100)
  vim.opt.pumblend = math.floor(M.config.glass.panel_opacity.popups * 100)

  -- Force terminal gui colors
  vim.opt.termguicolors = true
end

-- Function to get all highlight groups (for debugging/inspection)
local function get_all_highlight_groups()
  local groups = {}
  local all_highlights = vim.api.nvim_get_hl(0, {})

  for name, _ in pairs(all_highlights) do
    table.insert(groups, name)
  end

  table.sort(groups)
  return groups
end

-- Setup function
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  -- Override vim.cmd.colorscheme to auto-apply transparency
  vim.cmd.colorscheme = function(scheme)
    original_colorscheme(scheme)
    -- Small delay to ensure colorscheme is fully loaded
    vim.defer_fn(apply_transparency, 10)
  end

  -- Create autocommand for ColorScheme event
  vim.api.nvim_create_augroup("GlassNvim", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = "GlassNvim",
    pattern = "*",
    callback = function()
      vim.defer_fn(apply_transparency, 10)
    end,
  })

  -- Apply transparency on initial load
  apply_transparency()

  -- Create user commands
  vim.api.nvim_create_user_command("Glassify", function()
    M.config.glass.enable = true
    apply_transparency()
    print("Nvim glassified ⋆｡°✩")
  end, { desc = "Enable glass effect" })

  vim.api.nvim_create_user_command("UnGlassify", function()
    M.config.glass.enable = false
    vim.cmd.colorscheme(vim.g.colors_name or "default")
    print("Glass effect disabled")
  end, { desc = "Disable glass effect" })

  vim.api.nvim_create_user_command("GlassToggle", function()
    if M.config.glass.enable then
      vim.cmd.UnGlassify()
    else
      vim.cmd.Glassify()
    end
  end, { desc = "Toggle glass effect" })

  vim.api.nvim_create_user_command("GlassListGroups", function()
    local groups = get_all_highlight_groups()
    print("All highlight groups:")
    for _, group in ipairs(groups) do
      print("  " .. group)
    end
  end, { desc = "List all highlight groups" })

  -- Mark as enabled
  vim.g.glass_enabled = M.config.glass.enable
end

-- Utility functions

-- Convert color int to rgb
function M.clear_prefix(prefix)
  local groups = get_all_highlight_groups()
  for _, group in ipairs(groups) do
    if string.match(group, "^" .. prefix) then
      create_glass(group, M.config.glass.panel_opacity.floats)
    end
  end
end

function M.clear_group(group, opacity)
  opacity = opacity or 0
  create_glass(group, opacity)
end

function M.add_group(group, opacity)
  opacity = opacity or M.config.glass.panel_opacity.floats
  table.insert(M.config.extra_groups, group)
  create_glass(group, opacity)
end

function M.remove_group(group)
  for i, g in ipairs(M.config.extra_groups) do
    if g == group then
      table.remove(M.config.extra_groups, i)
      break
    end
  end
end

-- Apply transparency (expose for manual calling)
function M.apply_transparency()
  apply_transparency()
end

-- Get current configuration
function M.get_config()
  return M.config
end

return M
