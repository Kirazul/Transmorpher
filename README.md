# Transmorpher (3.3.5a)
![Transmorpher Screenshot](images/screenshot.png)

A high-performance **transmog addon and morpher** for World of Warcraft 3.3.5a (12340).

## What it does
Transmorpher is a powerful tool that gives you complete control over your character's visual appearance. It allows you to change how you look to yourself without affecting your actual gear, stats, or other players.

### Key Features:
- **Item Morphing**: Instantly change any armor or weapon slot to any item in the game database.
- **Character Morphing**: Morph into any race, gender, NPC, or legendary creature (Lich King, Illidan, etc.).
- **Visual Customization**: Adjust your character's scale and size.
- **Save System**: Create your favorite "Looks" and save them.
- **Automatic Loading**: Your transmogs and morphs are saved and will be **automatically loaded** every time you open the game.
- **Native UI**: Includes a modern interface and a "Transmog" button directly on your character frame.

## Installation
1. **DLL**: Place `dinput8.dll` in your WoW folder (next to `Wow.exe`).
2. **Addon**: Place the `Transmorpher` folder in your `Interface\AddOns\` directory.

## How to Use
- Open the interface with `/morph` or `/vm`.
- Use the **Transmog** button on your character frame.
- **Left-click** items to preview.
- **Alt + Left-click** slots to apply morphs.
- Use the **Morph** tab for race and scale changes.

## Releases
Check the [Releases](https://github.com/Kirazul/Transmorpher/releases) section for:
- Pre-compiled `dinput8.dll`.
- Ready-to-use `Transmorpher` Addon.
- Full Source Code.


## Changelog (1.0.2)
- **Weapon Transmog Overhaul**: Improved weapon transmog handling for both main-hand and off-hand slots.
- **Stealth & Combat Fix**: Fixed weapon transmogs being removed when stealthing/unstealthing, entering combat, or leaving combat.
- **Deathbringer's Will Fix**: Fixed Deathbringer's Will procs removing the morph.
- **Robust Morph Persistence**: Added a more robust system for handling transformations and teleportation to prevent morph resets.
- **Reduced Flickering**: Removed the majority of visual flickering during morph restoration.
- **Shapeshift Setting**: Added a setting to keep morph active while shapeshifted.
- **DBW Toggle**: Added an option to disable the Deathbringer's Will transformation while morphed.
- **Ranged Weapons Unrestricted**: Fixed ranged weapon restrictions — ranged weapons can now be used as melee appearances and vice versa.
- **Character Info Button**: Updated the Character Info button design.

## Changelog (1.0.1)
- **Updated IDs**: Corrected several incorrect `CreatureTemplate` IDs in the Popular Creatures list.
- **Weapon Refinement**: Removed all weapon slot restrictions. You can now transmogrify off-hand items to the main-hand and vice versa (Shields, Held-in-off-hand, etc.).
- **Persistence Fixes**: Resolved issues where morphs were removed after shapeshifts (Moonkin, Cat, Bear, Metamorphosis) or using portals/teleportation.
- **Stability**: Fixed a bug where saving an appearance set intermittently failed to store all transmog slots.

## Progress Note
**Race Morph Support**: This feature is currently in progress. We are developing a solution that works without game function hooks or memory patches, ensuring the system remains 100% client-safe.

*Educational purposes only.*

