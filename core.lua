local MPGHName = "Mythic Plus Group Helper"
---@class MythicPlusGroupHelper
MythicPlusGroupHelper = LibStub("AceAddon-3.0"):NewAddon(MPGHName, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local AceGUI = LibStub("AceGUI-3.0")

MythicPlusGroupHelper.isFormingGroup = false
MythicPlusGroupHelper.ConvertToRaidTimer = nil

-- globals
local MAX_PLAYER_LEVEL = MAX_PLAYER_LEVEL

-- local constants
local d_warn = 1
local d_info = 2
local d_notice = 3
local d_debug = 4
local debugLevel = d_debug
local isDebug = true

local TANK = "TANK"
local DPS = "DAMAGER"
local HEALER = "HEALER"

local factionMapping = {
    ["Alliance"] = 1,
    ["Horde"] = 2
}

function MythicPlusGroupHelper:OnEnable()
  self:Debug(d_debug, "Initialized")
  self:RegisterChatCommand("mpgh", "ChatCommand")
  self:RegisterChatCommand("mm", "ChatCommand")
  self:Debug(d_debug, "Chat commands initialized. Use /mpgh help or /mm help to see the addon options.")
end

function MythicPlusGroupHelper:ConvertToRaid()
  -- Schedule a timer to watch for someone to join the group, then convert to raid
  self.ConvertToRaidTimer = self:ScheduleRepeatingTimer(function()
    local partyCount = GetNumGroupMembers()
    if (partyCount > 1 and self.isFormingGroup and not UnitInRaid("player")) then
      C_PartyInfo.ConvertToRaid()
    end
  end, 1)
  -- Stop after two minutes
  self:ScheduleTimer("CancelTimer", 120, self.ConvertToRaidTimer)
end

-- A function that invites all online guild members to a raid
function MythicPlusGroupHelper:InviteGuildToRaid()
  -- Get the number of guild members
  local numGuildMembers = GetNumGuildMembers()
  -- Loop through all guild members
  for i = 1, numGuildMembers do
    -- Get the name, rank, online status and class of the guild member
    local name, _ , _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
    -- If the guild member is online and not the player
    if online and name ~= UnitName("player") and level == MAX_PLAYER_LEVEL then
      -- Invite the guild member to the raid
      if not isDebug then
        C_PartyInfo.InviteUnit(name)
      end
        -- Print a message to the chat
      self:Debug(d_info, "Inviting " .. name .. " (" .. class .. ") to the raid")
    end
  end
end

-- A function that sorts the raid members into groups by role and rating
function MythicPlusGroupHelper:SortRaidByRoleAndRating()
  -- Define the order of roles
  local roleOrder = {TANK, HEALER, DPS}
  -- Define the number of groups and members per group
  local numGroups = 8
  local numMembers = 5
  -- Create a table to store the raid members by role
  local raidMembers = {}
  -- Loop through all roles
  for i, role in ipairs(roleOrder) do
    -- Create a subtable for each role
    self:Debug(d_debug, role)
    raidMembers[role] = {}
  end
  -- Get the number of raid members
  local numRaidMembers = GetNumGroupMembers()
  -- Loop through all raid members
  for i = 1, numRaidMembers do
    -- Get the name, role and rating of the raid member
    local role = select(12, GetRaidRosterInfo(i))
    local raidIndex = "raid"..i
    local name, realm = UnitFullName(raidIndex)
    if (realm == nil) then
        realm = GetRealmName()
    end
    local faction = factionMapping[UnitFactionGroup(name)]
    local rating = self:GetMythicRating(name, realm, faction)
    self:Debug(d_debug, "name, faction, rating: ", name, faction, rating)
    -- Insert the raid member into the table by role
    self:Debug(d_debug, "Insert into raid table: ", self:DumpTable(raidMembers), name, role, rating, realm, faction)
    table.insert(raidMembers[role], {name = name, rating = rating})
  end
  -- Create a table to store the sorted groups
  local sortedGroups = {}
  -- Loop through all groups
  for i = 1, numGroups do
    -- Create a subtable for each group
    sortedGroups[i] = {}
    -- Loop through all members
    for j = 1, numMembers do
      -- Create a subtable for each member
      sortedGroups[i][j] = {}
    end
  end
  -- Define a variable to keep track of the current group and member index
  local groupIndex = 1
  local memberIndex = 1
  -- Loop through all roles
  for i, role in ipairs(roleOrder) do
    -- Sort the raid members by rating
    table.sort(raidMembers[role], function(a, b) return a.rating > b.rating end)
    -- Loop through all raid members
    for k, member in ipairs(raidMembers[role]) do
      -- Assign the raid member to the current group and member index
      sortedGroups[groupIndex][memberIndex] = member
      -- Print a message to the chat
      self:Debug(d_debug, "Assigning " .. member.name .. " (" .. role .. ") to group " .. groupIndex .. " slot " .. memberIndex)
      -- Increment the member index
      memberIndex = memberIndex + 1
      -- If the member index exceeds the number of members per group
      if memberIndex > numMembers then
        -- Reset the member index
        memberIndex = 1
        -- Increment the group index
        groupIndex = groupIndex + 1
        -- If the group index exceeds the number of groups
        if groupIndex > numGroups then
          -- Break the loop
          break
        end
      end
    end
  end
  -- Loop through all groups
  for i = 1, numGroups do
    -- Loop through all members
    for j = 1, numMembers do
      -- Get the name of the raid member
      local name = sortedGroups[i][j].name
      -- Set the raid member to the corresponding group and slot
      SetRaidSubgroup(i, j, name)
    end
  end
end

function MythicPlusGroupHelper:GetMythicRating(name, realm, faction)
  local profile = RaiderIO.GetProfile(name, realm, faction)
  if (profile) then
    return profile.mythicKeystoneProfile.currentScore
  else
    return 0
  end
end

function MythicPlusGroupHelper:SortByRating(a, b)
  return a.rating > b.rating
end

function MythicPlusGroupHelper:Debug(level, ...)
  if (level <= debugLevel) then
      self:Print(...)
  end
end

function MythicPlusGroupHelper:DumpTable(table)
  if type(table) ~= "table" then
    -- if the original arg isn't a table, we need to catch that case before the pairs() call
    self:Debug(d_debug, "Table dump recursion, not a table (".. type(table) .."):", table);
    return
  end
  for k, v in pairs(table) do
    if type(v == "table") then
      self:DumpTable(v)
    else
      -- Print the value to the console
      self:Debug(d_debug, "Table dump:", k, v)
    end
  end
end 

function MythicPlusGroupHelper:ChatCommand(arg)
  if (arg == "help") then
    self:Print("Usage: /mpgh or /mm + <command>")
    self:Print("Currently supported commands:")
    self:Print("'invite' or 'i' will invite all max level guild members to a raid group")
    self:Print("'sort' or 's' will execute an algorithm to define groups with 1 tank, 1 healer, and 3 dps (as available) that have similar Mythic+ ratings")
    self:Print("'send' will finalize the groups after an adjustments are made and announce who is together")
    self:Print("Features to be implemented:")
    self:Print("Defining which key each group will be running")
    self:Print("Adding information to the raid roster to facilitate group management")
    return
  end
  local count = GetNumGroupMembers()
  if (count == 0 and not isDebug) then
    self:Debug(d_warn, "This command requires you to be in a group: " .. arg)
    self:Debug(d_warn, "Sorry, WoW makes it hard to wait for a group without freezing the game - Laserfox-Thrall")
    return
  end
  -- If the message is "invite"
  if arg == "invite" or arg == "i" then
    self.isFormingGroup = true
    self:Debug(d_debug, "isFormingGroup: ", arg, tostring(self.isFormingGroup))
    -- Run the invite function
    self:InviteGuildToRaid()
  -- If the message is "sort"
  elseif arg == "sort" or arg == "s" then
    -- Run the sort function
    self:SortRaidByRoleAndRating()
  elseif arg == "send" then
    -- do the thing
    self.isFormingGroup = false
    self:Debug(d_debug, "isFormingGroup: ", arg, tostring(self.isFormingGroup))
  -- Otherwise
  else
    -- Print a usage message
    self:Debug(d_warn, "Use /mpgh help for available options")
  end
end

function MythicPlusGroupHelper:OnInitialize()
  self:RegisterEvent("GROUP_JOINED", function(event) self:Debug(d_debug, event) end)
end

function MythicPlusGroupHelper:OnDisable()
	self:UnregisterEvent("GROUP_JOINED")
end

function MythicPlusGroupHelper:Test()
  self:Debug(d_debug, "Test")
end
