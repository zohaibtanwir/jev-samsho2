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
--   s:filter("equal_snap", i)        -- current == value in snapshot i (e.g. landed after a jump)
--   s:filter("diff_snap", i)         -- current ~= value in snapshot i
--   s:count()                        -- candidates left
--   s:report(sink, limit)            -- sink = function(line) or a path (append); "addr v1 v2 ..." per candidate
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
    if pred(old, new, off) then out[#out + 1] = off end
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
  elseif mode == "equal_snap" then                       -- current == value in snapshot #x
    local ref = assert(self.snaps[x], "no such snapshot").data
    pred = function(o, n, off) return n == self:value(ref, off) end
  elseif mode == "diff_snap" then                        -- current ~= value in snapshot #x
    local ref = assert(self.snaps[x], "no such snapshot").data
    pred = function(o, n, off) return n ~= self:value(ref, off) end
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

-- report(sink, limit): sink is a function(line) (e.g. the script's logger)
-- or a file path opened in append mode. Never pass the path of a file the
-- caller already holds open: two handles on one file interleave badly.
function RS:report(sink, limit)
  limit = limit or 50
  local out
  local f
  if type(sink) == "function" then out = sink else f = assert(io.open(sink, "a")); out = function(l) f:write(l, "\n") end end
  local a, b = self.snaps[#self.snaps - 1], self.snaps[#self.snaps]
  local labels = {}
  for i, sn in ipairs(self.snaps) do labels[i] = sn.label end
  out(string.format("-- %d candidates, width %d, snapshots: %s", #self.cand, self.width, table.concat(labels, " ")))
  for i, off in ipairs(self.cand) do
    if i > limit then out(string.format("-- ... %d more", #self.cand - limit)); break end
    local hist = {}
    for j, v in ipairs(self:values(off)) do hist[j] = string.format(self.width == 8 and "%02X" or "%04X", v) end
    out(string.format("0x%06X  %s", self.base + off, table.concat(hist, " ")))
  end
  if f then f:close() end
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
