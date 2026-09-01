# azul — agent instructions

## Project

macOS + iOS 3D city model viewer (AppKit/Metal + UIKit/Metal). Open-source (GPLv3) by Ken Arroyo Ohori, TU Delft.

**Languages**: C++17, Swift 5, Objective-C++, Metal shading language.

## Build

### macOS

Open `azul.xcodeproj` in Xcode, select the **azul** scheme, build and run. There is no command-line build. No CI, no linter, no formatter.

### Tests

Unit tests live in the **azulTests** target (`tests/azulTests/`, XCTest). It is a hosted test bundle (runs inside the azul app), so tests use the existing ObjC++ bridge (`DataManagerWrapperWrapper`) via the app's bridging header and need no C++ compilation of their own. Fixtures are small files in `tests/Fixtures/` (bundled as a folder reference). Run with `⌘U` in Xcode or:

    xcodebuild test -project azul.xcodeproj -scheme azulTests -destination 'platform=macOS'

Unit tests live in three classes: `DataManagerParsingTests` (per-format parsing), `DataManagerStateTests` (visibility, attributes, selection, buffer splitting, malformed input, degenerate geometry, FCB/JSON parity) and `MathTests`. `tests/generate_themed_fcb.py` regenerates `tests/Fixtures/themed.fcb` (a hand-built FlatCityBuf fixture with attributes, two LoDs and appearance themes); run it from the repo root after changing the FCB reader's expected schema.

Minimum macOS 13.0, minimum iOS 15.0; Xcode targets macOS 26 (Tahoe) but works on older Xcode.

### iOS

Open `azul.xcodeproj` in Xcode and build:
- **Device**: select the **azul-iOS** scheme, build and run on a device.
- **Simulator**: select the **azul-iOS-simulator** scheme, build and run on a simulator.

**Important**: The iOS target uses static libraries in `libs-ios/`. These must match the target platform:
- **Device** (`iphoneos` SDK): `libs-ios-device/` contains `arm64-apple-ios` builds. Copy to `libs-ios/` before building for device.
- **Simulator** (`iphonesimulator` SDK): `libs-ios-sim/` contains `arm64-apple-ios-simulator` builds. Copy to `libs-ios/` before building for simulator.
- **Xcode schemes handle this automatically** — `azul-iOS` expects device libs, `azul-iOS-simulator` expects simulator libs.

Both `arm64` variants are incompatible — lipo cannot combine them since they share the same architecture name.

Xcode Cloud: macOS only; uses `ci_scripts/ci_pre_xcodebuild.sh` to install pinned dependency versions from Homebrew before building.

## Architecture

### macOS
- **Entry point**: `src/Controller.swift` (`@NSApplicationMain` app delegate)
- **Swift → C++ bridge**: `DataManagerWrapperWrapper.{h,mm}` + `PerformanceHelperWrapperWrapper.{h,mm}` expose C++ `DataManager` to Swift via Objective-C++. The bridging header (Swift→ObjC) is `src/Azul-Bridging-Header.h`. The `.mm` files also import `"azul-Swift.h"` (Xcode-generated ObjC→Swift header) to call back into Swift types.
- **C++ core**: `src/DataManager/DataManager.cpp` owns all data, file parsing, triangulation, edge generation, selection, LOD filtering. Parsing helpers in `src/DataManager/*ParsingHelper.hpp`.
- **Rendering**: `src/MetalView.swift` (MTKView subclass) + `src/Shaders.metal`. MSAA configurable (1/2/4x). Lit/unlit/picking pipelines cached as binary archive (`azul.metalar`). Textured pipeline (`vertexLitTextured`/`fragmentLitTextured`) used when appearances are on and a texture URI is available on the triangle buffer. Export pipelines (`exportLitRenderPipelineState`, etc.) use `.rgba8Unorm` with MSAA matching the view setting. Selection highlight uses a luminance-aware hybrid blend (screen blend on dark surfaces, plain mix on bright surfaces) with configurable alpha.
- **Appearance system**: Single dropdown in toolbar: "Semantics" (appearances off, uses type-based `colourForType` map) plus named themes (Materials, Textures, and any themes from the file). Dropdown always defaults to Semantics on file load. Appearance theme/state is stored in `DataManager::{useAppearances, appearanceTheme}` and persisted via `metalView.showTextures` + `currentAppearanceTheme`.
- **UI**: Menu bar loaded from `src/Base.lproj/MainMenu.xib` (XIB); all other UI (NSSplitView, NSOutlineView sidebar, NSTableView attributes) is programmatic. Appearance controls in toolbar dropdown only (no separate toggle). App icon and CityGML type icons in `src/Assets.xcassets/`; document type icons in `src/Icons/`.

### iOS
- **Entry point**: `src_iOS/AppDelegate.swift` (`@main` UIApplicationDelegate) + `src_iOS/SceneDelegate.swift` (UISceneDelegate)
- **Root VC**: `src_iOS/MainViewController.swift` — full-screen MTKView, floating buttons (UIVisualEffectView blur), gesture recognizers, file loading, GPU picking, empty state view
- **Object browser**: `src_iOS/ObjectListViewController.swift` — expandable UITableView with hierarchy (context menus with peek preview, visibility toggles)
- **Attributes**: `src_iOS/AttributeTableViewController.swift` — key-value table for selected object
- **Appearance picker**: `src_iOS/AppearancePickerViewController.swift` — inset grouped table with theme icons
- **LoD picker**: `src_iOS/LodPickerViewController.swift` — inset grouped table with LoD icons
- **Bridging**: Same ObjC++ bridge as macOS (`DataManagerWrapperWrapper.{h,mm}`) with `#if TARGET_OS_OSX` conditionals for platform-specific code. iOS bridging header: `src_iOS/Azul-Bridging-Header.h`
- **Shared types**: `src/Math.swift` — matrix/vector helpers + Metal structs (`Constants`, `Vertex`, `EdgeVertex`, `VertexWithNormal`, `BufferWithColour`). Used by both platforms.

## Dependencies (prebuilt, gitignored)

| Directory | Contents |
|-----------|----------|
| `include/` | Boost, CGAL, GMP, MPFR, pugixml headers/source (gitignored) |
| `libs/` | macOS fat (arm64+x86_64) static libs: boost_thread, gmp, mpfr, pugixml |
| `libs-ios-device/` | iOS device arm64 static libs (built with iphoneos SDK) |
| `libs-ios-sim/` | iOS simulator arm64 static libs (built with iphonesimulator SDK) |
| `libs src/` | Dependency source (not tracked) |

`include/` is gitignored — populated locally via vendored copy, on Xcode Cloud by `ci_scripts/ci_pre_xcodebuild.sh` from Homebrew. simdjson is vendored as source in `src/DataManager/simdjson.{cpp,h}`.

### Pinned versions

| Library | Version | Homebrew formula |
|---------|---------|-----------------|
| Boost | 1.90.0 | `boost` |
| CGAL | 6.1.1 | `cgal` |
| GMP | 6.3.0 | `gmp` |
| MPFR | 4.2.2 | `mpfr` |
| pugixml | 1.15 | `pugixml` |
| simdjson | 4.6.3 | vendored in source |

## Source layout

| Path | Purpose |
|------|---------|
| `src/Controller.swift` | macOS app delegate, window setup, file loading pipeline |
| `src/MetalView.swift` | macOS MTKView, rendering, camera controls, picking |
| `src/Math.swift` | Matrix/vector math helpers + shared Metal structs (macOS + iOS) |
| `src/Shaders.metal` | Metal vertex/fragment shaders (macOS + iOS) |
| `src/DataManager/DataManager.{cpp,hpp}` | Core data model and operations |
| `src/DataManager/DataModel.hpp` | Internal data structures (AzulObject, etc.) |
| `src/DataManager/DataManagerWrapperWrapper.{h,mm}` | ObjC++ bridge exposing C++ DataManager to Swift |
| `src/DataManager/PerformanceHelperWrapperWrapper.{h,mm}` | ObjC++ bridge for performance timing/memory |
| `src/DataManager/TableCellView.{h,m}` | macOS custom NSTableCellView with checkbox + icon + label |
| `src/DataManager/AppearanceHelpers.hpp` | Shared appearance parsing helpers (style key, URI resolution) |
| `src/DataManager/*ParsingHelper.hpp` | Format-specific parsers (GML, JSON, JSONL, OBJ, OFF, POLY, FCB) |
| `src/DataManager/simdjson.{cpp,h}` | Vendored simdjson 4.6.3 |
| `src/Base.lproj/MainMenu.xib` | macOS menu bar (XIB) |
| `src/Assets.xcassets/` | App icon (macOS + iOS) + CityGML type icons + AzulIcon image set |
| `src/Icons/` | Document type icons (.icns) |
| `data/` | Sample data files for testing, organised by format (`cityjson/`, `jsonl/`, `gml/`, `obj/`, `fcb/`) |
| `azul.entitlements` | macOS sandbox entitlements |
| `src_iOS/AppDelegate.swift` | iOS app delegate, window/scene management |
| `src_iOS/SceneDelegate.swift` | iOS scene delegate, window creation |
| `src_iOS/MainViewController.swift` | iOS root VC: rendering, gestures, UI, file loading |
| `src_iOS/ObjectListViewController.swift` | iOS expandable object hierarchy browser (context menus, peek preview, visibility toggles) |
| `src_iOS/AttributeTableViewController.swift` | iOS attribute inspector |
| `src_iOS/AppearancePickerViewController.swift` | iOS appearance theme picker (inset grouped table) |
| `src_iOS/LodPickerViewController.swift` | iOS LoD filter picker (inset grouped table with icons) |
| `src_iOS/Azul-Bridging-Header.h` | iOS bridging header (Swift→ObjC++) |
| `libs-ios-device/` | iOS device static libraries |
| `libs-ios-sim/` | iOS simulator static libraries |

## Data flow (file loading pipeline)

This ordering matters — it's the exact sequence in `Controller.swift:loadData(from:)` (macOS) and `MainViewController.swift:loadFile(url:)` (iOS):

1. `parse(filePath)` — reads file, populates `AzulObject` tree
2. `clearHelpers()` — releases parser memory
3. `updateBoundsWithLastFile()` — computes bounding box
4. `triangulateLastFile()` — CGAL triangulation of concave polygons
5. `generateEdgesForLastFile()` — extracts edges, deduplicated per feature (file-child and CityJSON `LoD` subtrees), so shared polygon/triangle edges are stored once
6. `clearPolygonsOfLastFile()` — frees polygon memory (only triangles/edges kept)
7. `regenerateTriangleBuffers(maxBufferSize: 16*1024*1024)` — builds GPU buffers
8. `regenerateEdgeBuffers(maxBufferSize: 16*1024*1024)` — builds edge buffers
9. (Swift side) `reloadTriangleBuffers()`, `reloadEdgeBuffers()`, `regenerateBoundingBoxBuffer()`
10. `availableLods()` + `setLodFilter("__highest__")` + regenerate buffers (default to highest LoD)

## Appearance system

CityGML and CityJSON appearance data (X3DMaterial and ParameterizedTexture) is parsed in `GMLParsingHelper.hpp` and `JSONParsingHelper.hpp`; FlatCityBuf appearance data in `FCBParsingHelper.hpp`. Styles are pooled into `AzulAppearanceStyle` structs and assigned to polygons via `appearanceStyleId`. During buffer regeneration, the `DataManager::useAppearances` and `appearanceTheme` flags control whether appearance data overrides the semantic `colourForType` fallback.

The toolbar dropdown offers:
- **Semantics**: type-based colouring (`colourForType` map), appearances off
- **Materials**: material colours from the file (X3DMaterial), textures suppressed
- **Textures**: texture images from the file (ParameterizedTexture), material colours suppressed
- **Named themes** (if present): both materials and textures filtered by theme

### ImplicitGeometry (CityGML trees)

Vegetation objects in CityGML often use `ImplicitGeometry` with a shared template geometry and `xlink:href` references. The parser expands these templates per instance, applying the transformation matrix to geometry points. Appearance data (`appearanceStyleId`, `textureCoordinates`) must be explicitly copied from the template — `AzulPolygon()` default constructor discards them (`GMLParsingHelper.hpp:947-1003`).

### FlatCityBuf (`.fcb`)

`FCBParsingHelper.hpp` is a self-contained binary reader: it hand-decodes the FlatBuffers subset the schemas use (no FlatBuffers runtime dependency) and mirrors the JSON parser's `AzulObject` output. Geometry is stored as flattened count arrays (`solids`/`shells`/`surfaces`/`strings`/`boundaries`) with one redundant count level above a type's depth, which the surface walker ignores. The R-tree and attribute B+tree index sections are skipped (azul loads whole files); only their byte lengths are computed from the header. The Rust flatbuffers builder omits scalar fields equal to their schema default (absent `template`, `index`, `type`…), so absent scalars read as defaults, and vtables may sit after their table (signed soffset). A `GeometryInstance` has no LoD field in the schema, so its LoD child uses the template's LoD. Theme selection skips mappings without values, and a shared material `value` colours the whole geometry, matching the JSON parser's theme handling.

## Key conventions

- Functions bridging to Swift return C types (`float *`, `const char *`); Swift side wraps with `UnsafeBufferPointer`.
- Colour = `(r, g, b, a)` float tuple. `a == 1.0` renders opaque first, `a < 1.0` renders second (transparent overlay).
- Selection overlay colour is configurable via Preferences (default yellow `(1.0, 1.0, 0.0, 0.7)`). Passed as `selectionColour` in the `Constants` Metal struct. Blend mode switches between screen blend (dark surfaces) and plain mix (bright surfaces) based on luminance.
- Selected edges colour is configurable via Preferences (default red). Stored in `DataManager::selectedEdgesColour`, baked into edge buffers on regeneration.
- Type/semantic surface colours are configurable via Preferences. Stored in `DataManager::colourForType` map; overrides persisted in UserDefaults `azulTypeColours` as `[type: [r, g, b, a]]`.
- Preferences window has three tabbed panels: Rendering, Selection, Semantic Surfaces. All settings persist in UserDefaults.
- UserDefaults keys: `azulLightBackgroundColor`, `azulDarkBackgroundColor`, `azulSampleCount`, `azulSelectionColour`, `azulSelectedEdgesColour`, `azulTypeColours`, `azulRecentFiles`, `azulSortKey` (`"none"`/`"id"`/`"type"`), `azulSortDescending`.
- Sorting is a cached display permutation, never an in-place sort of `AzulObject::children` (that would invalidate the iterators wrapped by `AzulObjectIterator` and the pointers in `objectsById`). `DataManager::child()`/`fileChild()` walk per-node `displayOrder` index vectors, recomputed lazily after `setSortOrder` or a new `parse` (invalidated via `sortOrdersCurrent`).
- Object picking uses a dedicated GPU-only render pass (`vertexPicking`/`fragmentPicking`) that encodes `objectId` into pixel bytes.
- `selectionStateCount` on GPU side = `objectsById.size()`; represents number of selectable flat objects.
- LOD filter is a string match; empty string = no filter. LOD detected from objects with type `"LoD"` (id = lod string) or type starting with `"lod"` + digits.
- Search string is matched against object IDs, types, and attribute keys/values.
- Object type filter is sidebar-only (like search): `DataManager::objectTypeFilter` (empty set = all types) with a memoized tri-state `AzulObject::matchesTypeFilter` ('Y'/'N'/'U'); an object matches if its own type is selected or any descendant matches, so ancestors stay visible for context. `availableTypesWithCounts()` feeds the UI menus and skips structural rows (`"File"`, `"LoD"`, `"lod"+digits`). The filter is not persisted and resets on file load.
- Visible state is a tri-state char: `'Y'` (all visible), `'N'` (all invisible), `'P'` (partly). Toggling regenerates GPU buffers.
- View parameters can be saved/loaded as `.azulview` JSON files.
- Image export renders the view to PNG via an offscreen render pass (MSAA-aware, supports transparent background). Resolution 1×/2×/4× of drawable size. File → Export Image… (`⌘E`) with options in the save panel accessory view.
- `BOOL` return values in ObjC wrappers are `YES`/`NO` proper, not `true`/`false`.
- iOS conditional compilation uses `#if TARGET_OS_OSX` / `#if !TARGET_OS_OSX` in ObjC++ files.
- iOS uses `matrix4x4_perspective_shorter_dim()` (FOV constrained by shorter dimension) vs macOS which now also uses this function.
- Empty state view (icon, title, subtitle, description, Open File button) shown when no file is loaded, on both iOS (`src_iOS/MainViewController.swift:setupEmptyState()`) and macOS (`src/Controller.swift:setupEmptyStateView()`). Fades out after file load.
- Selection pulse: briefly boosts `selectionColour.w` to 1.0 then ramps back to 0.7 over 300ms when an object is selected. iOS: `MainViewController.animateSelectionPulse()`. macOS: `MetalView.animateSelectionPulse()`.
- Context menus on iOS use `UIContextMenuConfiguration` with `UIContextMenuContentPreviewProvider` for peek previews. Object list (sidebar/modal) and 3D view (metalView) both have context menus.
- Recent files (iOS Open button menu; macOS File → Open Recent, which replaces the standard system menu) stored in `UserDefaults.standard` under key `"azulRecentFiles"`. Capped at 5 entries on iOS; on macOS capped at the global-domain `NSRecentDocumentsLimit` when set (Apple does not expose the Control Center "Recent documents, applications, and servers" setting to apps), otherwise 10. macOS stores security-scoped bookmarks (`.withSecurityScope`) so recents open across launches in the sandbox; menu items are rebuilt via `Controller.reloadRecentFilesMenu()`.
