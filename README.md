# AltManager - Project Epoch Edition

**AltManager** is a lightweight, compact World of Warcraft addon designed specifically for the **Project Epoch** (3.3.5a architecture) private server. It aggregates dungeon/raid lockouts, daily activities, and profession cooldowns for all your characters into a clean, horizontal multi-character matrix.

<img width="227" height="280" alt="image" src="https://github.com/user-attachments/assets/4bd0cbe6-13b0-4038-95d7-bd2782d1b10a" />

## Features

### Standard Tasks
* **Onyxia's Lair (25-man)**
* **Molten Core (25-man)** 
* **Silithus Custom Daily Quest**
* **Daily Battleground Currency Token**

### Profession Cooldowns 
* **3-Day Matrix:** Leatherworking *Salt Shaker*, Alchemy *Transmute*, Tailoring *Mooncloth*.
* **7-Day Matrix (Project Epoch Custom Items):** Leatherworking *Masterwork Salt*, Alchemy *Crystal Lattice*, Tailoring *Signet of the Moonlit*.

<img width="297" height="223" alt="image" src="https://github.com/user-attachments/assets/c765bf8c-d092-4c35-becb-488fb776a36d" />


---

## Commands & Interactivity

| Command | Action |
| :--- | :--- |
| `/am` or `/altmanager` | Toggles the graphical overview overlay interface window. |
| `/am list` | Dumps registered roster strings directly to your chat frame. |
| `/am delete <number>` | Safely deletes an obsolete or removed character profile database path. |
| `/am minimap` | Toggles visibility of the standard minimap button frame anchor. |

* **Left-Click** cell elements or the minimap frame to instantly toggle the primary addon display grid.
* **Right-Click** the interface launchers to enter the Standard Blizzard Interface Addon Configuration submenu panels.

---

## Installation

1. Download the latest release package version from the repository.
2. Extract the archive contents into your custom World of Warcraft directory path:  
   `"/Interface/AddOns/`
3. Ensure the folder name matches exactly: `AltManager-Epoch`
4. Boot up the game and verify the addon is activated in your character select screen screen layout.

## Contribution & Troubleshooting

If you discover missing custom item IDs, broken localized daily indices, or database formatting exceptions while playing on Project Epoch:
1. Open a tracking item inside the **Issues** tab.
2. Provide your server-specific item IDs alongside the console logs thrown by your Lua environment interpreter.
