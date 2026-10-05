-- WirePlumber
-- SPDX-License-Identifier: MIT

local requests = require ("filter-request-utils")
local phone = { ["device.intended-roles"] = "music phone" }
local other = { ["device.intended-roles"] = "headphone music" }
local cases = {
  { {}, nil },
  { { ["filter.want"] = "echo-cancel" }, "echo-cancel" },
  { { ["filter.apply"] = "echo-cancel" }, "echo-cancel" },
  { { ["filter.want"] = "echo-cancel", ["filter.apply"] = "" }, nil },
  { { ["filter.want"] = "echo-cancel", ["filter.apply"] = "other" }, "other" },
  { { ["filter.apply"] = "echo-cancel", ["filter.suppress"] = "echo-cancel" }, nil },
  { { ["filter.want"] = "echo-cancel", ["filter.suppress"] = "echo-cancel" }, nil },
  { { ["filter.want"] = "echo-cancel", ["filter.suppress"] = "other" }, "echo-cancel" },
  { { ["filter.want"] = "echo-cancel" }, nil, phone },
  { { ["filter.want"] = "echo-cancel" }, "echo-cancel", other },
  { { ["filter.apply"] = "echo-cancel" }, "echo-cancel", phone },
  { { ["filter.apply"] = "echo-cancel", ["filter.want"] = "echo-cancel",
      ["filter.heuristics"] = "1" }, nil, phone },
  { { ["filter.apply"] = "echo-cancel", ["filter.want"] = "echo-cancel",
      ["filter.heuristics"] = "1" }, "echo-cancel", other },
  { { ["filter.want"] = "echo-cancel-other" }, "echo-cancel-other" },
}
for i, case in ipairs (cases) do
  assert (requests.get_request (case[1], case[3]) == case[2], "request case " .. i)
end
