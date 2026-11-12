# Project Specification: Offline D&D 5e Player Tracker (Flutter Desktop)

## 1. System Instructions for the AI Agent
You are an autonomous AI software engineer building a standalone **Flutter Desktop Application** (targeting Windows, macOS, and Linux). 
* **Zero Web/Network Access:** This application must be 100% offline. Do not include any HTTP requests, external APIs, cloud databases, or web-hosted fonts/assets. Use bundled or system fonts and standard Material Icons.
* **No Version Control Assumption:** The user is not using Git. Write modular, well-isolated code so that updates to one file do not break others. Implement safe file-writing practices (atomic writes / `.bak` fallback) when saving local JSON data so character files are never corrupted.
* **Single Active Character View:** The application tracks multiple characters via local JSON files, but displays **only one active character sheet at a time** on a unified, multi-column dashboard.
* **Instant Auto-Save:** Every state change (modifying stats, toggling proficiencies, changing HP, adding/editing items, spells, or notes) must automatically and debounced-save (e.g., 300ms delay) to the active character's local `.json` file.

---

## 2. Tech Stack & Allowed Dependencies
Keep external dependencies minimal and strictly local:
* **Framework:** Flutter (Material 3 Design, Dark Theme default with clean card separation).
* **`path_provider`:** To locate the local application documents directory for storing character JSON files (`<Documents>/DnDPlayerTracker/characters/`).
* **`file_picker`:** For the "Import Character (.json)" and "Export Character (.json)" native desktop file dialogs.
* **`uuid`:** (Optional) For generating unique IDs for characters, items, spells, and notes (or use timestamp-based unique strings).

---

## 3. Data Architecture & JSON Schema
One character equals **one self-contained `.json` file**. This exact structure is used both for internal auto-saving in the app's workspace folder and for exporting/sharing characters between users.

### 3.1 Derived Math Rules (Auto-Calculated in UI/Model, Overridable if needed)
* **Ability Modifier:** $$\text{Modifier} = \lfloor \frac{\text{Score} - 10}{2} \rfloor$$
* **Saving Throw Total:** $\text{Ability Modifier} + (\text{isProficient} \ ? \ \text{proficiencyBonus} : 0)$
* **Skill Total:** $\text{Linked Ability Modifier} + (\text{isProficient} \ ? \ \text{proficiencyBonus} : 0)$

### 3.2 Complete Character JSON Schema
```json
{
  "id": "uuid-string",
  "name": "Theren Amakiir",
  "characterClass": "Wizard",
  "level": 5,
  "proficiencyBonus": 3,
  "armorClass": 15,
  "initiative": 2,
  "speed": 30,
  "hp": {
    "current": 32,
    "max": 32,
    "temp": 0
  },
  "hitDice": {
    "total": "5d6",
    "remaining": 5
  },
  "deathSaves": {
    "successes": 0,
    "failures": 0
  },
  "abilities": {
    "STR": 8,
    "DEX": 14,
    "CON": 14,
    "INT": 18,
    "WIS": 12,
    "CHA": 10
  },
  "savingThrowProficiencies": {
    "STR": false,
    "DEX": false,
    "CON": false,
    "INT": true,
    "WIS": true,
    "CHA": false
  },
  "skillProficiencies": {
    "Acrobatics": false,
    "Animal Handling": false,
    "Arcana": true,
    "Athletics": false,
    "Deception": false,
    "History": true,
    "Insight": true,
    "Intimidation": false,
    "Investigation": true,
    "Medicine": false,
    "Nature": false,
    "Perception": false,
    "Performance": false,
    "Persuasion": false,
    "Religion": false,
    "Sleight of Hand": false,
    "Stealth": false,
    "Survival": false
  },
  "currency": {
    "cp": 0,
    "sp": 15,
    "ep": 0,
    "gp": 120,
    "pp": 0
  },
  "items": [
    {
      "id": "item-1",
      "name": "Potion of Healing",
      "amount": 3,
      "description": "You regain 2d4 + 2 hit points when you drink this potion."
    }
  ],
  "featuresAndNotes": [
    {
      "id": "note-1",
      "name": "Arcane Recovery",
      "description": "Once per day when you finish a short rest, you can choose expended spell slots to recover."
    }
  ],
  "spellSlots": {
    "1": { "remaining": 2, "max": 4 },
    "2": { "remaining": 3, "max": 3 },
    "3": { "remaining": 2, "max": 2 },
    "4": { "remaining": 0, "max": 0 },
    "5": { "remaining": 0, "max": 0 },
    "6": { "remaining": 0, "max": 0 },
    "7": { "remaining": 0, "max": 0 },
    "8": { "remaining": 0, "max": 0 },
    "9": { "remaining": 0, "max": 0 }
  },
  "spells": [
    {
      "id": "spell-1",
      "name": "Fireball",
      "level": 3,
      "castingTime": "1 Action",
      "range": "150 feet",
      "duration": "Instantaneous",
      "components": "V, S, M (a tiny ball of bat guano and sulfur)",
      "description": "A bright streak flashes from your pointing finger to a point you choose within range and then blossoms with a low roar into an explosion of flame..."
    }
  ]
}
```

### 3.3 Standard 5e Skill-to-Ability Mapping
Hardcode this mapping in a constants file so the UI automatically displays the linked ability and calculates the bonus:
* **STR:** Athletics
* **DEX:** Acrobatics, Sleight of Hand, Stealth
* **CON:** *(None)*
* **INT:** Arcana, History, Investigation, Nature, Religion
* **WIS:** Animal Handling, Insight, Medicine, Perception, Survival
* **CHA:** Deception, Intimidation, Performance, Persuasion

---

## 4. UI/UX Layout & Functional Specifications

The desktop interface must be clean, modern, and scannable at a glance without clutter. Use a **Top Action Bar** and a **3-Column Responsive Dashboard Body**.

### 4.1 Top Navigation & Action Bar
* **Character Switcher Dropdown:** Lists all characters found in the local workspace directory. Selecting one loads that character into the dashboard.
* **`+ New Character` Button:** Creates a blank character with default stats and immediately switches to it.
* **`Duplicate Character` Button:** Creates a safe backup copy of the currently active character (e.g., `"Theren Amakiir (Copy)"`) in the workspace.
* **`Delete Character` Button:** Prompts a confirmation dialog before deleting the active character file.
* **`Import JSON` Button:** Opens the OS file picker to select an external `.json` character file, copies it into the local workspace, and loads it.
* **`Export JSON` Button:** Opens the OS "Save As" dialog to export the active character's `.json` file anywhere on the computer for sharing.
* **`Long Rest` Button:** Prompts a brief confirmation, then automatically:
  1. Sets `hp.current` equal to `hp.max`.
  2. Resets `hp.temp` to `0`.
  3. Sets all `spellSlots[level].remaining` equal to `spellSlots[level].max`.
  4. Resets `deathSaves` to `0`.
* **Auto-Save Indicator:** A subtle text/icon indicator on the far right (e.g., `"Saved ✓"`) confirming changes are written to disk.

---

### 4.2 Column 1 (Left - ~40% Width): Character Core, Combat, Abilities, Saves & Skills
Make this column vertically scrollable if the window height is small, using clean cards with subtle borders:

1. **Identity Header Card:**
   * Editable fields for **Character Name**, **Class**, and **Level**.
2. **Combat & Vitals Card:**
   * **HP Tracker:** Displays `Current HP / Max HP` and `Temp HP`. Include a **Quick Heal/Damage input box** with `+ Heal` and `- Damage` buttons so the player can type a number (e.g., `12`) and click `- Damage` to automatically deduct from Temp HP first, then Current HP.
   * **Core Combat Row:** Editable numeric boxes for **AC**, **Initiative**, **Speed**, and **Proficiency Bonus** (e.g., `+3`).
   * **Hit Dice & Death Saves Row:** 
     * Hit Dice: `Total` (text, e.g., `5d8`) and `Remaining` (number stepper).
     * Death Saves: 3 checkboxes for `Successes` and 3 checkboxes for `Failures`.
3. **6 Ability Scores Grid:**
   * Displayed in a 3x2 or 6x1 row of clean stat boxes (`STR`, `DEX`, `CON`, `INT`, `WIS`, `CHA`).
   * Prominent display of the calculated **Modifier** (e.g., `+4`) and an editable field for the base **Score** (e.g., `18`).
4. **Saving Throws & Skills Split List:**
   * **Left Sub-Panel (Saving Throws):** Lists all 6 abilities with a circular proficiency checkbox, the ability name, and the auto-calculated total modifier.
   * **Right Sub-Panel (Skills):** Lists all 18 skills alphabetically. Each row shows: `[Proficiency Checkbox] | [Calculated Bonus, e.g., +5] | Skill Name (DEX)`.

---

### 4.3 Column 2 (Center - ~30% Width): Currency, Inventory Items, & Features/Notes

1. **Currency Row Card:**
   * 5 compact numeric inputs in a single horizontal row: **CP**, **SP**, **EP**, **GP**, **PP**.
2. **Inventory Items Card (Expandable/Scrollable List):**
   * **Header:** Title `"Inventory"` and an **`+ Add Item`** button.
   * **List View:** Displays **only the Item Name and Amount badge** (e.g., `Potion of Healing (x3)`). Keep the list clean—do not show descriptions in the list view.
   * **Click Interaction:** Clicking any item row opens the **Item Details Modal** (see Section 5.1).
3. **Features & Notes Card (Expandable/Scrollable List):**
   * **Header:** Title `"Features & Notes"` and an **`+ Add Note`** button.
   * **List View:** Displays **only the Feature/Note Name** (e.g., `Sneak Attack`, `Arcane Recovery`, `Session 4 Clues`).
   * **Click Interaction:** Clicking any row opens the **Feature/Note Details Modal** (works identically to Items, without the `amount` field).

---

### 4.4 Column 3 (Right - ~30% Width): Spell Slots & Spells List

1. **Spell Slot Tracker Card:**
   * Displays Levels `1` through `9` in a compact grid or list.
   * Each level uses a **Simple Number Counter (`Remaining / Max`)**, e.g., `Level 1:  [-] 2 / 4 [+]`, where clicking `-` or `+` adjusts `remaining`, and clicking the `Max` number allows editing total slots for that level.
2. **Spells Card (Grouped by Spell Level):**
   * **Header:** Title `"Spells"` and an **`+ Add Spell`** button.
   * **List View:** Grouped into collapsible or clearly labeled sections from **Cantrips (Level 0)** up to **Level 9** (only show level headers that have spells, or show all with a clean empty state).
   * Each row displays **only the Spell Name**.
   * **Click Interaction:** Clicking any spell opens the **Spell Details Modal** (see Section 5.2).

---

## 5. Modal Dialogs & Editing Flows

A core requirement of this application is a **two-step View -> Edit flow** for Items, Spells, and Features/Notes so the user doesn't accidentally overwrite descriptions while looking them up mid-game.

### 5.1 Item Details & Edit Flow
1. **Creation (`+ Add Item`):**
   * Opens a dialog with inputs for: **Name** (required), **Amount** (integer, default `1`), and **Description** (multi-line text area).
   * Buttons: `Cancel` and `Save`.
2. **Viewing (Clicking an Item in the List):**
   * Opens a clean **Read-Only Details Modal**.
   * Displays the **Item Name**, **Amount** (with quick `-` / `+` stepper buttons for convenience), and the full scrollable **Description**.
   * Includes a dedicated **`Edit` Button**, a **`Delete` Button**, and a **`Close` Button**.
3. **Editing (Clicking the `Edit` Button inside the View Modal):**
   * Switches the modal into **Edit Mode** (or opens the Edit form) where the user can modify the **Name**, **Amount**, and **Description** text fields, then click **`Save Changes`**.

### 5.2 Spell Details & Edit Flow
1. **Creation (`+ Add Spell`):**
   * Opens a dialog with inputs for:
     * **Spell Name** (Text)
     * **Spell Level** (Dropdown: `0 (Cantrip)` through `9`)
     * **Casting Time** (Text, e.g., `1 Action`)
     * **Range** (Text, e.g., `60 feet`)
     * **Duration** (Text, e.g., `Concentration, up to 1 minute`)
     * **Components** (Text, e.g., `V, S, M`)
     * **Description** (Multi-line text area)
   * Buttons: `Cancel` and `Save`.
2. **Viewing (Clicking a Spell in the List):**
   * Opens a clean **Read-Only Spell Details Modal**.
   * Displays the **Spell Name**, **Level Badge**, a structured metadata block showing **Casting Time**, **Range**, **Duration**, and **Components**, followed by a divider and the full scrollable **Description**.
   * Includes a dedicated **`Edit` Button**, a **`Delete` Button**, and a **`Close` Button**.
3. **Editing (Clicking the `Edit` Button inside the View Modal):**
   * Switches the modal into **Edit Mode** allowing the user to modify any of the spell's fields (`Name`, `Level`, `Casting Time`, `Range`, `Duration`, `Components`, `Description`) and click **`Save Changes`**.

### 5.3 Features & Notes Details & Edit Flow
* Follows the exact same Read-Only View Modal -> `Edit` Button -> Edit Mode flow as Items, containing **Name** and **Description**.

---

## 6. Recommended Folder Structure
To keep the codebase clean and easy for the AI agent to maintain without version control:

```text
lib/
├── main.dart                     # App entry point, theme setup
├── constants/
│   └── dnd_constants.dart        # Skills map, ability names, default character factory
├── models/
│   ├── character.dart            # Main Character class + fromJson/toJson + derived math
│   ├── item.dart                 # InventoryItem model
│   ├── spell.dart                # Spell & SpellSlot models
│   └── feature_note.dart         # FeatureNote model
├── services/
│   └── storage_service.dart      # Local file I/O, atomic auto-save, import/export, duplicate
├── state/
│   └── character_controller.dart # ChangeNotifier holding active character & triggering saves
└── ui/
    ├── dashboard_screen.dart     # Top bar + 3-column layout scaffold
    ├── widgets/
    │   ├── top_action_bar.dart   # Character switcher, Import/Export, Long Rest, Duplicate
    │   ├── stats_column.dart     # Left column: Identity, HP, Combat, Abilities, Saves, Skills
    │   ├── inventory_column.dart # Center column: Currency, Items list, Features/Notes list
    │   └── spells_column.dart    # Right column: Spell Slots counter, Grouped Spells list
    └── modals/
        ├── item_modal.dart       # View -> Edit modal for Items
        ├── spell_modal.dart      # View -> Edit modal for Spells
        └── note_modal.dart       # View -> Edit modal for Features/Notes
```

---

## 7. Step-by-Step Implementation Plan for the AI Agent

When executing this design document, follow these phases sequentially and verify each compiles before moving to the next:

* **Phase 1: Project Initialization & Data Models**
  * Initialize the Flutter desktop project and add `path_provider` and `file_picker` to `pubspec.yaml`.
  * Create all data models in `lib/models/` with complete `toJson()` and `fromJson()` serialization, plus fallback defaults for missing JSON keys so imported files never crash the app.
* **Phase 2: Local Storage & State Controller**
  * Implement `StorageService` to manage the `<Documents>/DnDPlayerTracker/characters/` directory.
  * Implement atomic file writes (write to `.tmp` then rename to `.json`) to prevent corruption.
  * Build `CharacterController` (`ChangeNotifier`) that loads all characters on startup (or creates a default starter character if the folder is empty) and triggers auto-save on every model mutation.
* **Phase 3: Core Dashboard & Column 1 (Stats & Skills)**
  * Build the `TopActionBar` and the 3-column `DashboardScreen`.
  * Build `StatsColumn` with live modifier math, HP calculator (`+ Heal` / `- Damage`), proficiency checkboxes, Saving Throws, and the 18 Skills list.
* **Phase 4: Column 2 (Currency, Items, & Features/Notes) + Modals**
  * Build `InventoryColumn` and implement `ItemModal` and `NoteModal` with the strict **Read-Only View -> Click Edit Button -> Edit Mode** workflow.
* **Phase 5: Column 3 (Spell Slots & Spells) + Spell Modal**
  * Build `SpellsColumn` with the `Remaining / Max` counters for levels 1–9 and the level-grouped spell list.
  * Implement `SpellModal` with fields for Name, Level, Casting Time, Range, Duration, Components, and Description, following the **View -> Edit** workflow.
* **Phase 6: Import/Export & Polish**
  * Wire up the `Import JSON`, `Export JSON`, `Duplicate Character`, and `Long Rest` buttons.
  * Apply a cohesive dark fantasy/tabletop Material 3 theme (slate/charcoal backgrounds, subtle gold/amber accents, clear typography).