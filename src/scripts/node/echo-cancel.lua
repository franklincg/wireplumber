-- WirePlumber
-- SPDX-License-Identifier: MIT

local cutils = require ("common-utils")
local lutils = require ("linking-utils")
local rutils = require ("filter-request-utils")
local lifetime = require ("filter-lifetime-utils")
local log = Log.open_topic ("s-echo-cancel")
local config = Conf.get_section_as_json ("node.echo-cancel", Json.Object {}):parse ()
local observed = {}

local function filter_properties (name, target)
  local properties = {
    ["node.name"] = name,
    ["filter.smart"] = true,
    ["filter.smart.name"] = "echo-cancel",
    ["filter.smart.on-request"] = true,
  }
  if target then
    properties ["filter.smart.target"] = Json.Object { ["node.name"] = target }
  end
  return Json.Object (properties)
end

local function stream_properties (name)
  return Json.Object {
    ["node.name"] = name,
    ["node.passive"] = true,
    ["node.dont-fallback"] = true,
    ["node.linger"] = true,
    ["state.restore-props"] = false,
    ["state.restore-target"] = false,
  }
end

local args = Json.Object {
  ["source.props"] = filter_properties ("wp.echo-cancel.source", config.source),
  ["sink.props"] = filter_properties ("wp.echo-cancel.sink", config.sink),
  ["capture.props"] = stream_properties ("wp.echo-cancel.capture"),
  ["playback.props"] = stream_properties ("wp.echo-cancel.playback"),
}
local manager = lifetime.new (function ()
  return LocalModule ("libpipewire-module-echo-cancel", args:to_string (), {})
end, function (error)
  log:warning ("Cannot load on-request echo cancellation: " .. error)
end)

local function rescan ()
  Plugin.find ("standard-event-source"):call ("schedule-rescan", "linking")
end

SimpleEventHook {
  name = "node/echo-cancel/track-streams",
  interests = {
    EventInterest { Constraint { "event.type", "=", "node-added" } },
    EventInterest { Constraint { "event.type", "=", "node-removed" } },
  },
  execute = function (event)
    local node = event:get_subject ()
    if event:get_properties () ["event.type"] == "node-removed" then
      observed[node.id] = nil
      manager:update (node.id, false)
      return
    end
    local props = node.properties
    if props["node.link-group"] or
        (props["media.class"] ~= "Stream/Output/Audio" and
         props["media.class"] ~= "Stream/Input/Audio") then
      return
    end
    if not observed[node.id] then
      observed[node.id] = true
      node:connect ("notify::properties", function (n)
        if observed[n.id] then rescan () end
      end)
    end
  end,
}:register ()

SimpleEventHook {
  name = "node/echo-cancel/request",
  after = { "linking/find-defined-target", "linking/find-filter-target",
      "linking/find-media-role-target", "linking/find-default-target",
      "linking/find-best-target" },
  before = { "linking/get-filter-from-target", "linking/prepare-link" },
  interests = {
    EventInterest { Constraint { "event.type", "=", "select-target" } },
  },
  execute = function (event)
    local source, om, si, props, flags, target = lutils.unwrap_select_target_event (event)
    local node = si:get_associated_proxy ("node")
    if not node or not observed[node.id] then return end
    local requested = false
    if target and not lutils.is_role_policy_target (props, target.properties) then
      local target_props = target:get_associated_proxy ("node").properties
      local configured_target = config.source
      if cutils.getTargetDirection (props) == "input" then
        configured_target = config.sink
      end
      local eligible = configured_target and target_props["node.name"] == configured_target or
          not configured_target and not flags.has_defined_target
      requested = eligible and not target_props["session.audio-group"] and
          rutils.get_request (node.properties, target_props) == "echo-cancel"
    end
    manager:update (node.id, not not requested)
  end,
}:register ()
