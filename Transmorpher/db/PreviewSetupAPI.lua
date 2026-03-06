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
		if subclass:startswith("1H", "MH", "OH") then
			subclass = subclass:sub(4)
		end
		return previewSetup[version][raceFileName][sex][slot][subclass]
	end
end