-- Motion for Pathwise UI: short eased tweens for hovers, fades, switches and
-- scrolling, so the interface moves instead of snapping.
--
-- One driver frame runs every tween and is hidden (no OnUpdate at all) while
-- nothing moves. A tween is keyed by its owner and a name: starting another
-- with the same key takes over from wherever the last one got to, so a quick
-- hover in and out never jumps.
--
--   A.Tween(owner, key, to, dur, apply(v), done)   from the last value, eased
--   A.Set(owner, key, v, apply)                     jump there (no motion)
--   A.Get(owner, key)                               where it is now
--   A.Fade(frame, alpha, dur, done)                 a frame's alpha
--   A.Hover(owner, on, apply(p))                    0 -> 1 on hover, 0.12 s
--   A.Mix(a, b, p)                                  color between two
--
-- "look.motion" off makes every tween land at once.

local ADDON, ns = ...
local A = {}
ns.Anim = A

ns.Defaults("look", { motion = true })

A.FAST, A.NORMAL, A.SLOW = 0.12, 0.18, 0.3

local tweens = {} -- owner -> key -> tween
local values = setmetatable({}, { __mode = "k" }) -- owner -> key -> last value
local count = 0

local function outCubic(t) t = 1 - t return 1 - t * t * t end

local driver = CreateFrame("Frame")
driver:Hide()

local function finish(owner, key, tw)
	tweens[owner][key] = nil
	if next(tweens[owner]) == nil then tweens[owner] = nil end
	count = count - 1
	if count <= 0 then count = 0 driver:Hide() end
	if tw.done then
		local ok, err = pcall(tw.done)
		if not ok then ns.Error("motion", err) end
	end
end

local function step(tw, owner, key, p)
	local v = tw.from + (tw.to - tw.from) * outCubic(p)
	values[owner] = values[owner] or {}
	values[owner][key] = v
	local ok, err = pcall(tw.apply, v)
	if not ok then ns.Error("motion", err) end
end

-- This frame's tweens are listed first, then stepped: a tween started or
-- stopped from inside one (an apply or done) never disturbs the walk.
local batch = {}
driver:SetScript("OnUpdate", function(_, dt)
	local n = 0
	for owner, list in pairs(tweens) do
		for key, tw in pairs(list) do
			n = n + 3
			batch[n - 2], batch[n - 1], batch[n] = owner, key, tw
		end
	end
	for i = 1, n, 3 do
		local owner, key, tw = batch[i], batch[i + 1], batch[i + 2]
		-- Still the live tween for this key (not replaced or stopped meanwhile)?
		if tweens[owner] and tweens[owner][key] == tw then
			tw.t = tw.t + (dt or 0)
			local p = tw.dur > 0 and math.min(1, tw.t / tw.dur) or 1
			step(tw, owner, key, p)
			if p >= 1 and tweens[owner] and tweens[owner][key] == tw then finish(owner, key, tw) end
		end
	end
	for i = n, 1, -1 do batch[i] = nil end
end)

function A.Get(owner, key)
	return values[owner] and values[owner][key]
end

function A.Set(owner, key, v, apply)
	local list = tweens[owner]
	if list and list[key] then
		list[key] = nil
		if next(list) == nil then tweens[owner] = nil end
		count = count - 1
		if count <= 0 then count = 0 driver:Hide() end
	end
	values[owner] = values[owner] or {}
	values[owner][key] = v
	if apply then apply(v) end
end

function A.Enabled() return ns.Get("look.motion") ~= false end

function A.Tween(owner, key, to, dur, apply, done)
	local from = A.Get(owner, key)
	if from == nil or not A.Enabled() or not dur or dur <= 0 or from == to then
		A.Set(owner, key, to, apply)
		if done then done() end
		return
	end
	tweens[owner] = tweens[owner] or {}
	if not tweens[owner][key] then count = count + 1 end
	tweens[owner][key] = { t = 0, dur = dur, from = from, to = to, apply = apply, done = done }
	driver:Show()
end

-- A frame's alpha. `done` runs once it gets there.
function A.Fade(frame, alpha, dur, done)
	if A.Get(frame, "alpha") == nil then
		local now = frame.GetAlpha and frame:GetAlpha()
		values[frame] = values[frame] or {}
		values[frame].alpha = type(now) == "number" and now or 1
	end
	A.Tween(frame, "alpha", alpha, dur or A.NORMAL, function(v) frame:SetAlpha(v) end, done)
end

-- Hover progress 0 -> 1 (in) or back (out); apply(p) paints it.
function A.Hover(owner, on, apply)
	if A.Get(owner, "hover") == nil then values[owner] = values[owner] or {} values[owner].hover = 0 end
	A.Tween(owner, "hover", on and 1 or 0, A.FAST, apply)
end

function A.Mix(a, b, p)
	return a[1] + (b[1] - a[1]) * p, a[2] + (b[2] - a[2]) * p, a[3] + (b[3] - a[3]) * p, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * p
end

function A.Busy() return count > 0 end
