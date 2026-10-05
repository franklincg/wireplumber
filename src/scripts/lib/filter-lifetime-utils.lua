-- WirePlumber
-- SPDX-License-Identifier: MIT

local module = {}

function module.new (load, report_error)
  local state = { requests = {}, count = 0, instance = nil, attempted = false }

  function state:update (id, requested)
    if requested and not self.requests[id] then
      self.requests[id] = true
      self.count = self.count + 1
    elseif not requested and self.requests[id] then
      self.requests[id] = nil
      self.count = self.count - 1
    end

    if self.count == 0 then
      if self.instance then
        self.instance:unload ()
        self.instance = nil
      end
      self.attempted = false
    elseif not self.attempted then
      -- Loading creates nodes and schedules further rescans. Do not retry on
      -- those events if a plugin is missing or cannot initialize.
      self.attempted = true
      local ok, instance = pcall (load)
      if ok and instance then
        self.instance = instance
      else
        report_error (ok and "module creation failed" or tostring (instance))
      end
    end
  end

  return state
end

return module
