-- WirePlumber
-- SPDX-License-Identifier: MIT

local filters = require ("filter-utils")

local function target (id, link_group)
  local n = { properties = { ["node.link-group"] = link_group } }
  return { id = id, get_associated_proxy = function () return n end }
end

local function filter (id, name, on_request, direction, device)
  local group = "filter-" .. id
  return {
    name = name, link_group = group, direction = direction,
    media_type = "Audio", smart = true, disabled = false,
    on_request = on_request, target = device, targetless = device == nil,
    main_si = target (id, group),
  }
end

-- Both capture and playback, targetless and device-bound, and every position
-- of the request-only entry relative to two permanent processing stages.
for _, direction in ipairs ({ "input", "output" }) do
  for target_case = 1, 2 do
    local device = target_case == 1 and target (900) or nil
    local other = target (901)
    for position = 1, 3 do
      local first = filter (10, "first", false, direction, device)
      local last = filter (20, "last", false, direction, device)
      local echo = filter (30, "echo-cancel", true, direction, device)
      filters.filters = { first, last }
      table.insert (filters.filters, position, echo)

      assert (filters.get_filter_from_target (direction, "Audio", device) == first.main_si,
          "ordinary stream must bypass the request-only entry")
      assert (filters.get_filter_from_target (direction, "Audio", device, "other") == first.main_si)
      assert (filters.get_filter_from_target (direction, "Audio", device, "echo-cancel") == echo.main_si)
      assert (filters.get_filter_target (direction, echo.link_group) == first.main_si)
      assert (filters.get_filter_target (direction, first.link_group) == last.main_si)
      assert (filters.get_filter_target (direction, last.link_group) == device)
      assert (filters.get_filter_from_target (direction, "Video", device, "echo-cancel") == nil)
      assert (filters.get_filter_from_target (direction, "Audio", other, "echo-cancel") == nil)

      -- Resolving an already-selected smart filter must preserve the request.
      assert (filters.get_filter_from_target (direction, "Audio", last.main_si, "echo-cancel") == echo.main_si)
      assert (filters.get_filter_from_target (direction, "Audio", echo.main_si) == first.main_si)
      echo.disabled = true
      assert (filters.get_filter_from_target (direction, "Audio", device, "echo-cancel") == first.main_si)
      echo.disabled = false
      echo.smart = false
      assert (filters.get_filter_from_target (direction, "Audio", device, "echo-cancel") == first.main_si)
    end
  end
end

-- No permanent filter: unrelated streams keep their device unchanged.
do
  local echo = filter (30, "echo-cancel", true, "input", nil)
  filters.filters = { echo }
  assert (filters.get_filter_from_target ("input", "Audio", nil) == nil)
  assert (filters.get_filter_from_target ("input", "Audio", nil, "echo-cancel") == echo.main_si)
  assert (filters.get_filter_from_target ("output", "Audio", nil, "echo-cancel") == nil)
  assert (filters.get_filter_target ("input", echo.link_group) == nil)
end

-- Request-only filters must not chain into each other.
do
  local a = filter (30, "echo-cancel", true, "input", nil)
  local b = filter (40, "other", true, "input", nil)
  filters.filters = { a, b }
  assert (filters.get_filter_target ("input", a.link_group) == nil)
  assert (filters.get_filter_target ("input", b.link_group) == nil)
  assert (filters.get_filter_from_target ("input", "Audio", nil, "other") == b.main_si)
end

-- An absent configured target must not join a default-device chain.
do
  local a = filter (30, "echo-cancel", true, "input", nil)
  a.targetless = false
  local b = filter (40, "default-only", false, "input", nil)
  filters.filters = { a, b }
  assert (filters.get_filter_target ("input", a.link_group) == nil)
  assert (filters.get_filter_from_target ("input", "Audio", nil, "echo-cancel") == b.main_si)
end
filters.filters = {}
