local addon, ns = ...
local previewSetup = ns.previewSetup


function string:startswith(...)
    local array = {...}
    for i = 1, #array do
        assert(type(array[i]) == "string", "string:startswith(\"...\") - argument type error, string is required")
        if self:sub(1, array[i]:len()) == array[i] then
            return true
        end
    end
    return  false
end


function ns.GetPreviewSetup(version, raceFileName, sex, slot, subclass)
	assert(previewSetup[version] ~= nil, "'version' is mandatory and must be either 'classic' or 'modern'.")
	assert(type(raceFileName) == "string", "'raceFileName' is mandatory and must be string.")
	assert(type(sex) == "number", "'sex' is mandatory and must be int.")
	assert(type(slot) == "string", "'slot' is mandatory and must be string.")
	if previewSetup[version][raceFileName][sex][slot] == nil then
		return previewSetup[version][raceFileName][sex]["Armor"][slot]
	else
		assert(type(subclass) == "string", "'subclass' is mandatory and must be string.")
		local raceData = previewSetup[version][raceFileName][sex]

		-- Use the camera from the slot where TryOn actually RENDERS the weapon
		-- on the model, so the angle faces the correct side of the character.
		-- "1H Axe" → TryOn puts it in main hand → use Main Hand camera
		-- "OH Axe" → TryOn puts it in off-hand → use Off-hand camera
		-- "Shield" → TryOn puts it in off-hand → use Off-hand camera

		local lookupSubclass = subclass
		local renderSlot = slot  -- which slot TryOn renders to

		-- Map subclass → the slot where TryOn actually renders the weapon
		local offhandRender = {["Shield"]=true, ["Held in Off-hand"]=true}
		local rangedRender  = {["Bow"]=true, ["Crossbow"]=true, ["Gun"]=true, ["Wand"]=true, ["Thrown"]=true}

		if subclass:startswith("OH") then
			lookupSubclass = subclass:sub(4)
			renderSlot = "Off-hand"
		elseif subclass:startswith("MH") then
			lookupSubclass = subclass:sub(4)
			renderSlot = "Main Hand"
		elseif subclass:startswith("1H") then
			lookupSubclass = subclass:sub(4)
			renderSlot = "Main Hand"  -- TryOn always puts 1H in main hand
		elseif offhandRender[subclass] then
			renderSlot = "Off-hand"
		elseif rangedRender[subclass] then
			renderSlot = "Ranged"
		else
			-- 2H Axe, 2H Mace, 2H Sword, Polearm, Staff → main hand
			renderSlot = "Main Hand"
		end

		-- 1. Try render slot with base type
		if raceData[renderSlot] and raceData[renderSlot][lookupSubclass] then
			return raceData[renderSlot][lookupSubclass]
		end
		-- 2. Try render slot with full subclass name
		if lookupSubclass ~= subclass and raceData[renderSlot] and raceData[renderSlot][subclass] then
			return raceData[renderSlot][subclass]
		end
		-- 3. Render slot doesn't have exact type — use a similar type from same slot
		local similarMap = {
			["2H Axe"] = "Axe", ["2H Mace"] = "Mace", ["2H Sword"] = "Sword",
			["Polearm"] = "Axe", ["Staff"] = "Sword",
		}
		local similar = similarMap[lookupSubclass] or similarMap[subclass]
		if similar and raceData[renderSlot] and raceData[renderSlot][similar] then
			return raceData[renderSlot][similar]
		end
		-- 4. Any camera from the render slot
		if raceData[renderSlot] then
			for _, setup in pairs(raceData[renderSlot]) do
				return setup
			end
		end
		-- 5. Ultimate fallback
		if raceData["Main Hand"] then
			for _, setup in pairs(raceData["Main Hand"]) do
				return setup
			end
		end
		return raceData[slot][lookupSubclass]
	end
end