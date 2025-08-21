print("Installing Fusion Reactor...")

shell.run("wget https://raw.githubusercontent.com/MohammedMMC/FissionReactor-CC/refs/heads/main/functions.lua functions.lua")
shell.run("wget https://raw.githubusercontent.com/MohammedMMC/FissionReactor-CC/refs/heads/main/reactor.lua reactor.lua")

shell.run("cp reactor.lua startup.lua")

print("Installation complete! Reboot to start.")