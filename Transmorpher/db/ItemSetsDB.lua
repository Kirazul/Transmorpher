local addon, ns = ...

-- Parse itemsets.txt and create a structured database
-- Format: SetName(Description):slot@itemId:slot@itemId:...

ns.itemSetsDB = {}
ns.itemSetsByClass = {}

-- Slot name mapping from itemsets.txt to addon slot names
local slotMapping = {
    hands = "Hands",
    head = "Head",
    legs = "Legs",
    shoulders = "Shoulder",
    chest = "Chest",
    bracers = "Wrist",
    belt = "Waist",
    boots = "Feet",
    back = "Back",
    tabard = "Tabard",
    shirt = "Shirt"
}

-- Class name extraction from set descriptions
local classKeywords = {
    Priest = "Priest",
    Rogue = "Rogue",
    Druid = "Druid",
    Hunter = "Hunter",
    Mage = "Mage",
    Paladin = "Paladin",
    Shaman = "Shaman",
    Warlock = "Warlock",
    Warrior = "Warrior",
    ["Death Knight"] = "DEATHKNIGHT"
}


-- Parse a single set line from itemsets.txt
local function ParseSetLine(line)
    -- Skip comments and empty lines
    if line:match("^%s*%-%-") or line:match("^%s*$") then
        return nil
    end
    
    -- Extract set name and description
    local setName, description, itemsStr = line:match("^([^%(]+)%(([^%)]+)%)%:(.+)$")
    if not setName or not description or not itemsStr then
        return nil
    end
    
    setName = setName:gsub("^%s+", ""):gsub("%s+$", "")
    description = description:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Parse items
    local items = {}
    for slotItem in itemsStr:gmatch("([^:]+)") do
        local slot, itemIds = slotItem:match("([^@]+)@(.+)")
        if slot and itemIds then
            slot = slot:gsub("^%s+", ""):gsub("%s+$", "")
            local mappedSlot = slotMapping[slot:lower()]
            if mappedSlot then
                -- Handle multiple item IDs separated by &
                for itemId in itemIds:gmatch("([^&]+)") do
                    itemId = tonumber(itemId)
                    if itemId then
                        table.insert(items, {slot = mappedSlot, itemId = itemId})
                    end
                end
            end
        end
    end
    
    if #items == 0 then
        return nil
    end
    
    return {
        name = setName,
        description = description,
        items = items
    }
end

-- Embedded sets data (parsed from itemsets.txt)
local rawSetsData = {
    {name="Devout", desc="Dungeon 1 Priest Set", class="PRIEST", items={{s="Hands",i=16692},{s="Head",i=16693},{s="Legs",i=16694},{s="Shoulder",i=16695},{s="Chest",i=16690},{s="Wrist",i=16697},{s="Waist",i=16696},{s="Feet",i=16691}}},
    {name="Virtuous", desc="Dungeon 2 Priest Set", class="PRIEST", items={{s="Hands",i=22081},{s="Head",i=22080},{s="Legs",i=22085},{s="Shoulder",i=22082},{s="Chest",i=22083},{s="Wrist",i=22079},{s="Waist",i=22078},{s="Feet",i=22084}}},
    {name="Prophecy", desc="Tier 1 Priest Raid Set", class="PRIEST", items={{s="Hands",i=16812},{s="Head",i=16813},{s="Legs",i=16814},{s="Shoulder",i=16816},{s="Chest",i=16815},{s="Wrist",i=16819},{s="Waist",i=16817},{s="Feet",i=16811}}},
    {name="Transcendence", desc="Tier 2 Priest Raid Set", class="PRIEST", items={{s="Hands",i=16920},{s="Head",i=16921},{s="Legs",i=16922},{s="Shoulder",i=16924},{s="Chest",i=16923},{s="Wrist",i=16926},{s="Waist",i=16925},{s="Feet",i=16919}}},
    {name="Oracle", desc="AQ40 Tier 2.5 Priest Raid Set", class="PRIEST", items={{s="Head",i=21348},{s="Legs",i=21352},{s="Shoulder",i=21350},{s="Chest",i=21351},{s="Feet",i=21349}}},
    {name="Faith", desc="Tier 3 Priest Raid Set", class="PRIEST", items={{s="Hands",i=22517},{s="Head",i=22514},{s="Legs",i=22513},{s="Shoulder",i=22515},{s="Chest",i=22512},{s="Wrist",i=22519},{s="Waist",i=22518},{s="Feet",i=22516}}},
    {name="Incarnate", desc="Tier 4 Priest Raid Set", class="PRIEST", items={{s="Hands",i=29055},{s="Head",i=29049},{s="Legs",i=29053},{s="Shoulder",i=29054},{s="Chest",i=29050}}},
    {name="Avatar", desc="Tier 5 Priest Raid Set", class="PRIEST", items={{s="Hands",i=30151},{s="Head",i=30152},{s="Legs",i=30153},{s="Shoulder",i=30154},{s="Chest",i=30150}}},
    {name="Absolution", desc="Tier 6 Priest Raid Set", class="PRIEST", items={{s="Hands",i=31061},{s="Head",i=31064},{s="Legs",i=31067},{s="Shoulder",i=31070},{s="Chest",i=31065},{s="Wrist",i=34434},{s="Waist",i=34528},{s="Feet",i=34563}}},
    {name="Valorous Ragalia", desc="Tier 7.5 Priest Raid Set", class="PRIEST", items={{s="Hands",i=40454},{s="Head",i=40456},{s="Legs",i=40457},{s="Shoulder",i=40459},{s="Chest",i=40458}}},
    {name="Shadowcraft", desc="Dungeon 1 Rogue Set", class="ROGUE", items={{s="Hands",i=16712},{s="Head",i=16707},{s="Legs",i=16709},{s="Shoulder",i=16708},{s="Chest",i=16721},{s="Wrist",i=16710},{s="Waist",i=16713},{s="Feet",i=16711}}},
    {name="Darkmantle", desc="Dungeon 2 Rogue Set", class="ROGUE", items={{s="Hands",i=22006},{s="Head",i=22005},{s="Legs",i=22007},{s="Shoulder",i=22008},{s="Chest",i=22009},{s="Wrist",i=22004},{s="Waist",i=22002},{s="Feet",i=22003}}},
    {name="Nightslayer", desc="Tier 1 Rogue Raid Set", class="ROGUE", items={{s="Hands",i=16826},{s="Head",i=16821},{s="Legs",i=16822},{s="Shoulder",i=16823},{s="Chest",i=16820},{s="Wrist",i=16825},{s="Waist",i=16827},{s="Feet",i=16824}}},
    {name="Bloodfang", desc="Tier 2 Rogue Raid Set", class="ROGUE", items={{s="Hands",i=16907},{s="Head",i=16908},{s="Legs",i=16909},{s="Shoulder",i=16832},{s="Chest",i=16905},{s="Wrist",i=16911},{s="Waist",i=16910},{s="Feet",i=16906}}},
    {name="Wildheart", desc="Dungeon 1 Druid Set", class="DRUID", items={{s="Hands",i=16717},{s="Head",i=16720},{s="Legs",i=16719},{s="Shoulder",i=16718},{s="Chest",i=16706},{s="Wrist",i=16714},{s="Waist",i=16716},{s="Feet",i=16715}}},
    {name="Feralheart", desc="Dungeon 2 Druid Set", class="DRUID", items={{s="Hands",i=22110},{s="Head",i=22109},{s="Legs",i=22111},{s="Shoulder",i=22112},{s="Chest",i=22113},{s="Wrist",i=22108},{s="Waist",i=22106},{s="Feet",i=22107}}},
    {name="Beaststalker", desc="Dungeon 1 Hunter Set", class="HUNTER", items={{s="Hands",i=16676},{s="Head",i=16677},{s="Legs",i=16678},{s="Shoulder",i=16679},{s="Chest",i=16674},{s="Wrist",i=16681},{s="Waist",i=16680},{s="Feet",i=16675}}},
    {name="Beastmaster", desc="Dungeon 2 Hunter Set", class="HUNTER", items={{s="Hands",i=22015},{s="Head",i=22013},{s="Legs",i=22017},{s="Shoulder",i=22016},{s="Chest",i=22060},{s="Wrist",i=22011},{s="Waist",i=22010},{s="Feet",i=22061}}},
    {name="Magister's Ragalia", desc="Dungeon 1 Mage Set", class="MAGE", items={{s="Hands",i=16684},{s="Head",i=16686},{s="Legs",i=16687},{s="Shoulder",i=16689},{s="Chest",i=16688},{s="Wrist",i=16683},{s="Waist",i=16685},{s="Feet",i=16682}}},
    {name="Sorcerer Ragalia", desc="Dungeon 2 Mage Set", class="MAGE", items={{s="Hands",i=22066},{s="Head",i=22065},{s="Legs",i=22067},{s="Shoulder",i=22068},{s="Chest",i=22069},{s="Wrist",i=22063},{s="Waist",i=22062},{s="Feet",i=22064}}},
    {name="Lightforge Armor", desc="Dungeon 1 Paladin Set", class="PALADIN", items={{s="Hands",i=16724},{s="Head",i=16727},{s="Legs",i=16728},{s="Shoulder",i=16729},{s="Chest",i=16726},{s="Wrist",i=16722},{s="Waist",i=16723},{s="Feet",i=16722}}},
    {name="Soulforge Armor", desc="Dungeon 2 Paladin Set", class="PALADIN", items={{s="Hands",i=22090},{s="Head",i=22091},{s="Legs",i=22092},{s="Shoulder",i=22093},{s="Chest",i=22089},{s="Wrist",i=22088},{s="Waist",i=22086},{s="Feet",i=22087}}},
    {name="The Elements", desc="Dungeon 1 Shaman Set", class="SHAMAN", items={{s="Hands",i=16672},{s="Head",i=16667},{s="Legs",i=16668},{s="Shoulder",i=16669},{s="Chest",i=16666},{s="Wrist",i=16671},{s="Waist",i=16673},{s="Feet",i=16670}}},
    {name="The Five Thunders", desc="Dungeon 2 Shaman Set", class="SHAMAN", items={{s="Hands",i=22099},{s="Head",i=22097},{s="Legs",i=22100},{s="Shoulder",i=22101},{s="Chest",i=22102},{s="Wrist",i=22095},{s="Waist",i=22098},{s="Feet",i=22096}}},
    {name="Dreadmist Raiment", desc="Dungeon 1 Warlock Set", class="WARLOCK", items={{s="Hands",i=16705},{s="Head",i=16698},{s="Legs",i=16699},{s="Shoulder",i=16701},{s="Chest",i=16700},{s="Wrist",i=16703},{s="Waist",i=16702},{s="Feet",i=16704}}},
    {name="Deathmist Raiment", desc="Dungeon 2 Warlock Set", class="WARLOCK", items={{s="Hands",i=22077},{s="Head",i=22074},{s="Legs",i=22072},{s="Shoulder",i=22073},{s="Chest",i=22075},{s="Wrist",i=22071},{s="Waist",i=22070},{s="Feet",i=22076}}},
    {name="Battlegear of Valor", desc="Dungeon 1 Warrior Set", class="WARRIOR", items={{s="Hands",i=16737},{s="Head",i=16731},{s="Legs",i=16732},{s="Shoulder",i=16733},{s="Chest",i=16730},{s="Wrist",i=16735},{s="Waist",i=16736},{s="Feet",i=16734}}},
    {name="Battlegear of Heroism", desc="Dungeon 2 Warrior Set", class="WARRIOR", items={{s="Hands",i=21998},{s="Head",i=21999},{s="Legs",i=22000},{s="Shoulder",i=22001},{s="Chest",i=21997},{s="Wrist",i=21996},{s="Waist",i=21994},{s="Feet",i=21995}}},
    {name="Valorous Scourgeborne", desc="Tier 7.5 Death Knight Raid Set", class="DEATHKNIGHT", items={{s="Hands",i=40552},{s="Head",i=40554},{s="Legs",i=40556},{s="Shoulder",i=40557},{s="Chest",i=40550}}},
}

-- Initialize the database
function ns.InitializeItemSetsDB()
    for _, rawSet in ipairs(rawSetsData) do
        local setData = {
            name = rawSet.name,
            description = rawSet.desc,
            items = {}
        }
        
        for _, item in ipairs(rawSet.items) do
            table.insert(setData.items, {slot = item.s, itemId = item.i})
        end
        
        table.insert(ns.itemSetsDB, setData)
        
        -- Categorize by class
        local className = rawSet.class
        if className then
            if not ns.itemSetsByClass[className] then
                ns.itemSetsByClass[className] = {}
            end
            table.insert(ns.itemSetsByClass[className], setData)
        end
    end
end
