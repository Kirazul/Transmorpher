# Transmorpher

Transmorpher is a full client-side appearance and morphing suite for World of Warcraft: Wrath of the Lich King 3.3.5a.

It goes far beyond a basic transmog browser. The addon can preview and morph gear, race, creature displays, mounts, companion pets, hunter pets, enchants, titles, spell visuals, shapeshift forms, barber appearances, item textures, persistent aura visuals, damage text colors, and selected world presentation settings from one UI, with optional peer-to-peer sync for other addon users.

![Transmorpher preview workflow](images/screenshot1.png)

## Highlights

- Full equipment transmogrification workflow with slot-based preview and direct apply.
- Creature and race morphing with saved favorites and direct display ID search.
- Mount, companion pet, and hunter pet morphing, including quick reset access.
- Enchant visual morphing for main-hand and off-hand weapons.
- Account-wide loadouts with talent spec bindings and auto-apply support.
- Form morph assignments for druid, shaman, warlock, priest, and DBW-style transformations.
- Direct spell morphing from your spellbook to other spell visuals.
- Conditional aura-triggered spell visual swapping with custom rules.
- Persistent aura visual browser to permanently wear spell visual effects.
- Full barbershop controls with per-region free-RGB tint, gradient, and rainbow recolor.
- Per-slot item recolor system with tint modes, color direction, and glow control.
- Damage text color customization with rainbow mode and global size slider.
- Search-heavy UI across items, sets, creatures, pets, titles, spells, and optimization lists.
- Optional world sync that shares visuals with other Transmorpher users without chat spam.
- Extra client-side controls for time, fog, far clip, render analysis, player culling, spell optimization, and HD font mode.

## What Transmorpher Covers

| Area | What you can do |
| --- | --- |
| Gear | Preview items by slot and armor/weapon subclass, apply hidden-slot looks, browse enchants, inspect item IDs, open Wowhead links, recolor item textures per slot with tint/glow/color controls. |
| Sets | Browse item sets by class, preview full outfits, inspect slot pieces around the dressing room model. |
| Character Morphs | Switch to any race model (male/female), apply creature display IDs, resize your character (0.1x-10.0x), save favorite morphs with undo support. |
| Mounts | Search by name, type, or display ID, apply universal/ground/flying mount morph, hide the mount model, or reset it. |
| Pets | Search and morph companion pets with quick apply and reset support. |
| Combat Pets | Morph hunter pets from a curated family list or all-creatures browser, direct display ID entry and scaling. Includes warlock demons and water elemental. |
| Enchants | Browse and apply main-hand and off-hand enchant visuals from the preview workflow. |
| Titles | Search and apply character titles from a dedicated picker. |
| Forms | Assign display IDs to 13 form groups: Bear, Cat, Moonkin, Tree, Travel, Aquatic, Flight, Ghost Wolf, Metamorphosis, Shadowform, and DBW proc forms. |
| Spell Visuals | Remap any spellbook spell to another spell visual, persisted per character. |
| Aura Spell Swaps | Create conditional rules that auto-swap spell visuals when specific auras are active. |
| Persistent Aura Visuals | Browse and wear spell visual effects permanently, surviving morphs, forms, zoning, and relogs. |
| Barber Controls | Adjust skin tone, face, hair style, hair color, facial hair with free-RGB texture recolor, gradient, rainbow, and two-tone tint modes per region. |
| Item Recoloring | Re-skin transmogged items per slot with another item's texture. Control tint mode, color direction, contrast, brightness, saturation, hue, and glow intensity. |
| World Presentation | Adjust time of day (0-24h), fog (toggle, color, start/end), far clip distance, and 28 render analysis toggles. |
| Damage Text Colors | Customize world text colors for damage, healing, crit, miss, absorb, XP, and honor. Rainbow gradient mode and global text size slider. |
| Sync | Share your current state with other addon users through optional P2P world sync. |
| Optimization | Suppress spell visuals/sounds per category, protect raid spells per tier (T7-T10, VOA), cull players/pets/NPCs at distance, hide nameplates and chat bubbles, mute other players' sounds. |
| HD Font | Queue MSDF font rendering for the next client launch. |

## Tab Guide

### Main Tabs

| Tab | Purpose |
| --- | --- |
| `Preview` | Main browsing and preview hub for items, sets, forms, spells, and enchants. |
| `Loadouts` | Save, preview, overwrite, delete, and apply full appearance presets with talent spec binding and auto-apply. |
| `Mounts` | Searchable mount morph browser with ground/flying/both filter, set, hide, and reset actions. |
| `Pets` | Searchable companion pet morph browser. |
| `CPets` | Hunter pet and creature-display browser with scaling support and dual curated/all mode. |
| `Morph` | Race morph buttons, custom creature search, size controls, favorites, and recent morphs. |
| `Color` | Damage text color customization with per-category pickers, rainbow mode, and size slider. |
| `Misc` | Environment, atmosphere, distance culling, render analysis, titles, HD font, and optimization controls. |
| `Settings` | Persistence, behavior, sync, interface toggles, and system status. |

### Preview Sub-Tabs

| Sub-Tab | Purpose |
| --- | --- |
| `Items` | Browse item appearances by slot and subclass, search by item name or ID, and preview on the dressing room model. |
| `Sets` | Browse class-filtered item sets, inspect each piece, and preview the full set. |
| `Forms` | Assign creature display IDs to supported shapeshift and transformation groups. |
| `Spells` | Pick a spell from your spellbook and assign it a different spell visual. |

### Misc Sub-Panels

| Sub-Panel | Purpose |
| --- | --- |
| `Environment` | Set client-side world time, fog, and far clip values. |
| `Analysis` | Toggle 28 render and analysis flags such as terrain, M2, WMO, shadows, wireframe, normals, clutter, and related debug views. |
| `Distance Culling` | Hide players/pets/NPCs/objects at distance, toggle shadows, nameplates, chat bubbles, and mute other players' sounds. |
| `Titles` | Search and apply titles. |
| `HD Font` | Queue MSDF font rendering for the next client launch. |
| `Optimization` | Suppress spell visuals and sounds, protect important raid spell sets per tier, and manage the protected spell list. |

### Other Tabs

| Tab | Access |
| --- | --- |
| `Barber` | Accessed through the dressing room or gear workflow. Full barbershop controls and per-region free-RGB tinting. |
| `Skin` | Accessed per equipment slot. Per-slot item recolor system with tint modes, color direction, and glow. |
| `Visuals` | Accessed through spell/aura workflows. Persistent aura visual browser and active set management. |
| `Aura Swap` | Accessed through spell workflows. Conditional aura-triggered spell visual swap rule editor. |

## Loadouts

Loadouts are one of the biggest features in the addon. A loadout can include:

- Equipment appearance and hidden-slot state.
- Weapon enchant visuals.
- Mount, companion pet, and combat pet morphs.
- Character morph and scale.
- Active title.

You can also:

- Preview a saved loadout before applying it.
- Overwrite an existing loadout.
- Delete old loadouts.
- Bind a loadout to Primary or Secondary talent spec.
- Auto-apply bound loadouts when you switch specs.
- Export and import loadouts as portable TM1 strings.

## Controls And Shortcuts

| Action | Result |
| --- | --- |
| Left-click an equipment slot | Select the slot and jump to matching item previews. |
| Alt + Left-click an item slot | Apply the currently previewed item morph to that slot. |
| Right-click an equipment slot | Remove or reset the slot morph. |
| Shift + Left-click an item slot | Print the item link and item ID to chat. |
| Ctrl + Left-click an item slot | Open a Wowhead URL dialog for the item. |
| Left-click an enchant slot | Enter enchant browsing mode in Preview. |
| Alt + Left-click an enchant slot | Apply the selected enchant visual. |
| Right-click an enchant slot | Remove the enchant morph. |
| Left-click an eye icon on a slot | Toggle slot item visibility (hide/show). |
| Left-click a sheathe icon on a weapon slot | Set sheathe position (Back/Hip/Hidden/Default). |
| Left-click a special slot under the model | Open the related tab. |
| Right-click a special slot | Clear the current mount, pet, combat pet, or character morph. |
| Left-click minimap button | Toggle the main window. |
| Right-drag character info button | Reposition the character-frame launcher. |

## Slash Commands

| Command | Description |
| --- | --- |
| `/morph` | Toggle the Transmorpher window. |
| `/morph reset` | Reset all active morphs. |
| `/morph status` | Show DLL and current morph status. |
| `/morph morph <displayID>` | Morph your character to a creature or race display ID. |
| `/morph scale <value>` | Set character scale. Use `0` for default. |
| `/morph mount <displayID>` | Morph your mount. |
| `/morph pet <displayID>` | Morph your companion pet. |
| `/morph hpet <displayID>` | Morph your hunter pet. |
| `/morph enchant <mh\|oh> <enchantID>` | Apply an enchant visual. |
| `/morph title <titleID>` | Apply a title. |
| `/morph sync` | Broadcast your current state to peers. |
| `/morph export` | Export a TM1 loadout string of your current state. |
| `/morph import <string>` | Import and apply a TM1 loadout string. |
| `/morph random` | Random creature morph. |
| `/morph target` | Morph into your target's appearance. |
| `/morph undo` | Undo the last character morph. |
| `/morph helm` | Toggle helm visibility. |
| `/morph cloak` | Toggle cloak visibility. |
| `/morph ss` | Take a screenshot. |
| `/morph fov <20-150>` | Set the camera field of view. |
| `/morph help` | Show command help. |

Aliases: `/vm` and `/Transmorpher`

## Multiplayer Sync

World sync is optional and can be toggled in `Settings`.

When enabled, Transmorpher can share your appearance state with other addon users nearby or connected through supported addon-message routes. The sync system is designed to be practical in real play:

- It discovers peers automatically.
- It re-broadcasts after state changes.
- It filters sync traffic out of visible chat.
- It handles large state payloads safely.
- It keeps your own morphs active even if you disable remote world sync.

This means sync is useful for shared social visuals, RP, events, or coordinated client-side appearance setups without polluting normal chat windows.

## Settings And Persistence

The addon supports both account-wide and per-character persistence.

### Account-level data

- Morph favorites.
- Global settings.
- Saved loadouts.
- Damage text color configurations.
- Window position and size.

### Character-level data

- Current active morph state.
- Per-character settings.
- Mount, pet, and combat pet state.
- Form and spell morph assignments.
- Aura swap rules.
- Persistent aura visual set.
- Barber shop state (skin, face, hair, facial hair).
- Item recolor state per slot.
- Sheathe positions and hidden slot states.

### Key settings exposed in the UI

- Persist morphs across sessions.
- Save mount, pet, and combat pet morphs per character.
- Keep morphs in shapeshift forms.
- Show Warlock Metamorphosis instead of suppressing it.
- Enable or disable world sync.
- Show or hide the minimap button.
- Show or hide the character info button.
- Queue HD MSDF font mode for next launch.

## Installation

1. Copy the `Transmorpher` addon folder into your WoW addons directory:

   `World of Warcraft/Interface/AddOns/Transmorpher`

2. Place `dinput8.dll` in your WoW root directory, next to `Wow.exe`.

3. If you use Universal Proxy instead of the bundled DLL loader, configure that instead.

4. Launch the client and use `/morph` to open the UI or click on interface button.

## Summary

Transmorpher is not just a transmog browser. It is a unified visual control panel for WotLK 3.3.5a that combines appearance morphing, spell visuals, form overrides, barber controls, item recolor, aura swaps, persistent visuals, damage text colors, loadouts, sync, and world-side client customization into a single addon workflow.
