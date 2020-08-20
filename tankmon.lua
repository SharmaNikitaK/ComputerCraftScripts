--tankmon
--   Railcraft tank monitoring by Forgotten_Boy
--   	requires OpenPeripherals (OP) at least version 0.1.9, supports new liquid names in OP 0.2.1
-- 		with thanks to AmigaLink and Kalmor for the updated liquid names.
--   	Supports iron and steel Railcraft tanks and 15 common liquids.
--[[
 Setup:
 - Place an Advanced Computer with wireless modem and with tankmon on it adjacent to a tank valve.  Run "tankmon".
 - Setup another Advanced Computer with wireless modem and with tankmon on it adjacent to an advanced monitor.  Run "tankmon".
 - Your monitor should now show the contents of the tank.  Add as many tanks as you like and the server will simply add them to the display.
 - The size of the monitor or locations of the modems don't matter, place them anywhere on the computer.  The monitor can be resized while tankmon is running.
 
 Advanced usage:
 - On the client, you can use tankmon to trigger a redstone signal when the tank reaches a certain threshold (specified as 0 to 100, a percentage).  For example:
 tankmon 100 left
 tankmon 0 top
 The first example will send redstone output on the left when the tank is full.  The second example will send redstone output on the top when the tank is empty.
--]]

-- Variable definitions
local valve, monitor, screenw, screenh
local serverID = nil
local clients = {}
local args = {...}
local redlimit, redside, on
local sides = {"left", "right", "top", "bottom", "front", "back"};

----------------------------------------------------
-- Function definitions
----------------------------------------------------
local liquidColors = {{"Water", colors.blue },
					{"tile.oilStill", colors.gray, "Oil"},
					{"Creosote Oil", colors.brown},
					{"Essence", colors.lime},
					{"Steam", colors.lightGray},
					{"Honey", colors.yellow},
					{"Ethanol", colors.orange},
					{"Lava", colors.orange},
					{"item.fuel", colors.yellow, "Fuel"},
					{"Biomass", colors.green},
					{"Fortron", colors.lightBlue},
					{"Sludge", colors.black},
					{"Liquid DNA", colors.magenta},
					{"Fruit Juice", colors.green},
					{"Seed Oil", colors.yellow},
					{"Liquid Force", colors.yellow},
					{"Oil", colors.gray, "Oil"},
					{"Fuel", colors.yellow, "Fuel"},
					{"uumatter", colors.purple, "UUMatter"},
					{"vegetable", colors.magenta, "Veg"},
					{"deuterium", colors.lightBlue, "Deuterium"},
--liquid names for OpenPeripherals 0.2.1 by AmigaLink
                                        {"creosote", colors.brown, "Creosote Oil"},
                                        {"essence", colors.lime, "Essence"},
                                        {"steam", colors.lightGray, "Steam"},
                                        {"honey", colors.yellow, "Honey"},
                                        {"bioethanol", colors.orange, "Ethanol"},
                                        {"lava", colors.orange, "Lava"},
                                        {"biomass", colors.green, "Biomass"},
                                        {"fortron", colors.lightBlue, "Fortron"},
                                        {"sludge", colors.black, "Sludge"},
                                        {"liquiddna", colors.magenta, "Liquid DNA"},
                                        {"fruitjuice", colors.green, "Fruit Juice"},
                                        {"seedoil", colors.yellow, "Seed Oil"},
                                        {"xpjuice", colors.lime, "XP Juice"},
                                        {"liquidforce", colors.yellow, "Liquid Force"},
                                        {"oil", colors.gray, "Oil"},
                                        {"fuel", colors.yellow, "Fuel"},
                                        {"milk", colors.white, "Milk"},
-- Life Essence suggested by Fyrhtu
					{"life essence", colors.red, "Life Essence"}
                }

local function getLiquidColor(liquid)
  for c, color in pairs (liquidColors) do
	if (liquid == color[1]) then
		return color[2],color[3] or liquid
	end
  end
  return colors.white, liquid;
end

local function getDeviceSide(deviceType)
	for i,side in pairs(sides) do
		if (peripheral.isPresent(side)) then
			if (peripheral.getType(side)) == string.lower(deviceType) then
				return side;
			end
		end
	end
end

local function showLevel(count,max,filled,color,label, amt, threshold, signal)
	local screenw, screenh = monitor.getSize()
	max = max + 1
	if (not screenw) then
		return nil;
		-- monitor has been broken
	end
	
    local starty = screenh -  math.floor((screenh * filled))
    local width  = math.ceil(screenw / max + .5)
    local offset = math.ceil(width * (count - 1))
	local amtw = string.len(amt)
	local thresholdy = (threshold and ( screenh - ((threshold / 100) * screenh)))
	
	if (count == max) then
	--  the final column should use up the remaining space.  A hack!
		width = screenw - offset
	end
	--truncate the label to the width of the bar.
	label = string.sub(label, 1, math.max((width - 1), 0))

	if (thresholdy and thresholdy < 1) then
		thresholdy = 1
	else
		if (thresholdy and thresholdy > screenh) then
			thresholdy = screenh
		end
	end

    term.redirect(monitor)
    for c=starty, screenh + 1, 1 do
        for line=0, width, 1 do
			paintutils.drawPixel(line + offset, c, color)
        end
    end
	if (thresholdy) then
		local thresholdColor = color
		for line=0, width, 1 do
			thresholdColor = color
			if (signal) then
				thresholdColor = colors.red
			else
				-- makes a dotted line when there is no redstone signal
				if (line % 2 == 0) then
					thresholdColor = colors.red
				end
			end
			paintutils.drawPixel(line + offset, thresholdy, thresholdColor)
        end
	end

	monitor.setBackgroundColor(color)
	if (color == colors.white) then
		monitor.setTextColor(colors.black)
	end
	
	labely = math.min((starty + 1), screenh - 1)
	monitor.setCursorPos(offset + 1, labely)
	write(label)
	
	if (amtw <= width) then
		amty = math.min(labely + 1, screenh)
		monitor.setCursorPos(offset + 1, amty)
		write(amt)
	end
	monitor.setTextColor(colors.white)
--    term.restore()
end

local function tankStats(tank)
	if(tank) then
		local amt = tank["contents"]["amount"]
		local size = tank["capacity"]
		local filled = (amt and 1 / (size / amt)) or 0
		return amt, size, filled
	else
		return nil;
	end
end

local function tableCount(t)
	local total=0
	for k,v in pairs (t) do
		total = total + 1
	end
	return total
end

local function updateDisplay()
	local total = tableCount(clients)
	local count = 1

	monitor.setBackgroundColor(colors.black)
	monitor.setTextScale(.5)
	monitor.clear()
  
	for ix,client in pairs (clients) do
		local tank = client[1]
		local threshold = client[2]
		local signalOn = client[3]
		local amt,size,filled = tankStats(tank)
		local kind = tank["contents"]["name"]
		local color,name = getLiquidColor(kind)
		local unit = ""
		local amount = math.max(amt or 0, 0)

		if (amount > 1000000) then
			unit="M"
			amount=string.format("%.2f", math.floor(amt / 1000) / 1000)
		else
			if(amount > 0) then
			  unit="K"
			  amount=string.format("%.2f", amt / 1000)
			else
			  amount = ""
			end
		end
		amount = amount..unit
		showLevel(count, total, filled, color, name or "Empty", amount, threshold, signalOn)
		count = count + 1    
	end
	return nil;
end

local function broadcast ()
	term.clear()
	term.setCursorPos(1,1)
	print("_____________ tankmon Server started __________")
	print("Broadcasting that tank display is available...")
	print("Hold Ctrl+T to Terminate.")
	while true do
		rednet.broadcast(os.getComputerID())
		term.setCursorPos(1, 5)
		term.clearLine()
		write("Connected tankmon clients: " .. tostring(tableCount(clients)))
		sleep(7)
	end
end

local function receive()
  while true do
    local senderID, message, distance = rednet.receive()
    if (message) then
		local data = textutils.unserialize(message)
		clients[senderID] = data
    end
  end
end

local function display()
	while true do
		updateDisplay()
		sleep(1.5)
	end
end

local function connect()
	print("Looking for a tankmon server in wireless Rednet range...")
	while true do
		local senderID, message, distance = rednet.receive()
		serverID = senderID
		print("Connected to server " .. tostring(serverID))
		sleep(3)
  end  
end

local function publishTank()
    while true do
        if serverID then
			term.clear()
			term.setCursorPos(1,1)
            print("** Sending out tank information **")
            local tank = valve.getTankInfo()[1]
			-- establish whether redstone signal should be sent
			local amt,size,pctFilled = tankStats(tank)
			on = false
			local filled = pctFilled * 100
			if (filled and redlimit and redlimit==0 and filled==0) then
				on = true
			else
				if(filled and redlimit and filled <= redlimit) then
					on=true
				end
			end
			if(redside) then
				rs.setOutput(redside, on)
			end
			-- use rednet to update the server with this tank's info.
			local info = {tank, redlimit, on}
			if (redlimit and redside) then
				print("Redstone threshold: " .. tostring(redlimit))
				print("Redstone output side: " .. redside)
				print("Redstone signal on: " .. tostring(on))
				print("")
			end
			term.clearLine()
			write("** Tank contains: " .. tostring(amt))
            rednet.send(serverID, textutils.serialize(info), false)		
		end
		sleep(math.random(1,5))
    end
end

---------------------------------------
--the Main
---------------------------------------
local modemSide = getDeviceSide("modem");

if (modemSide) then
    local modem = peripheral.wrap(modemSide)
else
    error("A wireless modem must be attached to this computer.")
end

local tankSide = getDeviceSide("iron_tank_valve");
local tankSide2 = getDeviceSide("steel_tank_valve");
local tankSide3 = getDeviceSide("rcsteeltankvalvetile");
local tankSide4 = getDeviceSide("rcirontankvalvetile");
local finalside = tankSide or tankSide2 or tankSide3 or tankSide4
local screenSide = getDeviceSide("monitor");

if (finalside and screenSide) then
    error("Either a screen or a tank valve can be connected, not both.")
end

if finalside  then
    valve = peripheral.wrap(finalside )
end

if (screenSide) then
    monitor = peripheral.wrap(screenSide)
	if(not monitor.isColor()) then
		error("The attached monitor must be Advanced.  Get some gold!")
	end
    screenw, screenh = monitor.getSize()
    monitor.clear()
end

rednet.open(modemSide)
if (valve) then
    -- client mode
	redlimit = args[1]
	redside = args[2]
	if (redlimit and not redside) then
		print("A threshold and redstone side must both be present.")
		print("e.g. tankmon 100 top")
		error()
	end
	if (redlimit) then
		redlimit = tonumber(redlimit)
		print("")
		print("Tank will send redstone signal at or below " .. tostring(redlimit) .. "% on side " .. redside)
	end
	-- clear outstanding redstone signals.
	for i,side in pairs(sides) do
		rs.setOutput(side, false)
	end
    parallel.waitForAll(connect, publishTank)
else
    -- server mode
    parallel.waitForAll(broadcast, receive, display)
end
rednet.close(modemSide)