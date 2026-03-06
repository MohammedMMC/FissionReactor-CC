-- reactor-modem.lua
-- Runs on the computer connected directly to the reactor peripheral.
-- Reads reactor data via functions.lua and broadcasts it over a wireless modem.
-- Receives commands (setStatus, setBurnRate) from the display computer.

local r = require('functions')
local ok, config = pcall(require, 'config')
if not ok or type(config) ~= 'table' then config = {} end

local MODEM_CHANNEL = tonumber(config.MODEM_CHANNEL) or 42
local BROADCAST_INTERVAL = tonumber(config.REFRESH_INTERVAL) or 0.05

local peripheral = _G.peripheral
local parallel = _G.parallel
local osSleep = _G.os.sleep
local pullEvent = _G.os.pullEvent
local term = _G.term
local colors = _G.colors or _G.colours

local modem = peripheral.find('modem')
if not modem then
	error('No modem found! Attach a wireless modem.')
end
modem.open(MODEM_CHANNEL)

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.lime)
print('[ Reactor Modem Bridge ]')
term.setTextColor(colors.white)
print('Channel: ' .. MODEM_CHANNEL)
print('Broadcasting reactor data...')
print('')
print('Press Ctrl+T to stop.')

local function broadcast()
	while true do
		local data = {
			active   = r.getStatus(),
			dmg      = r.getDamage(),
			temp     = r.getTemp(),
			heatRate = r.getHeatingRate(),
			br       = r.getBurnRate(),
			brMax    = r.getBurnRate('max'),
			brPct    = r.getBurnRate('percent') or 0,
			fuel     = r.getFuel(),
			fuelMax  = r.getFuel('max'),
			fuelPct  = r.getFuel('percent') or 0,
			waste    = r.getWaste(),
			wasteMax = r.getWaste('max'),
			wastePct = r.getWaste('percent') or 0,
			cool     = r.getCoolant(),
			coolMax  = r.getCoolant('max'),
			coolPct  = r.getCoolant('percent') or 0,
			hot      = r.getHeatedCoolant(),
			hotMax   = r.getHeatedCoolant('max'),
			hotPct   = r.getHeatedCoolant('percent') or 0,
		}

		modem.transmit(MODEM_CHANNEL, MODEM_CHANNEL, {
			type = 'reactor_data',
			data = data,
		})

		osSleep(BROADCAST_INTERVAL)
	end
end

local function listen()
	while true do
		local _, _, ch, _, msg = pullEvent('modem_message')
		if ch == MODEM_CHANNEL and type(msg) == 'table' and msg.type == 'command' then
			if msg.cmd == 'setStatus' and type(msg.value) == 'boolean' then
				local ok, err = r.setStatus(msg.value)
				if not ok then
					term.setTextColor(colors.red)
					print('setStatus failed: ' .. tostring(err))
					term.setTextColor(colors.white)
				end
			elseif msg.cmd == 'setBurnRate' and type(msg.value) == 'number' then
				local ok, err = r.setBurnRate(msg.value)
				if not ok then
					term.setTextColor(colors.red)
					print('setBurnRate failed: ' .. tostring(err))
					term.setTextColor(colors.white)
				end
			end
		end
	end
end

if parallel and parallel.waitForAny then
	parallel.waitForAny(broadcast, listen)
else
	broadcast()
end
