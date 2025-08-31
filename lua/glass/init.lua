-- glass.nvim - Universal transparency plugin with glass pane effects
-- Author: Klsci
-- License: MIT

local M = {}

-- Default configuration
local default_config = {
  -- Glass pane effect settings
  glass = {
    enable = true,
    opacity = 0.85,
    blur_background = true,
    frosted_borders = true,
    panel_opacity = {
      editor = 0.0,  -- Main editor completely transparent
      sidebar = 0.0, -- Sidebars slightly tinted
      -- statusline = 0.1, -- Status line subtle tint
      floats = 0.2,  -- Floating windows more visible
      popups = 0.25, -- Popups most visible
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
    cursorline = false,
    statusline = false,
    tabline = true,
    winbar = true,
  }
}

-- Module state
M.config = default_config
local original_colorscheme = vim.cmd.colorscheme

-- Function to create glass pane effect with subtle background
local function create_glass_pane(group_name, opacity_level)
  -- Use pcall to safely get highlight group
  local success, hl = pcall(vim.api.nvim_get_hl, 0, { name = group_name, link = false })
  if not success then
    -- Fallback: create a new highlight group
    hl = {}
  end

  -- Ensure hl is a table
  if type(hl) ~= "table" then
    hl = {}
  end

  -- Create a very subtle tinted background for glass effect
  local bg_color = nil

  if opacity_level == 0.0 then
    bg_color = "none"    -- Fully transparent
  else
    bg_color = "#000000" -- Default to black if no overlay is defined
  end

  if opacity_level > 0.0 then
    -- Use a subtle dark overlay for glass panels
    local overlay_colors = {
      [0.05] = "#050505", -- Minimal tint
      [0.08] = "#080808", -- Status line
      [0.1] = "#0a0a0a",  -- Very subtle
      [0.12] = "#0c0c0c", -- Sidebar subtle
      [0.15] = "#0f0f0f", -- Sidebar normal
      [0.18] = "#121212", -- Float subtle
      [0.2] = "#141414",  -- Float normal
      [0.22] = "#161616", -- Popup subtle
      [0.25] = "#1a1a1a", -- Popup normal
      [0.3] = "#1e1e1e",  -- Strong glass
    }
    bg_color = overlay_colors[opacity_level] or "#0f0f0f"
  end

  hl.bg = bg_color

  -- Note: border_color is used for related border highlight groups
  -- but not applied directly to this group since 'border' is not a valid hl key

  vim.api.nvim_set_hl(0, group_name, hl)
end

-- Main transparency function with glass pane effects
local function apply_transparency()
  -- Skip if current colorscheme is in exclude list
  local current_scheme = vim.g.colors_name or ""
  if vim.tbl_contains(M.config.exclude_schemes, current_scheme) then
    return
  end

  if M.config.glass.enable then
    -- Apply glass pane effects with varying opacity levels

    -- Main editor - completely transparent
    for _, group in ipairs({ 'Normal', 'NormalNC', 'SignColumn', 'LineNr', 'EndOfBuffer' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass_pane(group, M.config.glass.panel_opacity.editor)
      end
    end

    -- Sidebar elements - subtle tint
    for _, group in ipairs({ 'NvimTreeNormal', 'NeoTreeNormal', 'NvimTreeNormalNC', 'NeoTreeNormalNC' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass_pane(group, M.config.glass.panel_opacity.sidebar)
      end
    end

    -- Status line - subtle glass panel
    if M.config.enable.statusline then
      for _, group in ipairs({ 'StatusLine', 'StatusLineNC' }) do
        if not vim.tbl_contains(M.config.exclude_groups, group) then
          create_glass_pane(group, M.config.glass.panel_opacity.statusline)
        end
      end
    end

    -- Tab line - subtle glass panel
    if M.config.enable.tabline then
      for _, group in ipairs({ 'TabLine', 'TabLineFill', 'TabLineSel' }) do
        if not vim.tbl_contains(M.config.exclude_groups, group) then
          create_glass_pane(group, M.config.glass.panel_opacity.statusline)
        end
      end
    end

    -- Floating windows - more visible glass
    for _, group in ipairs({ 'NormalFloat', 'TelescopeNormal', 'WhichKeyFloat', 'LspFloatWinNormal', 'LazyNormal' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass_pane(group, M.config.glass.panel_opacity.floats)
      end
    end

    -- Popup menus - most visible glass panels
    for _, group in ipairs({ 'Pmenu', 'PmenuSel', 'CmpNormal' }) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass_pane(group, M.config.glass.panel_opacity.popups)
      end
    end

    -- Special handling for borders to create frosted glass effect
    if M.config.glass.frosted_borders then
      vim.api.nvim_set_hl(0, "FloatBorder", {
        bg = "#1a1a1a",
        fg = "#4a4a4a"
      })
      vim.api.nvim_set_hl(0, "TelescopeBorder", {
        bg = "#1a1a1a",
        fg = "#4a4a4a"
      })
      vim.api.nvim_set_hl(0, "VertSplit", {
        bg = "none",
        fg = "#2a2a2a"
      })
      vim.api.nvim_set_hl(0, "WinSeparator", {
        bg = "none",
        fg = "#2a2a2a"
      })
    end
  else
    -- Fallback to simple transparency
    for _, group in ipairs(M.config.groups) do
      if not vim.tbl_contains(M.config.exclude_groups, group) then
        create_glass_pane(group, 0) -- Fully transparent
      end
    end
  end

  -- Apply transparency to extra groups
  for _, group in ipairs(M.config.extra_groups) do
    if not vim.tbl_contains(M.config.exclude_groups, group) then
      create_glass_pane(group, M.config.glass.panel_opacity.floats)
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
  vim.api.nvim_create_user_command("GlassEnable", function()
    M.config.glass.enable = true
    apply_transparency()
    print("Glass effect enabled")
  end, { desc = "Enable glass effect" })

  vim.api.nvim_create_user_command("GlassDisable", function()
    M.config.glass.enable = false
    vim.cmd.colorscheme(vim.g.colors_name or "default")
    print("Glass effect disabled")
  end, { desc = "Disable glass effect" })

  vim.api.nvim_create_user_command("GlassToggle", function()
    if M.config.glass.enable then
      vim.cmd.GlassDisable()
    else
      vim.cmd.GlassEnable()
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
function M.clear_prefix(prefix)
  local groups = get_all_highlight_groups()
  for _, group in ipairs(groups) do
    if string.match(group, "^" .. prefix) then
      create_glass_pane(group, M.config.glass.panel_opacity.floats)
    end
  end
end

function M.clear_group(group, opacity)
  opacity = opacity or 0
  create_glass_pane(group, opacity)
end

function M.add_group(group, opacity)
  opacity = opacity or M.config.glass.panel_opacity.floats
  table.insert(M.config.extra_groups, group)
  create_glass_pane(group, opacity)
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
