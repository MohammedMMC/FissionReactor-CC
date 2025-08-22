local r = require('functions')
local ok, config = pcall(require, 'config')
if not ok or type(config) ~= 'table' then config = {} end

local term = _G.term
local colors = _G.colors or _G.colours
local peripheral = _G.peripheral
local osClock = _G.os.clock
local osSleep = _G.os.sleep
local pullEvent = _G.os.pullEvent
local parallel = _G.parallel
local floor, max = math.floor, math.max
local abs = math.abs
local fmtStr = string.format

local mon = peripheral and peripheral.find and peripheral.find('monitor') or term
if mon and mon.setTextScale then
	mon.setTextScale(0.5)
end
local useMon = mon ~= term
if useMon then
	term.redirect(mon)
end

do
	local target = colors.pink
	local rC, gC, bC = 0xF2 / 255, 0xD7 / 255, 0xB6 / 255
	if mon and mon.setPaletteColor then
		mon.setPaletteColor(target, rC, gC, bC)
	elseif term and term.setPaletteColor then
		term.setPaletteColor(target, rC, gC, bC)
	end
end

local REFRESH_INTERVAL = tonumber(config.REFRESH_INTERVAL) or 0.05
local buttons = {}
local w, h = term.getSize()

local safetyMode = true
local safetyShutdown = false
local safetyHighDanger = false
local safetyLastReason = nil
local SAFETY_TEMP_F = tonumber(config.SAFETY_TEMP_F) or 5000
local SAFETY_DMG_HIGH = tonumber(config.SAFETY_DMG_HIGH) or 50
local SAFETY_COOLANT_MIN = tonumber(config.SAFETY_COOLANT_MIN) or 20
local SAFETY_FUEL_MIN = tonumber(config.SAFETY_FUEL_MIN) or 5
local SAFETY_HEATED_MAX = tonumber(config.SAFETY_HEATED_MAX) or 99
local SAFETY_WASTE_MAX = tonumber(config.SAFETY_WASTE_MAX) or 99
local SAFETY_DMG_WARN = tonumber(config.SAFETY_DMG_WARN) or 20
local SAFETY_RESTART_COOLANT_MIN = tonumber(config.SAFETY_RESTART_COOLANT_MIN) or 15
local SAFETY_RESTART_FUEL_MIN = tonumber(config.SAFETY_RESTART_FUEL_MIN) or 5
local SAFETY_RESTART_HEATED_MAX = tonumber(config.SAFETY_RESTART_HEATED_MAX) or 99
local SAFETY_RESTART_WASTE_MAX = tonumber(config.SAFETY_RESTART_WASTE_MAX) or 99
local SAFETY_RESTART_DMG_MAX = tonumber(config.SAFETY_RESTART_DMG_MAX) or 20
local SAFETY_RESTART_TEMP_MAX = tonumber(config.SAFETY_RESTART_TEMP_MAX) or SAFETY_TEMP_F

local function resetSafetyShutdown()
	safetyShutdown = false
	safetyHighDanger = false
	safetyLastReason = nil
end

local function drawBtn(b, _, bg, fg)
	local bgc = bg or colors.blue
	local bh = b.h or 1
	for i = 0, bh - 1 do
		term.setCursorPos(b.x, b.y + i)
		term.setBackgroundColor(bgc)
		term.write(string.rep(' ', b.w))
	end
	local txt = b.l or ''
	term.setCursorPos(b.x + max(0, floor((b.w - #txt) / 2)), b.y + floor((bh - 1) / 2))
	term.setTextColor(fg or colors.white)
	term.write(txt:sub(1, b.w))
	term.setBackgroundColor(colors.black)
end

local function round(n)
	if type(n) ~= 'number' then
		return nil
	end
	return n >= 0 and floor(n + 0.5) or math.ceil(n - 0.5)
end

local function fmt(n)
	if type(n) ~= 'number' then
		return 'n/a'
	end
	if n >= 1000 then
		return fmtStr('%.1fK', n / 1000)
	end
	return tostring(floor(n * 100 + 0.5) / 100)
end

local DEG = string.char(176)
local function kelvinToF(k)
	if type(k) ~= 'number' then
		return nil
	end
	return (k - 273.15) * 9 / 5 + 32
end

local function getBurnStep()
	local m = r.getBurnRate('max') or 0
	if m <= 0 then return 0.1 end
	if m < 1 then return 0.1 end
	local targetPresses = 30
	local raw = m / targetPresses
	local nice = {0.1,0.2,0.25,0.5,1,2,2.5,5,10,15,20,25,50,75,100,125,150,200,250,300,400,500,750,1000}
	for _, v in ipairs(nice) do
		if v >= raw then
			return v
		end
	end
	return nice[#nice]
end

local function normalizeRate(v)
	return floor(v * 100 + 0.5) / 100
end

local function adjustRate(dir)
	local cur = r.getBurnRate() or 0
	local maxR = r.getBurnRate('max') or cur
	local new = cur + getBurnStep() * dir
	if new < 0 then
		new = 0
	elseif new > maxR then
		new = maxR
	end
	new = normalizeRate(new)
	if new ~= cur then
		r.setBurnRate(new)
	end
end

local function toggleOnOff()
	local cur = r.getStatus()
	if cur then
		resetSafetyShutdown()
		r.setStatus(false)
	else
		resetSafetyShutdown()
		r.setStatus(true)
	end
end

local function toggleSafetyMode()
	safetyMode = not safetyMode
	if not safetyMode then
		resetSafetyShutdown()
	end
end

local firstDraw = true
local prevSnapshot = nil
local function draw()
	if firstDraw then
		term.setBackgroundColor(colors.black)
		term.clear()
		firstDraw = false
	end

	w, h = term.getSize()
	local snap = {
		active = r.getStatus(),
		dmg = r.getDamage(),
		temp = r.getTemp(),
		heatRate = r.getHeatingRate(),
		br = r.getBurnRate(),
		brMax = r.getBurnRate('max'),
		brPct = r.getBurnRate('percent') or 0,
		fuelPct = r.getFuel('percent') or 0,
		wastePct = r.getWaste('percent') or 0,
		coolPct = r.getCoolant('percent') or 0,
		hotPct = r.getHeatedCoolant('percent') or 0,
		w = w,
		h = h
	}
	local changed = false
	if not prevSnapshot then
		changed = true
	else
		for k, v in pairs(snap) do
			local pv = prevSnapshot[k]
			if type(v) == 'number' and type(pv) == 'number' then
				if abs(v - pv) > 0.01 then
					changed = true
					break
				end
			elseif v ~= pv then
				changed = true;
				break
			end
		end
	end
	if not changed then
		return
	end
	prevSnapshot = snap

	local active = snap.active
	local dmg = snap.dmg
	local temp = snap.temp
	local heatRate = snap.heatRate
	local br = snap.br
	local brMax = snap.brMax
	local brPct = snap.brPct
	local fuelPct = snap.fuelPct
	local wastePct = snap.wastePct
	local coolPct = snap.coolPct
	local hotPct = snap.hotPct

	local rightW = max(15, floor(w * 0.23))
	if w - rightW < 25 then
		rightW = max(12, w - 25)
	end
	local leftX, gap = 1, 1
	local leftW = w - rightW - gap
	local rightX = leftX + leftW + gap

	local newButtons = {}
	local function newAdd(id, x, y, wid, label, fn, height)
		newButtons[id] = {
			x = x,
			y = y,
			w = wid,
			h = height or 1,
			l = label,
			fn = fn
		}
	end

	local function resourceBox(order, title, pct, col)
		pct = tonumber(pct) or 0;
		if pct < 0 then
			pct = 0
		elseif pct > 100 then
			pct = 100
		end
		local boxH = floor(h / 4);
		if boxH < 3 then
			boxH = 3
		end
		local leftover = h - boxH * 4
		local thisH = boxH + (order == 4 and leftover or 0)
		local topMargin, bottomMargin = 1, 1
		local reserved = topMargin + 1 + bottomMargin
		if thisH < reserved + 1 then
			if thisH >= 2 then
				bottomMargin = 0
				reserved = topMargin + 1
			end
			if thisH < 2 then
				topMargin, bottomMargin, reserved = 0, 0, 1
			end
		end
		local y0 = 1 + (order - 1) * boxH
		for yy = 0, reserved - 1 do
			term.setCursorPos(leftX, y0 + yy)
			term.setBackgroundColor(colors.black)
			term.write(string.rep(' ', leftW))
		end
		term.setCursorPos(leftX + 1, y0 + topMargin)
		term.setBackgroundColor(colors.black)
		term.setTextColor(colors.white)
		term.write(title)
		local pctTxt = fmtStr('%d%%', floor(pct + 0.5))
		local px = leftX + leftW - #pctTxt
		if px <= leftX + #title + 1 then
			px = leftX + #title + 2
		end
		term.setCursorPos(px, y0 + topMargin)
		term.write(pctTxt)
		local areaTop = y0 + reserved
		local areaH = thisH - reserved
		local wasteBottomMargin = (order == 4) and 1 or 0
		if wasteBottomMargin > 0 and areaH > wasteBottomMargin then
			areaH = areaH - wasteBottomMargin
		end
		local fillW = floor(leftW * pct / 100 + 0.5);
		if fillW > leftW then
			fillW = leftW
		end
		for yy = 0, areaH - 1 do
			term.setCursorPos(leftX, areaTop + yy)
			term.setBackgroundColor(colors.black)
			term.write(string.rep(' ', leftW))
			if fillW > 0 then
				term.setCursorPos(leftX, areaTop + yy)
				term.setBackgroundColor(col)
				term.write(string.rep(' ', fillW))
			end
		end
		if wasteBottomMargin > 0 then
			for i = 0, wasteBottomMargin - 1 do
				term.setCursorPos(leftX, areaTop + areaH + i)
				term.setBackgroundColor(colors.black)
				term.write(string.rep(' ', leftW))
			end
		end
	end

	resourceBox(1, 'Coolant', coolPct, colors.lightBlue)
	resourceBox(2, 'Fuel', fuelPct, colors.gray)
	resourceBox(3, 'Heated Coolant', hotPct, colors.pink)
	resourceBox(4, 'Waste', wastePct, colors.brown)

	local rightHeight = h
	local topH = floor(rightHeight / 2)
	local bottomH = rightHeight - topH
	local topY, bottomY = 1, 1 + topH

	local function fillRect(x, y, wid, hei, bg)
		for yy = 0, hei - 1 do
			term.setCursorPos(x, y + yy)
			term.setBackgroundColor(bg)
			term.write(string.rep(' ', wid))
		end
		term.setBackgroundColor(colors.black)
	end

	fillRect(rightX, topY, rightW, topH, colors.gray)
	local btnH = max(2, floor(topH / 2))
	local btnColor
	if active then
		btnColor = colors.lime
	else
		if safetyShutdown then
			if safetyHighDanger then
				btnColor = colors.magenta
			else
				btnColor = colors.orange
			end
		else
			btnColor = colors.red
		end
	end
	for yy = 0, btnH - 1 do
		term.setCursorPos(rightX, topY + yy)
		term.setBackgroundColor(btnColor)
		term.write(string.rep(' ', rightW))
	end
	local statusTxt = active and 'ONLINE' or 'OFFLINE'
	term.setCursorPos(rightX + floor((rightW - #statusTxt) / 2), topY + floor(btnH / 2))
	term.setTextColor(colors.white)
	term.write(statusTxt)
	newAdd('onoff', rightX, topY, rightW, 'BTN', toggleOnOff, btnH)

	local infoY = topY + btnH + 1
	local fTemp = kelvinToF(temp)
	local lines = {
		'Heat Rate: ' .. (heatRate and (fmt(heatRate) .. ' mB/t') or 'n/a'),
		'Damage: ' .. (dmg and (round(dmg) .. '%') or 'n/a'),
		'Temp: ' .. (fTemp and (fmt(fTemp) .. DEG .. 'F') or 'n/a')
	}
	for i, l in ipairs(lines) do
		if infoY + i - 1 < topY + topH then
			term.setCursorPos(rightX + 1, infoY + i - 1)
			term.setBackgroundColor(colors.gray)
			term.setTextColor(colors.white)
			term.write(l:sub(1, rightW - 2))
		end
	end

	local bottomPadding = 1
	local safetyBtnHeight = 3
	local safetyBtnY = topY + topH - bottomPadding - safetyBtnHeight
	if safetyBtnY >= infoY + #lines then
		local safetyLabel = 'Safety Mode'
		local sColor = safetyMode and colors.lime or colors.red
		local btnX = rightX + 1
		local btnW = rightW - 2
		if btnW >= 6 and safetyBtnY + safetyBtnHeight - 1 < topY + topH then
			for yy = 0, safetyBtnHeight - 1 do
				term.setCursorPos(btnX, safetyBtnY + yy)
				term.setBackgroundColor(sColor)
				term.write(string.rep(' ', btnW))
			end
			local labelY = safetyBtnY + math.floor(safetyBtnHeight / 2)
			term.setCursorPos(btnX + math.max(0, floor((btnW - #safetyLabel) / 2)), labelY)
			term.setTextColor(colors.white)
			term.write(safetyLabel:sub(1, btnW))
			term.setBackgroundColor(colors.black)
			newAdd('safety', btnX, safetyBtnY, btnW, safetyLabel, toggleSafetyMode, safetyBtnHeight)
		end
	end

	fillRect(rightX, bottomY, rightW, bottomH, colors.gray)
	local burnTopMargin, burnBottomMargin, titleLines = 1, 1, 1
	local buttonHeight = (bottomH >= 8 and 3) or (bottomH >= 6 and 2) or 1
	local reservedBR = burnTopMargin + titleLines + burnBottomMargin
	if bottomH < reservedBR + buttonHeight + 1 then
		burnBottomMargin = 0;
		reservedBR = burnTopMargin + titleLines
		if bottomH < reservedBR + buttonHeight + 1 then
			burnTopMargin = 0;
			reservedBR = titleLines
		end
	end
	for yy = 0, reservedBR - 1 do
		term.setCursorPos(rightX, bottomY + yy)
		term.setBackgroundColor(colors.black)
		term.write(string.rep(' ', rightW))
	end
	local titleY = bottomY + burnTopMargin
	term.setCursorPos(rightX + 1, titleY)
	term.setTextColor(colors.white)
	term.setBackgroundColor(colors.black)
	term.write('Burn Rate')
	local brDisp, brMaxDisp = br or 0, (brMax and round(brMax)) or 0
	local brStr = brDisp .. '/' .. brMaxDisp .. ' mB/t'
	local minAfterTitle = rightX + 11
	local brPos = rightX + rightW - #brStr;
	if brPos < minAfterTitle then
		brPos = minAfterTitle
	end
	term.setCursorPos(brPos, titleY)
	term.write(brStr:sub(1, rightW - (minAfterTitle - rightX)))
	local barTop = bottomY + reservedBR
	local barAreaH = bottomH - reservedBR - buttonHeight;
	if barAreaH < 1 then
		barAreaH = 1
	end
	local fillH = floor(barAreaH * brPct / 100 + 0.5)
	for i = 0, barAreaH - 1 do
		local yLine = barTop + barAreaH - 1 - i
		term.setCursorPos(rightX, yLine)
		term.setBackgroundColor(i < fillH and colors.orange or colors.black)
		term.write(string.rep(' ', rightW))
	end
	local btnTop = bottomY + bottomH - buttonHeight
	local halfW = floor(rightW / 2)
	newAdd('dec', rightX, btnTop, halfW, '-', function()
		adjustRate(-1)
	end, buttonHeight)
	newAdd('inc', rightX + halfW, btnTop, rightW - halfW, '+', function()
		adjustRate(1)
	end, buttonHeight)
	drawBtn(newButtons.dec, false, colors.red, colors.white)
	drawBtn(newButtons.inc, false, colors.green, colors.white)

	buttons = newButtons
end

local function handleClick(x, y)
	for _, b in pairs(buttons) do
		if x >= b.x and x < b.x + b.w and y >= b.y and y <= b.y + (b.h or 1) - 1 then
			b.fn();
			draw();
			return
		end
	end
end

local function inputLoop()
	while true do
		local ev, a, b, c = pullEvent()
		if (useMon and ev == 'monitor_touch') then
			handleClick(b, c)
		elseif (not useMon and ev == 'mouse_click') then
			handleClick(b, c)
		elseif ev == 'term_resize' then
			draw()
		end
	end
end

local function autoRedraw()
	while true do
		local status = r.getStatus()
		if safetyMode then
			local coolant = r.getCoolant and r.getCoolant('percent') or 0
			local fuel = r.getFuel and r.getFuel('percent') or 0
			local heated = r.getHeatedCoolant and r.getHeatedCoolant('percent') or 0
			local waste = r.getWaste and r.getWaste('percent') or 0
			local tempK = r.getTemp and r.getTemp() or 0
			local tempF = kelvinToF(tempK) or 0
			local dmg = r.getDamage and r.getDamage() or 0

			if status then
				local reason, highDanger = nil, false
				if dmg > SAFETY_DMG_HIGH then
					reason, highDanger = 'Damage >' .. SAFETY_DMG_HIGH .. '%', true
				elseif tempF > SAFETY_TEMP_F then
					reason, highDanger = 'Temp >' .. SAFETY_TEMP_F .. 'F', true
				elseif coolant < SAFETY_COOLANT_MIN then
					reason = 'Coolant <' .. SAFETY_COOLANT_MIN .. '%'
				elseif fuel < SAFETY_FUEL_MIN then
					reason = 'Fuel <' .. SAFETY_FUEL_MIN .. '%'
				elseif heated > SAFETY_HEATED_MAX then
					reason = 'Heated Coolant >' .. SAFETY_HEATED_MAX .. '%'
				elseif waste > SAFETY_WASTE_MAX then
					reason = 'Waste >' .. SAFETY_WASTE_MAX .. '%'
				elseif dmg > SAFETY_DMG_WARN then
					reason = 'Damage >' .. SAFETY_DMG_WARN .. '%'
				end
				if reason then
					r.setStatus(false)
					safetyShutdown = true
					safetyHighDanger = highDanger
					safetyLastReason = reason
					status = false
				end
			else
				if safetyShutdown and (not safetyHighDanger) then
					local allSafe = (coolant >= SAFETY_RESTART_COOLANT_MIN)
						and (fuel >= SAFETY_RESTART_FUEL_MIN)
						and (heated <= SAFETY_RESTART_HEATED_MAX)
						and (waste <= SAFETY_RESTART_WASTE_MAX)
						and (tempF <= SAFETY_RESTART_TEMP_MAX)
						and (dmg <= SAFETY_RESTART_DMG_MAX)
					if allSafe then
						resetSafetyShutdown()
						r.setStatus(true)
						status = true
					end
				end
			end
		end
		draw();
		osSleep(REFRESH_INTERVAL)
	end
end

draw()
if parallel and parallel.waitForAny then
	parallel.waitForAny(autoRedraw, inputLoop)
else
	autoRedraw()
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.white)
term.write('Reactor UI closed.')
