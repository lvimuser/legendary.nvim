local State = require('legendary.data.state')
local Keymap = require('legendary.data.keymap')

local Lazy = require('legendary.vendor.lazy')
---@type ItemGroup
local ItemGroup = Lazy.require_on_exported_call('legendary.data.itemgroup')

local M = {}

local function longest_matching_group(wk, wk_groups)
  local matching_group = {}
  for prefix, group_data in pairs(wk_groups) do
    if prefix == '' or vim.startswith(wk.prefix, prefix) and #prefix > #(matching_group[1] or '') then
      matching_group = { prefix, group_data }
    end
  end

  return matching_group[2]
end

local did_load_wk
local function walk_wk(mapping)
  local Util = require('which-key.util')
  local WKConfig = require('which-key.config')
  local Keys = require('which-key.keys')

  local mode = Util.get_mode()
  local buf = vim.api.nvim_get_current_buf()

  if not did_load_wk then
    -- make sure the trees exist for update
    Keys.get_tree(mode)
    Keys.get_tree(mode, buf)
    -- update only trees related to buf
    Keys.update(buf)
  end
  did_load_wk = true

  local prefix_i = mapping.keys.keys
  local path = Keys.get_tree(mode).tree:path(prefix_i)
  local buf_path = Keys.get_tree(mode, buf).tree:path(prefix_i)

  -- vim.pretty_print({ m = mapping, prefix_i = prefix_i, bufpath = buf_path, path = path })

  local seen = {}
  for i = 2, #mapping.keys.notation - 1 do
    local node = buf_path[i]
    if not (node and node.mapping and node.mapping.label) then
      node = path[i]
    end

    local step = mapping.keys.notation[i]
    if node and node.mapping and node.mapping.label then
      -- step = node.mapping.group and (WKConfig.options.icons.group .. label) or label
      local label = node.mapping.label
      step = label
    end

    if WKConfig.options.key_labels[step] then
      -- step = WKConfig.options.key_labels[step]
      break
    end

    table.insert(seen, step)
    -- vim.pretty_print({
    --   i = i,
    --   step = step,
    --   -- m = node and node.mapping,
    --   g = node and node.mapping and node.mapping.group,
    --   label = node and node.mapping and node.mapping.label,
    -- })

    -- if WKConfig.options.key_labels[step] then
    --   step = WKConfig.options.key_labels[step]
    -- end
  end

  -- if #seen > 0 and seen[1] == 'l' then
  --   vim.pretty_print(mapping)
  -- end
  -- if #seen > 0 then
  --   vim.pretty_print(seen)
  -- end
  -- return table.concat(seen, WKConfig.options.icons.separator)
  return table.concat(seen, ' > ')
end

---@param wk table
---@param wk_opts table
---@param use_groups boolean
---@return table
local function wk_to_legendary(wk, wk_opts, wk_groups, use_groups)
  if use_groups == nil then
    use_groups = true
  end

  local legendary = {}
  legendary[1] = wk.prefix
  if wk.cmd then
    legendary[2] = wk.cmd
  end
  if wk_opts and wk_opts.mode then
    legendary.mode = wk_opts.mode
  end
  if wk.group == true and #wk.name > 0 and use_groups then
    legendary.itemgroup = wk.name
  end
  local group = use_groups and longest_matching_group(wk, wk_groups) or nil
  if group and use_groups then
    legendary.itemgroup = group
  end
  legendary.description = wk.label or vim.tbl_get(wk, 'opts', 'desc')
  legendary.opts = wk.opts or {}
  legendary.kind = walk_wk(wk)
  return legendary
end

local function parse_to_itemgroups(legendary_tbls)
  local keymaps = {}
  local itemgroups = {}
  for _, keymap in ipairs(legendary_tbls) do
    if keymap.itemgroup then
      itemgroups[keymap.itemgroup] = itemgroups[keymap.itemgroup]
        or {
          itemgroup = keymap.itemgroup[1],
          description = keymap.itemgroup[1] ~= keymap.itemgroup[2] and keymap.itemgroup[2] or nil,
          keymaps = {},
        }

      table.insert(itemgroups[keymap.itemgroup].keymaps, keymap)
    else
      table.insert(keymaps, keymap)
    end
  end

  local groups = vim.tbl_values(itemgroups)
  return vim.list_extend(keymaps, groups, 1, #groups)
end

--- Take which-key.nvim tables
--- and parse them into legendary.nvim tables
---@param which_key_tbls table[]
---@param which_key_opts table
---@param do_binding boolean whether to bind the keymaps or let which-key handle it; default true
---@param use_groups boolean whether to use item groups; default true
---@return LegendaryItem[]
function M.parse_whichkey(which_key_tbls, which_key_opts, do_binding, use_groups)
  if do_binding == nil then
    do_binding = true
  end
  if use_groups == nil then
    use_groups = true
  end

  local wk_parsed = require('which-key.mappings').parse(which_key_tbls, which_key_opts)
  local legendary_tbls = {}
  local wk_groups = {}
  vim.tbl_map(function(maybe_group)
    if maybe_group.group == true and maybe_group.name then
      -- empty string for a top-level group without a prefix
      wk_groups[maybe_group.prefix or ''] = { maybe_group.name, maybe_group.label }
    end
  end, wk_parsed)
  vim.tbl_map(function(wk)
    if vim.tbl_get(wk, 'opts', 'desc') and wk.group ~= true then
      table.insert(legendary_tbls, wk_to_legendary(wk, which_key_opts, wk_groups, use_groups))
    end
  end, wk_parsed)

  if not do_binding then
    legendary_tbls = vim.tbl_map(function(item)
      item[2] = nil
      return item
    end, legendary_tbls)
  end

  return parse_to_itemgroups(legendary_tbls)
end

--- Bind a which-key.nvim table with legendary.nvim
---@param wk_tbls table
---@param wk_opts table
---@param do_binding boolean whether to bind the keymaps or let which-key handle it; default true
---@param use_groups boolean whether to use item groups; default true
function M.bind_whichkey(wk_tbls, wk_opts, do_binding, use_groups)
  if do_binding == nil then
    do_binding = true
  end
  if use_groups == nil then
    use_groups = true
  end

  local legendary_tbls = M.parse_whichkey(wk_tbls, wk_opts, do_binding, use_groups)
  State.items:add(vim.tbl_map(function(keymap)
    local parsed
    if keymap.itemgroup and keymap.keymaps then
      parsed = ItemGroup:parse(keymap)
    else
      parsed = Keymap:parse(keymap)
    end

    if do_binding then
      parsed:apply()
    end
    return parsed
  end, legendary_tbls))
end

return M
