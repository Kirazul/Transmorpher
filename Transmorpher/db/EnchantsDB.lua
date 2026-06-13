local addon, ns = ...

-- ============================================================================
-- Enchant Visual Database for WoW 3.3.5a (build 12340)
-- Contains all enchant IDs that produce visible weapon glow effects.
-- Extracted from SpellItemEnchantment.dbc — only entries with itemVisual > 0.
-- Format: ns.enchantDB[enchantID] = "Enchant Name"
-- ============================================================================

ns.enchantDB = {
    -- ===================== Classic Enchants =====================
    [803]  = "Fiery Weapon",
    [912]  = "Demonslaying",
    [1894] = "Icy Chill",
    [1898] = "Lifestealing",
    [1899] = "Unholy Weapon",
    [1900] = "Crusader",
    [2504] = "Deathfrost",
    [2568] = "Adamantite Weapon Chain",

    -- ===================== TBC Enchants =====================
    [2669] = "Sunfire",
    [2670] = "Soulfrost",
    [2671] = "Savagery",
    [2672] = "Greater Agility",
    [2673] = "Mongoose",
    [2674] = "Spellpower",
    [2675] = "Battlemaster",
    [3222] = "Executioner",
    [3225] = "Executioner",

    -- ===================== WotLK Enchants =====================
    [3239] = "Icebreaker",
    [3241] = "Lifeward",
    [3247] = "Titanium Weapon Chain",
    [3251] = "Giant Slayer",
    [3273] = "Deathfrost",
    [3368] = "Titanium Plating",
    [3369] = "Titanium Plating",
    [3370] = "Titanium Plating",

    -- Runeforging (Death Knight)
    [3365] = "Rune of the Stoneskin Gargoyle",
    [3366] = "Rune of Swordbreaking",
    [3367] = "Rune of Swordbreaking",
    [3594] = "Rune of the Stoneskin Gargoyle",
    [3595] = "Rune of Swordbreaking",
    [3847] = "Rune of the Nerubian Carapace",
    [3883] = "Rune of the Nerubian Carapace",

    [3789] = "Berserking",
    [3790] = "Black Magic",
    [3833] = "Superior Potency",
    [3834] = "Mighty Spirit",
    [3844] = "Greater Savagery",
    [3845] = "Blade Ward",
    [3846] = "Blood Draining",
    [3869] = "Blade Ward",
    [3870] = "Blood Draining",

    -- Spell Power enchants with visuals
    [3830] = "Exceptional Spellpower",
    [3844] = "Greater Savagery",
    [3854] = "Greater Spellpower",
    [3855] = "Exceptional Agility",

    -- ===================== DK Runeforging (All) =====================
    [3323] = "Rune of Swordshattering",
    [3325] = "Rune of Lichbane",
    [3326] = "Rune of Razorice",
    [3345] = "Rune of the Fallen Crusader",
    [3347] = "Rune of Spellshattering",
    [3349] = "Rune of Cinderglacier",
    [3380] = "Rune of the Fallen Crusader",
    [3370] = "Rune of the Fallen Crusader",
    [3883] = "Rune of the Nerubian Carapace",

    -- ===================== Profession / Misc Enchants with Glow =====================
    [1103] = "Counterweight",
    [2523] = "Felsteel Spike",
    [3593] = "Titanium Spike",
    [3601] = "Titanium Spike",
    [3731] = "Titanium Shield Spike",
    [3748] = "Titanium Plating",

    -- ===================== Enchant Visuals (Extended) =====================
    -- These are additional enchant IDs confirmed to produce visible
    -- weapon glow effects on the 3.3.5a client.

    -- Agility enchants with glow
    [2564] = "Greater Agility",
    [2646] = "Greater Agility",
    [1593] = "Lesser Agility",
    [2567] = "Superior Agility",

    -- Strength / AP enchants with glow
    [3788] = "Accuracy",
    [3843] = "Exceptional Spirit",
    [3849] = "Titanguard",
    [3850] = "Major Stamina",

    -- Spirit / Intellect enchants with glow
    [3851] = "Mighty Spirit",
    [3853] = "Mighty Intellect",

    -- Additional visible enchants from SpellItemEnchantment
    [26]   = "Fiery Blaze Enchantment",
    [7]    = "Minor Beastslayer",
    [13]   = "Lesser Striking",
    [30]   = "Minor Striking",
    [36]   = "Striking",
    [241]  = "Lesser Intellect",
    [243]  = "Spirit",
    [249]  = "Intellect",
    [723]  = "Intellect",
    [803]  = "Fiery Weapon",
    [943]  = "Weapon Chain",
    [963]  = "Major Strength",
    [1606] = "Greater Striking",
    [1897] = "Strength",
    [1900] = "Crusader",
    [2443] = "Frost Oil",
    [2505] = "Shadow Oil",
    [2563] = "Greater Eternal Essence",
    [2666] = "Greater Agility",
    [2667] = "Major Healing",
    [2668] = "Major Striking",
    [2723] = "Khorium Scope",
    [3018] = "Stabilized Eternium Scope",
    [3607] = "Heartseeker Scope",
    [3608] = "Sun Scope",
    [3843] = "Exceptional Spirit",

    -- Popular PvP / raid enchants with particle effects
    [3231] = "Giant Slayer",
    [3232] = "Titanium Weapon Chain",
    [3241] = "Lifeward",
    [3239] = "Icebreaker",
    [3790] = "Black Magic",
    [3789] = "Berserking",
}

-- Build a sorted list for the UI (name + enchantID pairs)
ns.enchantSorted = {}
do
    local seen = {}
    for id, name in pairs(ns.enchantDB) do
        if not seen[id] then
            table.insert(ns.enchantSorted, { id = id, name = name, nameLower = name:lower() })
            seen[id] = true
        end
    end
    table.sort(ns.enchantSorted, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
end
