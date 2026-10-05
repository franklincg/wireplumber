-- WirePlumber
--
-- SPDX-License-Identifier: MIT
--
-- PulseAudio filter requests, without modifying the stream properties.

local module = {}

function module.get_request (properties, target_properties)
  local explicit = properties ["filter.apply"] ~= nil and
      properties ["filter.heuristics"] == nil
  local name = explicit and properties ["filter.apply"] or
      properties ["filter.want"]

  if type (name) ~= "string" or name == "" or
      properties ["filter.suppress"] == name then
    return nil
  end

  -- An explicit request takes precedence over the phone-device heuristic.
  if not explicit and name == "echo-cancel" and target_properties then
    local roles = target_properties ["device.intended-roles"] or ""
    for role in roles:gmatch ("%S+") do
      if role == "phone" then
        return nil
      end
    end
  end

  return name
end

return module
