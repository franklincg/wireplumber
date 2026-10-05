-- WirePlumber
-- SPDX-License-Identifier: MIT

local lifetime = require ("filter-lifetime-utils")
local loads, unloads, errors = 0, 0, 0
local fail = false
local manager = lifetime.new (function ()
  loads = loads + 1
  if fail then error ("missing AEC plugin") end
  return { unload = function () unloads = unloads + 1 end }
end, function () errors = errors + 1 end)

manager:update (1, false)
assert (loads == 0 and manager.count == 0)
for id = 1, 100 do
  manager:update (id, true)
  manager:update (id, true)
end
assert (loads == 1 and manager.count == 100 and unloads == 0)
for id = 1, 99 do
  manager:update (id, false)
  manager:update (id, false)
end
assert (unloads == 0 and manager.count == 1)
manager:update (100, false)
assert (unloads == 1 and manager.instance == nil and manager.count == 0)

manager:update (1, true)
assert (loads == 2)
manager:update (1, false)
assert (unloads == 2)

fail = true
for id = 1, 100 do manager:update (id, true) end
assert (loads == 3 and errors == 1 and manager.instance == nil)
for id = 1, 100 do manager:update (id, false) end
fail = false
manager:update (1, true)
assert (loads == 4 and errors == 1)
manager:update (1, false)
assert (unloads == 3)

local nil_manager = lifetime.new (function () return nil end,
    function () errors = errors + 1 end)
nil_manager:update (1, true)
nil_manager:update (1, true)
assert (errors == 2)
nil_manager:update (1, false)
assert (nil_manager.count == 0)
