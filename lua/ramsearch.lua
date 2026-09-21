-- ramsearch.lua  (bead sam-aug.1)
-- Snapshot-and-diff search over a range of maincpu program space.
--
--   local RS = dofile(dir .. "ramsearch.lua")
--   local s = RS.new{ base = 0x100000, size = 0x10000, width = 16 }  -- width 8 or 16
--   s:snapshot("idle")               -- take a snapshot, label it
--   s:filter("changed")              -- narrow candidates: compare last two snapshots
--   s:filter("increased") / ("decreased") / ("unchanged")
--   s:filter("equal", 0x60)          -- current value == v
--   s:filter("delta", -4)            -- new - old == n
--   s:filter("between", lo, hi)      -- lo <= current <= hi
--   s:count()                        -- candidates left
--   s:report(path, limit)            -- write "addr old new" lines (append)
--   s:values(addr)                   -- history of one address across snapshots
--   s:reset()                        -- all addresses are candidates again
--
-- Reads use space:read_range(start, end, 8) (one call per snapshot) and the
-- 16-bit view is decoded big-endian, as the 68000 stores it. RS.selftest()
-- checks read_range against read_u8/read_u16 at a few addresses so the byte
-- order is verified, not assumed.

local RS = {}
RS.__index = RS

local function space()
  return manager.machine.devices[":maincpu"].spaces["program"]
end

function RS.new(opt)
  local o = setmetatable({}, RS)
  o.base  = opt.base or 0x100000
  o.size  = opt.size or 0x10000
  o.width = opt.width or 16
  o.step  = o.width // 8
  o.snaps = {}          -- list of { label = , data = <string of bytes> }
  o.log   = opt.log     -- optional function(string)
  o:reset()
  return o
end

function RS:reset()
  self.cand = {}
  for off = 0, self.size - self.step, self.step do self.cand[#self.cand + 1] = off end
end

function RS:count() return #self.cand end

function RS:snapshot(label)
  local data = space():read_range(self.base, self.base + self.size - 1, 8)
  self.snaps[#self.snaps + 1] = { label = label or ("#" .. (#self.snaps + 1)), data = data }
  if self.log then self.log(string.format("snapshot %-12s %d bytes", label or "", #data)) end
  return #self.snaps
end

-- value at offset in snapshot string (1-based string index = off + 1)
function RS:value(data, off)
  if self.width == 8 then return data:byte(off + 1) end
  local hi, lo = data:byte(off + 1, off + 2)
  return hi * 256 + lo
end

local function keep(self, pred)
  local a, b = self.snaps[#self.snaps - 1], self.snaps[#self.snaps]
  assert(b, "need at least one snapshot")
  local out = {}
  for _, off in ipairs(self.cand) do
    local new = self:value(b.data, off)
    local old = a and self:value(a.data, off) or nil
    if pred(old, new) then out[#out + 1] = off end
  end
  local before = #self.cand
  self.cand = out
  return before, #out
end

function RS:filter(mode, x, y)
  local pred
  if     mode == "changed"   then pred = function(o, n) return o ~= nil and n ~= o end
  elseif mode == "unchanged" then pred = function(o, n) return o ~= nil and n == o end
  elseif mode == "increased" then pred = function(o, n) return o ~= nil and n > o end
  elseif mode == "decreased" then pred = function(o, n) return o ~= nil and n < o end
  elseif mode == "equal"     then pred = function(o, n) return n == x end
  elseif mode == "delta"     then pred = function(o, n) return o ~= nil and n - o == x end
  elseif mode == "between"   then pred = function(o, n) return n >= x and n <= y end
  else error("unknown filter " .. tostring(mode)) end
  local before, after = keep(self, pred)
  if self.log then self.log(string.format("filter %-9s %s -> %d candidates (from %d)", mode, x and tostring(x) or "", after, before)) end
  return after
end

function RS:values(off)
  local t = {}
  for i, s in ipairs(self.snaps) do t[i] = self:value(s.data, off) end
  return t
end

function RS:report(path, limit)
  limit = limit or 50
  local f = assert(io.open(path, "a"))
  local a, b = self.snaps[#self.snaps - 1], self.snaps[#self.snaps]
  f:write(string.format("-- %d candidates, width %d, last two snapshots: %s -> %s\n",
    #self.cand, self.width, a and a.label or "-", b.label))
  for i, off in ipairs(self.cand) do
    if i > limit then f:write(string.format("-- ... %d more\n", #self.cand - limit)); break end
    local vals = self:values(off)
    local hist = {}
    for j, v in ipairs(vals) do hist[j] = string.format(self.width == 8 and "%02X" or "%04X", v) end
    f:write(string.format("0x%06X  %s\n", self.base + off, table.concat(hist, " ")))
  end
  f:close()
end

function RS.selftest(log)
  local sp = space()
  local ok = true
  local raw = sp:read_range(0x100000, 0x10000F, 8)
  for i = 0, 15 do
    local a, b = raw:byte(i + 1), sp:read_u8(0x100000 + i)
    if a ~= b then ok = false; log(string.format("selftest MISMATCH at 0x%06X: range %02X vs read_u8 %02X", 0x100000 + i, a, b)) end
  end
  local be = raw:byte(1) * 256 + raw:byte(2)
  local u16 = sp:read_u16(0x100000)
  log(string.format("selftest read_range vs read_u8 over 16 bytes: %s; big-endian decode 0x%04X vs read_u16 0x%04X: %s",
    ok and "match" or "MISMATCH", be, u16, be == u16 and "match" or "MISMATCH"))
  return ok and be == u16
end

return RS
