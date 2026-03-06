local BASE = "https://raw.githubusercontent.com/MohammedMMC/FissionReactor-CC/refs/heads/main/"

local function header()
	term.setTextColor(colors.lime)
	print("Fission Reactor Control System")
	print("==============================")
	term.setTextColor(colors.white)
	print("")
end

local function ask(prompt, options)
	while true do
		write(prompt)
		local input = read()
		for _, v in ipairs(options) do
			if input == v then return input end
		end
		term.setTextColor(colors.red)
		print("Invalid choice. Please enter one of: " .. table.concat(options, ", "))
		term.setTextColor(colors.white)
	end
end

local function setConfigValue(key, value)
	local f = io.open("config.lua", "r")
	if not f then return end
	local content = f:read("*a")
	f:close()

	local newVal = (value == true) and "true" or (value == false) and "false" or tostring(value)
	content = content:gsub("(" .. key .. "%s*=%s*)(%a+)", "%1" .. newVal, 1)

	f = io.open("config.lua", "w")
	if not f then return end
	f:write(content)
	f:close()
end

header()

print("Select installation mode:")
print("  [1] Display Computer  - Shows the reactor UI")
print("  [2] Modem Bridge      - Sits next to the reactor (wireless only)")
print("")

local mode = ask("Choice (1/2): ", {"1", "2"})
print("")

if mode == "2" then
	print("Installing Modem Bridge...")
	shell.run("wget " .. BASE .. "functions.lua functions.lua")
	shell.run("wget " .. BASE .. "config.lua config.lua")
	shell.run("wget " .. BASE .. "reactor-modem.lua reactor-modem.lua")
	shell.run("cp reactor-modem.lua startup.lua")
	print("")
	term.setTextColor(colors.lime)
	print("Modem Bridge installed!")
	term.setTextColor(colors.white)
	print("Attach a Wireless Modem and connect the reactor via Logic Adapter.")
	print("Reboot to start.")

else
	print("How is this computer connected to the reactor?")
	print("  [1] Cable  - Computer is cabled directly to the reactor")
	print("  [2] Wireless - Uses a Wireless Modem + a Modem Bridge PC")
	print("")

	local connType = ask("Choice (1/2): ", {"1", "2"})
	local isWireless = connType == "2"
	print("")

	print("Installing Display Computer...")
	shell.run("wget " .. BASE .. "functions.lua functions.lua")
	shell.run("wget " .. BASE .. "config.lua config.lua")
	shell.run("wget " .. BASE .. "reactor.lua reactor.lua")
	shell.run("cp reactor.lua startup.lua")

	if isWireless then
		setConfigValue("IS_WIRELESS", true)
	end

	print("")
	term.setTextColor(colors.lime)
	print("Display Computer installed!")
	term.setTextColor(colors.white)

	if isWireless then
		print("Wireless mode enabled. Make sure:")
		print("  - A Wireless Modem is attached to this computer")
		print("  - The Modem Bridge PC is running near the reactor")
		print("  - Both use the same MODEM_CHANNEL in config.lua (default: 42)")
	else
		print("Cable mode enabled. Make sure the Logic Adapter is connected.")
	end

	print("Reboot to start.")
end
