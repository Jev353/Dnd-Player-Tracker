# D&D 5e Player Tracker — Multi-Layer Party Map Specification & Agent Prompts

## 1. Feature Overview & Architecture
This document specifies the design and phased implementation plan for a Roll20-style **Multi-Layer Interactive Party Map** (`World`, `Town`, `Battle`) with real-time Supabase synchronization and GM-specific permissions.

### Core Design Principles
* **Preserve Existing Architecture:** Follow the existing pattern in `lib/models/`, `lib/services/`, `lib/state/`, and `lib/ui/` (`ChangeNotifier` state management, `json_helpers.dart` for safe parsing, and `app_theme.dart` for dark fantasy styling).
* **Party-Centric Real-Time Sync:** Everyone in a party connects to a shared `party_code` via Supabase Realtime (`party_maps` table + broadcast/postgres changes).
* **Role-Based UI & Permissions (`isGM`):**
  * **GM (`isGM == true`):** Can create/upload maps, switch the party's active layer/map, toggle/resize the battle grid, spawn/delete any token, move any token, and toggle token visibility (hidden monsters/NPCs).
  * **Player (`isGM == false`):** Automatically views the `activeMapId` set by the GM, can pan/zoom freely on their own screen, and can **only** drag tokens where `characterId == characterController.character.id`. Cannot see tokens where `visibleToPlayers == false`.
* **Future-Proof for Fog of War:** The map rendering `Stack` must reserve a dedicated layer slot above the tokens for a future `FogOfWarPainter`.

---

## 2. Target File Structure
```text
lib/
├── models/
│   ├── map_token.dart          # Token model (id, characterId, label, x, y, size, colorHex, visibleToPlayers)
│   ├── map_scene.dart          # Single map layer/scene (id, name, category, imageUrl, gridEnabled, gridSize, tokens, fogRevealedPolygons)
│   └── party_session.dart      # Party state (partyCode, activeSceneId, scenes)
├── state/
│   └── map_controller.dart     # ChangeNotifier managing party session, GM status, token movement, and sync
├── services/
│   └── sync_service.dart       # Extended with Supabase Realtime stream & Storage upload for map images
└── ui/
    ├── modals/
    │   └── map_modal.dart      # Full-screen or large modal housing the map, layer switcher, and GM toolbar
    └── widgets/
        ├── map_canvas.dart     # InteractiveViewer + Stack (Image -> GridPainter -> Tokens -> FogOfWar placeholder)
        └── grid_painter.dart   # CustomPainter for 5ft battle grid overlay
```

---

## 3. Data Models & JSON Schema

### `MapCategory` Enum
`world`, `town`, `battle`

### `MapToken` JSON Schema
```json
{
  "id": "uuid-string",
  "character_id": "optional-character-uuid-or-null-for-monster",
  "label": "Flint",
  "x": 250.0,
  "y": 300.0,
  "size": 1.0,
  "color_hex": "#D4AF37",
  "visible_to_players": true
}
```

### `MapScene` JSON Schema
```json
{
  "id": "scene-uuid",
  "name": "Cragmaw Hideout",
  "category": "battle",
  "image_url": "https://.../map.png",
  "grid_enabled": true,
  "grid_size": 50.0,
  "tokens": [],
  "fog_polygons": []
}
```

### Supabase Table Schema (`party_maps`)
Run this SQL in the Supabase SQL Editor before Phase 3:
```sql
create table if not exists public.party_maps (
  party_code text primary key,
  active_scene_id text,
  scenes jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.party_maps enable row level security;

create policy "Allow public read/write by party_code"
on public.party_maps
for all
using (true)
with check (true);

-- Enable Realtime for party_maps
alter publication supabase_realtime add table public.party_maps;
```
*(Optional: Create a public Supabase Storage bucket named `map-images` with public read/insert policies so the GM can upload map files directly from their PC).*

---

## 4. Step-by-Step Agent Prompts

Feed these prompts to your AI coding agent **one phase at a time**. Wait for each phase to compile and pass tests before moving to the next prompt.

---

### Phase 1: Models, State Controller, & Party/GM Setup
**Goal:** Create the data models and `MapController` state management with local persistence and a GM role toggle.

#### Copy-and-Paste Prompt for Phase 1:
```text
We are adding a multi-layer interactive party map feature to this Flutter D&D 5e Player Tracker app. Please read `map_feature_agent_spec.md`, `lib/models/character.dart`, `lib/models/json_helpers.dart`, and `lib/state/character_controller.dart` first so you match our exact code style and conventions.

For Phase 1, do NOT build the map canvas UI or Supabase sync yet. Please implement:

1. `lib/models/map_token.dart`:
   - Fields: `id` (String), `characterId` (String?), `label` (String), `x` (double), `y` (double), `size` (double, default 1.0), `colorHex` (String, default '#D4AF37'), `visibleToPlayers` (bool, default true).
   - Include `fromJson`, `toJson`, and `copyWith` using our helper conventions in `json_helpers.dart`.

2. `lib/models/map_scene.dart`:
   - Enum `MapCategory { world, town, battle }`.
   - Fields: `id` (String), `name` (String), `category` (MapCategory), `imageUrl` (String, can be a local file path or remote URL), `gridEnabled` (bool), `gridSize` (double, default 50.0), `tokens` (List<MapToken>), `fogPolygons` (List<List<Map<String, double>>>, default empty for future Fog of War).
   - Include `fromJson`, `toJson`, and `copyWith`.

3. `lib/state/map_controller.dart`:
   - A `ChangeNotifier` that manages:
     - `String? partyCode`
     - `bool isGM` (default false)
     - `String? activeSceneId`
     - `List<MapScene> scenes`
   - Methods:
     - `setPartySession({required String partyCode, required bool isGM})`
     - `addScene(MapScene scene)` (GM only)
     - `setActiveScene(String sceneId)` (GM sets the active party scene)
     - `updateSceneSettings(String sceneId, {bool? gridEnabled, double? gridSize, String? imageUrl})` (GM only)
     - `addToken(MapToken token)` (GM can add any token; Player can add their own character token if not already on the map)
     - `moveToken(String tokenId, double newX, double newY, {required String? currentCharacterId})` — Enforce permission: allow move if `isGM == true` OR if `token.characterId == currentCharacterId`. If `activeScene.gridEnabled` is true, provide a helper `snapTokenToGrid(String tokenId)`.
     - `toggleTokenVisibility(String tokenId)` (GM only)
     - `removeToken(String tokenId)` (GM only)

Verify that `flutter analyze` passes with zero errors.
```

---

### Phase 2: Interactive Multi-Layer Map UI, Grid Overlay, & Draggable Tokens
**Goal:** Build the Roll20-style pan/zoom canvas, World/Town/Battle layer switcher, battle grid painter, and GM toolbar, accessible from the Top Action Bar.

#### Copy-and-Paste Prompt for Phase 2:
```text
Now let's implement Phase 2 of `map_feature_agent_spec.md`: the interactive Map UI and GM/Player controls. Please inspect `lib/ui/app_theme.dart`, `lib/ui/dashboard_screen.dart`, and `lib/ui/widgets/top_action_bar.dart` to match our dark fantasy theme (`AppTheme`).

Please implement:

1. `lib/ui/widgets/grid_painter.dart`:
   - A `CustomPainter` that draws a crisp square grid over the map when `gridEnabled` is true, using `gridSize` (in pixels) and a subtle semi-transparent gold/parchment line color.

2. `lib/ui/widgets/map_canvas.dart`:
   - Uses an `InteractiveViewer(constrained: false, minScale: 0.1, maxScale: 4.0, boundaryMargin: EdgeInsets.all(400))` wrapping a `Stack`.
   - Layer 1: Map background image (supports both network URLs via `Image.network` and local file paths via `Image.file`, with a fallback styled placeholder canvas of size 1600x1200 if `imageUrl` is empty).
   - Layer 2: If `scene.gridEnabled`, render `Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: GridPainter(gridSize: scene.gridSize))))`.
   - Layer 3: Render `scene.tokens` (filter out tokens where `!token.visibleToPlayers && !mapController.isGM`).
     - Each token is a `Positioned(left: token.x, top: token.y, ...)` wrapped in a `GestureDetector`.
     - `onPanUpdate`: calls `mapController.moveToken(...)` using `details.delta` so dragging a token moves it smoothly without panning the background map.
     - `onPanEnd`: if `scene.gridEnabled`, calls `mapController.snapTokenToGrid(token.id)`.
     - Token visual: circular token scaled to `scene.gridSize * token.size`, showing the token's `colorHex` border, initials/label, and a semi-transparent ghost indicator if `!token.visibleToPlayers` (so the GM knows it's hidden from players).
   - Layer 4: A comment placeholder `// TODO: Phase 4 Fog of War CustomPainter Layer` right above the tokens.

3. `lib/ui/modals/map_modal.dart`:
   - A full-screen (or 90% viewport) dialog/modal that takes `MapController` and `CharacterController`.
   - Top header bar inside the modal:
     - Category tabs for `World`, `Town`, and `Battle` to filter/view scenes.
     - Party Code badge + Role toggle/indicator (`GM Mode` vs `Player Mode`).
     - Button to "Drop My Character Token" onto the current map (links to `characterController.character.id` and `character.name`).
   - GM-Only Toolbar (only visible when `mapController.isGM == true`):
     - Add New Map Scene (name, category: World/Town/Battle, image URL or local file picker via `file_picker`).
     - Scene selector dropdown + "Push Scene to Party" button.
     - Toggle Grid switch + Grid Size slider (`25px` to `120px`).
     - "Add Monster/NPC Token" button (lets GM pick label, size, color, and whether it starts hidden from players).
     - Right-click or long-press on a token (for GM) to toggle visibility (`visibleToPlayers`) or delete the token.

4. Wire `MapController` into `DashboardScreen` and add a "Party Map" icon button in `lib/ui/widgets/top_action_bar.dart` that opens `MapModal`.

Run `flutter analyze` and ensure everything compiles cleanly.
```

---

### Phase 3: Real-Time Party Sync with Supabase
**Goal:** Connect `MapController` and `SyncService` so when the GM switches maps or anyone drags a token, all party members see it live.

#### Copy-and-Paste Prompt for Phase 3:
```text
Now let's implement Phase 3 of `map_feature_agent_spec.md`: Real-time Supabase party synchronization. Please inspect `lib/services/sync_service.dart` first.

Please implement the following:

1. Extend `lib/services/sync_service.dart` (or create `lib/services/map_sync_service.dart` if cleaner):
   - Add `Future<void> pushPartyMapState(String partyCode, String? activeSceneId, List<MapScene> scenes)` which upserts to the `party_maps` table in Supabase (`party_code`, `active_scene_id`, `scenes`, `updated_at`).
   - Add `Stream<Map<String, dynamic>?> subscribeToPartyMap(String partyCode)` using Supabase Realtime (`.from('party_maps').stream(primaryKey: ['party_code']).eq('party_code', partyCode)`).
   - Optional helper: Add `Future<String?> uploadMapImage(String partyCode, String filePath)` that uploads a local map image to a Supabase Storage bucket named `map-images` and returns the public URL so all players can render the map image.

2. Connect `MapController` to the sync service:
   - When a user joins/starts a `partyCode` in `MapModal`, subscribe to `subscribeToPartyMap(partyCode)`.
   - When remote updates arrive:
     - Update `scenes` and `activeSceneId` and call `notifyListeners()`.
     - Ensure that if a user is currently dragging a token locally (`_isDraggingTokenId`), incoming updates don't jitter the token they are actively dragging.
   - Throttle or debounce `pushPartyMapState` during `moveToken` (e.g., every 100ms while dragging, plus an immediate push on `onPanEnd`) so token movements feel smooth without spamming Supabase.
   - When a Player (`isGM == false`) is connected to a `partyCode`, automatically lock their view to the `activeSceneId` pushed by the GM.

Run `flutter analyze` and verify there are no build or lint issues.
```

---

### Phase 4 (Future Task): Fog of War Layer
**Goal:** Allow the GM to cover maps in fog and reveal areas to players using a brush or rectangle tool.

#### Copy-and-Paste Prompt for Phase 4 (Save for Later):
```text
Now let's implement Phase 4 of `map_feature_agent_spec.md`: Fog of War.

1. Add a `bool fogEnabled` field to `MapScene` (default false) and ensure `fogPolygons` (or `List<Rect> revealedRects`) serializes in `toJson`/`fromJson`.
2. Create `lib/ui/widgets/fog_of_war_painter.dart`:
   - When `scene.fogEnabled` is true:
     - Draw a layer over the map at Layer 4 in `map_canvas.dart` using `canvas.saveLayer(...)`.
     - For Players (`!isGM`), fill the canvas with opaque dark fog (`Colors.black.withOpacity(0.95)`).
     - For the GM (`isGM`), fill the canvas with semi-transparent fog (`Colors.black.withOpacity(0.55)`) so the GM can still see the map and hidden monsters underneath.
     - Loop through `revealedRects` and clear those areas using `Paint()..blendMode = BlendMode.clear`.
3. In `MapModal` (GM Toolbar):
   - Add a "Toggle Fog of War" switch, a "Reveal Area (Brush/Drag)" mode toggle, and a "Reset Fog" button.
   - When the GM is in "Reveal Area" mode, dragging on the map adds a revealed circle/rect to `scene.revealedRects` and syncs it to the party via `MapController`.
```