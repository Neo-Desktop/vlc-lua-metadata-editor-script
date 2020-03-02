--[[
  Filename: ffmetadata.lua
  Description: ffmpeg metadata chapter creator

  - Inputs: any VLC file
  - Outputs: <filepath>/<filename>.ffm

  Usage:
  ffmpeg -i <filepath>/<filename> -i <filepath>/<filename>.ffm -map_metadata 1 -codec copy <filepath>/<filename>

  More Info: https://ffmpeg.org/ffmpeg-formats.html#Metadata-1

  Copyright 2020 Amrit Panesar [Neo-Desktop]
  See LICENSE for full license text
]]

-- Imports from VLC modules library -------------------------

require 'common'

-- VLC Required Descriptor Function -------------------------

function descriptor()
  return {
    title = "ffmetadata Editor",
    version = "0.01",
    author = "Amrit Panesar",
    url = 'https://github.com/Neo-Desktop/vlc-lua-metadata-editor-script',
    shortdesc = "ffmetadata Editor",
    description = "Edits metadata for use with ffmpeg",
    capabilities = {"playing-listener"}
  }
end

-- Globals -------------------------

CURRENT_FILE = nil
VLC_TIMEBASE = 1000000

-- Objects -------------------------

MetaClass = { }
MetaClass.__index = MetaClass

function MetaClass:New(filename)
  -- out.debug("New Class")
  self = self or {}
  input = vlc.object.input()
  if input ~= nil then
    self.FileName = filename
    self.Chapters = {}
    self.DisplayChapters = {}
    self.Dirty = false
    self.metadata = vlc.input.item():metas() or { }
    self.path = uri_to_path(vlc.input.item():uri())
    self.duration = vlc.input.item():duration() * VLC_TIMEBASE
    self:WalkChapters()
    self:SetDirty(true)
    -- self:Write()
    return self
  end
  return nil
end

function MetaClass:Write()
  --[[
    ["metadata"] = { ["encoded_by"] = "HandBrake 0.10.5 2016021100"; ["filename"] = "The Simpsons S01E02 Bart the Genius.mp4"; ["title"] = "The Simpsons S01E02 Bart the Genius"; };
  ]]--

  local file = io.open(self.path .. ".ffm", "w")
  local writeln = function(...) file:write(... .. "\n") end

  writeln(";FFMETADATA1")
  writeln("title=" .. self.metadata["title"] or "")
  writeln("")

  --[[
    ["Chapters"] = { [1] = 0; [2] = 90244999; [3] = 179278999; [4] = 628507999; [5] = 1002628999; [6] = 1330483999; };
  ]]--

  for k, v in pairs(self.Chapters) do
    local endDuration = nil
    if #self.Chapters >= k+1 then
      endDuration = self.Chapters[k+1]
    else 
      endDuration = self.duration
    end

    writeln("[CHAPTER]")
    writeln("TIMEBASE=1/" .. VLC_TIMEBASE)
    writeln("START=" .. v)
    writeln("END=" .. endDuration)
    writeln("title=Chapter " .. k)
    writeln("")
  end

  file:flush()
  file:close()
  self:SetDirty(false)
end

function MetaClass:AddChapter(time)
  table.insert(self.Chapters, time)
  local displayString = string.format("%s %s - [%s]", "Chapter", #self.Chapters, common.durationtostring(time/VLC_TIMEBASE))
  table.insert(self.DisplayChapters, displayString)
  self:SetDirty(true)
end

function MetaClass:RemoveChapter(displayString)
  for k, v in pairs(self.DisplayChapters) do 
    if v == displayString then
      out.debug("Removing Chapter [" .. v .. ']')
      table.remove(self.Chapters, k)
      table.remove(self.DisplayChapters, k)
      break
    end
  end
end

function MetaClass:WalkChapters()
  local total, chapterMap = vlc.var.get_list(input, "chapter")
  vlc.playlist.pause()
  for k,v in pairs(chapterMap) do
    vlc.var.set(vlc.object.input(), "chapter", k - 1 )
    sleep(0.001)
    local time = vlc.var.get(vlc.object.input(), "time")
    out.debug("Key: " .. k .. " | Chapter Index: " .. k-1 .. " | Time: " .. time)
    self:AddChapter(time)
  end
  vlc.var.set(vlc.object.input(), "time", 0)
end

function MetaClass:SetDirty(dirty)
  self.Dirty = dirty
  update_Title(dirty)
end

-- VLC Callbacks -------------------------

function activate()
  -- this is where extension starts
  -- for example activation of extension opens custom dialog box:
  create_dialog()
end

function deactivate()
  -- what should be done on deactivation of extension
end

function close()
  -- function triggered on dialog box close event
  -- for example to deactivate extension on dialog box close:
  if CURRENT_FILE and CURRENT_FILE.dirty then
    CURRENT_FILE:Write()
  end
  vlc.deactivate()
end

function meta_changed()
  -- this really shouldn't be getting called, but here we are
end

function playing_changed()
  -- related to capabilities={"playing-listener"} in descriptor()
  -- triggered by Pause/Play madia input event

  -- FIX ME: I legitamately have no idea how to determine if all metadata was loaded
  -- this logic is a really bad hack with magic numbers and a state machine
  if ( vlc.playlist.status() == "playing" and vlc.var.get(vlc.object.input(), "state") == 2 ) and 
    ( CURRENT_FILE == nil or vlc.input.item():uri() ~= CURRENT_FILE["uri"] ) then

    CURRENT_FILE = MetaClass:New(vlc.input.item():name())
    update_List()
    out.debug(out.show(CURRENT_FILE, "CURRENT_FILE"))
  end
end

-- Dialog box Functions -------------------------

function create_dialog()
  d = vlc.dialog("FFMpeg Metadata Writer")
  w1 = d:add_label("Title:", 1, 1, 3, 1)
  w2 = d:add_text_input("", 1, 2, 3, 1)
  w3 = d:add_list(1, 4, 4, 1)
  w4 = d:add_button("Add", click_Add, 1, 3, 1, 1)
  w5 = d:add_button("Remove", click_Remove, 2, 3, 1, 1)
  w6 = d:add_button("Clear", click_Clear, 3, 3, 1, 1)
  w7 = d:add_button("Save", click_Save, 1, 9, 1, 1)
end

function click_Add()
  if not vlc.object.input() then return nil end

  local time = vlc.var.get(vlc.object.input(), "time")
  CURRENT_FILE:AddChapter(time)
  update_List()
end

function click_Clear()
  if not CURRENT_FILE then return nil end

  CURRENT_FILE:Clear()
  update_List()
end

function click_Save()
  if not CURRENT_FILE then return nil end
  
  CURRENT_FILE.metadata["title"] = w2:get_text()
  CURRENT_FILE:Write()
end

function click_Remove()
  local selection = w3:get_selection()
  if (not selection) then return 1 end

  for k, v in pairs(selection) do
    CURRENT_FILE:RemoveChapter(v)
  end

  update_List()
end

function update_List()
  w2:set_text(CURRENT_FILE.metadata and CURRENT_FILE.metadata["title"] or "")
  w3:clear()
  for k, v in pairs(CURRENT_FILE.DisplayChapters) do
    w3:add_value(v)
  end
end

function update_Title(dirty)
  if dirty then
    d:set_title("* FFMpeg Metadata Writer")
  else
    d:set_title("FFMpeg Metadata Writer")
  end
end

-- Debug Library -------------------------

out = {}

function out.debugf(format, ...)
  vlc.msg.dbg(string.format("[%s] " .. format, 'ffmetadata', ...))
end

function out.debug(...)
  vlc.msg.dbg(string.format("[%s] %s", 'ffmetadata', ...))
end

function out.debug_dump()
  local test = { }
  test.InputStatus = vlc.playlist.status()
  test.PlaylistItem = vlc.playlist.get(vlc.playlist.current())
  test.URI = vlc.input.item():uri()
  test.Name = vlc.input.item():name()
  test.InputItem = vlc.input.item():info()
  test.Preparsed = vlc.input.item():is_preparsed()
  test.InputPlaying = vlc.input.is_playing()
  test.InputState = vlc.var.get(vlc.object.input(), "state")
  out.debug(out.show(test, "test"))
end

-- "Internal" Library Functions -------------------------

function uri_to_path(uri)
  -- "file:///Z:/aesthetictv/media/_animation/The%20Simpsons/The%20Simpsons%20S02E13%20Homer%20vs.%20Lisa%20and%20the%20Eighth%20Commandment.mp4"
  uri = decodeURI(uri)
  uri = string.gsub(uri, "file:///", "", 1)
  return string.gsub(uri, "/", '\\')
end

function sleep(s)
  local ntime = os.time() + s
  repeat until os.time() > ntime
end

-- "External" Library Fuctions -------------------------

-- decodeURI
-- https://gist.github.com/cgwxyz/6053d51e8d7134dd2e30
function decodeURI(s)
  if(s) then
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, '%%(%x%x)', 
      function (hex) return string.char(tonumber(hex,16)) end )
  end
  return s
end


--[[
   Author: Julio Manuel Fernandez-Diaz
   Date:   January 12, 2007
   (For Lua 5.1)
   
   Modified slightly by RiciLake to avoid the unnecessary table traversal in tablecount()

   Formats tables with cycles recursively to any depth.
   The output is returned as a string.
   References to other tables are shown as values.
   Self references are indicated.

   The string returned is "Lua code", which can be procesed
   (in the case in which indent is composed by spaces or "--").
   Userdata and function keys and values are shown as strings,
   which logically are exactly not equivalent to the original code.

   This routine can serve for pretty formating tables with
   proper indentations, apart from printing them:

      print(table.show(t, "t"))   -- a typical use
   
   Heavily based on "Saving tables with cycles", PIL2, p. 113.

   Arguments:
      t is the table.
      name is the name of the table (optional)
      indent is a first indentation (optional).
--]]
function out.show(t, name, indent)
   local cart     -- a container
   local autoref  -- for self references

   --[[ counts the number of elements in a table
   local function tablecount(t)
      local n = 0
      for _, _ in pairs(t) do n = n+1 end
      return n
   end
   ]]
   -- (RiciLake) returns true if the table is empty
   local function isemptytable(t) return next(t) == nil end

   local function basicSerialize (o)
      local so = tostring(o)
      if type(o) == "function" then
         local info = debug.getinfo(o, "S")
         -- info.name is nil because o is not a calling level
         if info.what == "C" then
            return string.format("%q", so .. ", C function")
         else 
            -- the information is defined through lines
            return string.format("%q", so .. ", defined in (" ..
                info.linedefined .. "-" .. info.lastlinedefined ..
                ")" .. info.source)
         end
      elseif type(o) == "number" or type(o) == "boolean" then
         return so
      else
         return string.format("%q", so)
      end
   end

   local function addtocart (value, name, indent, saved, field)
      indent = indent or ""
      saved = saved or {}
      field = field or name

      cart = cart .. indent .. field

      if type(value) ~= "table" then
         cart = cart .. " = " .. basicSerialize(value) .. ";\n"
      else
         if saved[value] then
            cart = cart .. " = {}; -- " .. saved[value] 
                        .. " (self reference)\n"
            autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
         else
            saved[value] = name
            --if tablecount(value) == 0 then
            if isemptytable(value) then
               cart = cart .. " = {};\n"
            else
               cart = cart .. " = {\n"
               for k, v in pairs(value) do
                  k = basicSerialize(k)
                  local fname = string.format("%s[%s]", name, k)
                  field = string.format("[%s]", k)
                  -- three spaces between levels
                  addtocart(v, fname, indent .. "   ", saved, field)
               end
               cart = cart .. indent .. "};\n"
            end
         end
      end
   end

   name = name or "__unnamed__"
   if type(t) ~= "table" then
      return name .. " = " .. basicSerialize(t)
   end
   cart, autoref = "", ""
   addtocart(t, name, indent)
   return cart .. autoref
end