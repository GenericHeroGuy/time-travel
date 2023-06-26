local VERSION = 1

-- avoid redefiniton on updates
if timetravel.VERSION == nil or timetravel.VERSION < VERSION then

-- TIME TRAVEL
local FRACUNIT = FRACUNIT
local TICRATE = TICRATE
local RING_DIST = RING_DIST
local KITEM_THUNDERSHIELD = KITEM_THUNDERSHIELD
local sfx_kc50 = sfx_kc50

timetravel.teleportCooldown = TICRATE
local starttime = 6*TICRATE + 3*TICRATE/4
timetravel.introTP1tic = TICRATE+2
timetravel.introTP2tic = (TICRATE*3)+2

timetravel.isActive = false
timetravel.localXdist = 0
timetravel.localYdist = 0
timetravel.hasBackrooms = false
timetravel.backroomsX = 0
timetravel.backroomsY = 0
timetravel.backroomsZ = 0

timetravel.hookFuncs = {}

freeslot("sfx_ttshif", "sfx_ttshit", "sfx_ttfail", "sfx_ttfrag", "sfx_cdpast", "sfx_cdfutr")

sfxinfo[sfx_ttshif] = {
	singular = false,
	priority = 64,
	flags = 0
}

sfxinfo[sfx_ttshit] = {
	singular = false,
	priority = 64,
	flags = 0
}

timetravel.determineTimeWarpPosition = function(mo)
	local xOffset = 0
	local yOffset = 0

	if mo.timetravel and mo.timetravel.isTimeWarped then
		xOffset = $ - timetravel.localXdist
		yOffset = $ - timetravel.localYdist
	else
		xOffset = $ + timetravel.localXdist
		yOffset = $ + timetravel.localYdist
	end

	return xOffset, yOffset
end

timetravel.changePositions = function(mo, dontrunextralogic)
	local xOffset, yOffset = timetravel.determineTimeWarpPosition(mo)
	local finalX = mo.x + xOffset
	local finalY = mo.y + yOffset

	P_SetOrigin(mo, finalX, finalY, mo.z)
	
	if mo.timetravel.isTimeWarped == nil then
		mo.timetravel.isTimeWarped = false
	end
	mo.timetravel.isTimeWarped = not $
	
	if dontrunextralogic then return end
	
	if mo.linkedItem and mo.linkedItem.valid and mo.linkedItem.type == MT_ECHOGHOST then
		mo.linkedItem.justEchoTeleported = true
	end
	
	if mo.z < mo.floorz then
		-- print(abs(mo.floorz - mo.z)>>FRACBITS + " | " + ((mo.height * 3) >>FRACBITS))
		if abs(mo.floorz - mo.z) > mo.height then
			if timetravel.hasBackrooms and P_RandomChance(FRACUNIT/100) then
				P_SetOrigin(mo, timetravel.backroomsX, timetravel.backroomsY, timetravel.backroomsZ)
				
				-- Transform momentum to where the mo is looking
				local thrustForce = R_PointToDist2(0, 0, mo.momx, mo.momy)
				mo.momx = FixedMul(thrustForce, cos(mo.angle))
				mo.momy = FixedMul(thrustForce, sin(mo.angle))
				
				if mo.player then S_StopMusic(mo.player) end
			else
				S_StartSound(mo, sfx_ttfrag)
				if mo.linkedItem then S_StartSound(mo.linkedItem, sfx_ttfrag) end
				P_DamageMobj(mo, nil, nil, 10000) -- DEATH.
			end
		end
	end
end

timetravel.teleport = function(mo, dontrunhooks)
	if not dontrunhooks then
		local result = timetravel.runHooks(mo)
		if result == false then return result end
	end

	local player = mo.player
	if player then
		local localDisplayPlayer = timetravel.isDisplayPlayer(player) 
		if localDisplayPlayer > -1 then player.timetravelconsts.TWFlash = 5 end
		mo.timetravel.teleportCooldown = timetravel.teleportCooldown
	end
	
	timetravel.changePositions(mo)
	S_StartSound(mo, sfx_ttshif)
	
	-- Stuff in the mo's hnext list will also time travel.
	local moHnext = mo.hnext
	while moHnext ~= nil do
		if moHnext.timetravel then timetravel.changePositions(moHnext) end
		moHnext = moHnext.hnext
	end
	
	if consoleplayer and player and timetravel.isDisplayPlayer(player) ~= -1 and not player.exiting then
		COM_BufInsertText(consoleplayer, "resetcamera")
	end
	
	return true
end

timetravel.addTimeTravelHook = function(func)
	table.insert(timetravel.hookFuncs, func)
end

timetravel.runHooks = function(mo)

	local result = nil
	for _, v in ipairs(timetravel.hookFuncs) do
		-- Don't let people's awful code break teleporting, please.
		local ran, errorMsg = pcall(function() result = v(mo) end)
		
		if not ran then
			print(errorMsg)
			continue
		end
	end
	return result

end

timetravel.handleThunderShieldZap = function(player)
	if player.mo == nil or not player.mo.valid then return end
	
	local mobj = player.mo
	local thunderradius = RING_DIST/4
	
	searchBlockmap("objects", function(refmobj, foundmobj)
		if FixedHypot(FixedHypot(refmobj.x - foundmobj.x, refmobj.y - foundmobj.y),
			refmobj.z - foundmobj.z) > thunderradius then return nil end -- In radius?
		
		if not foundmobj.timetravel then return nil end
		if foundmobj == mobj then return end
		
		timetravel.teleport(foundmobj)
		
	end, mobj.linkedItem, 	mobj.linkedItem.x - thunderradius, mobj.linkedItem.x + thunderradius,
							mobj.linkedItem.y - thunderradius, mobj.linkedItem.y + thunderradius)
end

addHook("PreThinkFrame", function() -- Init
	if timetravel.VERSION > VERSION then return end
	if leveltime ~= 2 then return end
	
	if not timetravel.isActive then return end
	
	for player in players.iterate do
		if player.mo and player.mo.valid then
			player.mo.timetravel = {}
			player.mo.timetravel.isTimeWarped = false
		end
		player.timetravelconsts = {}
	end
end)

addHook("PreThinkFrame", function() -- Input Handler
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end
	if leveltime < starttime then return end

	for player in players.iterate do
		if not (player.mo and player.mo.valid) or player.timetravelconsts == nil then continue end
	
		if player.cmd.buttons & BT_ATTACK and not player.timetravelconsts.holdingItemButton then
			if not timetravel.isInDamageState(player) and not timetravel.canUseItem(player) and 
				(player.mo.timetravel.teleportCooldown == nil or player.mo.timetravel.teleportCooldown <= 0) then
				timetravel.teleport(player.mo)
			elseif not timetravel.isInDamageState(player) and timetravel.canUseItem(player) and
				player.kartstuff[k_respawn] == 0 and player.kartstuff[k_itemtype] == KITEM_THUNDERSHIELD then
				timetravel.handleThunderShieldZap(player)
			elseif not timetravel.canUseItem(player) and player.kartstuff[k_eggmanheld] == 0 then -- INCORRECTLY LOUD BUZZER
				S_StartSound(nil, sfx_ttfail, player)
			end
			
			player.timetravelconsts.holdingItemButton = true
		elseif not (player.cmd.buttons & BT_ATTACK) and player.timetravelconsts.holdingItemButton then
			player.timetravelconsts.holdingItemButton = false
		end
	end
end)

addHook("PreThinkFrame", function() -- Intro
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end
	if leveltime > timetravel.introTP2tic then return end
	
	for player in players.iterate do
		if player.spectator and player.mo == nil or not player.mo.valid then continue end
		if leveltime == timetravel.introTP1tic or leveltime == timetravel.introTP2tic then timetravel.teleport(player.mo) end
	end
end)

addHook("PostThinkFrame", function() -- Cooldown Handler
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end

	for player in players.iterate do
		if player.mo and player.mo.valid and player.mo.timetravel then
			player.mo.timetravel.teleportCooldown = $ or 0
			
			if player.mo.timetravel.teleportCooldown > 0 then
				player.mo.timetravel.teleportCooldown = $ - 1
			
				if player.mo.timetravel.teleportCooldown == 0 then
					S_StartSound(nil, sfx_kc50, player)
					
					local sfx = sfx_cdpast
					if player.mo.timetravel.isTimeWarped == true then
						sfx = sfx_cdfutr
					end
					
					S_StartSound(nil, sfx, player)
				end
			end
		end	
		
		if player.timetravelconsts then
			player.timetravelconsts.TWFlash = $ or 0
			if player.timetravelconsts.TWFlash > 0 then
				player.timetravelconsts.TWFlash = $ - 1
			end
		end
	end

end)

local thunderShieldBehaviour = function(player, inflictor, source)
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end

	if player.kartstuff[k_itemtype] == KITEM_THUNDERSHIELD then
		timetravel.handleThunderShieldZap(player)
	end
end
addHook("ShouldSpin", thunderShieldBehaviour)
addHook("ShouldExplode", thunderShieldBehaviour)
addHook("ShouldSquish", thunderShieldBehaviour)

addHook("ThinkFrame", function() -- Starpost/Timewarp status link
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end

	for player in players.iterate do
		if player.timetravelconsts == nil then continue end
		if player.spectator then
			player.timetravelconsts.starpostStatus = false
			player.timetravelconsts.starpostNumOld = 0
			continue
		end
		
		if player.starpostnum ~= player.timetravelconsts.starpostNumOld then
			if player.starpostnum == 0 then
				player.timetravelconsts.starpostStatus = false
			else
				player.timetravelconsts.starpostStatus = player.mo.timetravel.isTimeWarped
			end
		end

		player.timetravelconsts.starpostNumOld = player.starpostnum
	end

end, MT_PLAYER)

addHook("PlayerSpawn", function(player) -- Restore time warp status to mo.
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end
	if not (player.mo and player.mo.valid) then return end
	
	if player.timetravelconsts == nil then
		player.timetravelconsts = {}
	end
	
	player.mo.timetravel = {}
	player.mo.timetravel.isTimeWarped = player.timetravelconsts.starpostStatus or false
end)

-- Prevent latpoints from utterly breaking the gimmick.
addHook("MobjDeath", function(target)
	if timetravel.VERSION > VERSION then return end
	if not timetravel.isActive then return end
	
	if not (target and target.player and not target.player.spectator) then return end
	if target.player.kmp_respawn then target.player.kmp_respawn = nil end
end, MT_PLAYER)

addHook("MapChange", function(mapnum)
	if timetravel.VERSION > VERSION then return end
	
	if timetravel.isActive == true then -- cleanup
		for player in players.iterate do
			player.timetravelconsts = nil
		end
	end
	
	timetravel.isActive = false
	timetravel.localXdist = 0
	timetravel.localYdist = 0
	timetravel.hasBackrooms = false
	timetravel.backroomsX = 0
	timetravel.backroomsY = 0
	timetravel.backroomsZ = 0
	
	local XYOffsets = timetravel.turnCommaDelimitedStringIntoTable(mapheaderinfo[mapnum]["tt_2ndmapxyoffset"])
	local XYBackrooms = timetravel.turnCommaDelimitedStringIntoTable(mapheaderinfo[mapnum]["tt_backroomspos"])
	-- print(XYOffsets)
		
	if #XYOffsets >= 2 then
		timetravel.localXdist = tonumber(XYOffsets[1]) << FRACBITS
		timetravel.localYdist = tonumber(XYOffsets[2]) << FRACBITS
	end
	
	if #XYBackrooms >= 3 then
		timetravel.hasBackrooms = true
		timetravel.backroomsX = tonumber(XYBackrooms[1]) << FRACBITS
		timetravel.backroomsY = tonumber(XYBackrooms[2]) << FRACBITS
		timetravel.backroomsZ = tonumber(XYBackrooms[3]) << FRACBITS
	end
	
	if timetravel.localXdist ~= 0 or timetravel.localYdist ~= 0 then
		timetravel.isActive = true
	end
end)

addHook("NetVars", function(network)
	if timetravel.VERSION > VERSION then return end
	
	timetravel.isActive = network($)
	timetravel.localXdist = network($)
	timetravel.localYdist = network($)
	timetravel.hasBackrooms = network($)
	timetravel.backroomsX = network($)
	timetravel.backroomsY = network($)
	timetravel.backroomsZ = network($)
end)

timetravel.VERSION = VERSION

end