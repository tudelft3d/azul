# azul — agent instructions

## Project

macOS 3D city model viewer (AppKit + Metal). Open-source (GPLv3) by Ken Arroyo Ohori, TU Delft.

**Languages**: C++17, Swift 5, Objective-C++, Metal shading language.

## Build

Open `azul.xcodeproj` in Xcode, select the azul scheme, build and run. There is no command-line build. No CI, no tests, no linter, no formatter.

Minimum macOS 13.0; Xcode targets macOS 26 (Tahoe) but works on older Xcode.

## Architecture

- **Entry point**: `src/Controller.swift` (`@NSApplicationMain` app delegate)
- **Swift → C++ bridge**: `DataManagerWrapperWrapper.{h,mm}` + `PerformanceHelperWrapperWrapper.{h,mm}` expose C++ `DataManager` to Swift via Objective-C++. The bridging header (Swift→ObjC) is `src/Azul-Bridging-Header.h`. The `.mm` files also import `"azul-Swift.h"` (Xcode-generated ObjC→Swift header) to call back into Swift types.
- **C++ core**: `src/DataManager/DataManager.cpp` owns all data, file parsing, triangulation, edge generation, selection, LOD filtering. Parsing helpers in `src/DataManager/*ParsingHelper.hpp`.
- **Rendering**: `src/MetalView.swift` (MTKView subclass) + `src/Shaders.metal`. 4x MSAA. Lit/unlit/picking pipelines cached as binary archive (`azul.metalar`).
- **UI**: Menu bar loaded from `src/Base.lproj/MainMenu.xib` (XIB); all other UI (NSSplitView, NSOutlineView sidebar, NSTableView attributes) is programmatic. App icon and CityGML type icons in `src/Assets.xcassets/`; document type icons in `src/Icons/`.

## Dependencies (prebuilt, gitignored)

| Directory | Contents |
|-----------|----------|
| `include/` | Boost, CGAL, GMP, MPFR, pugixml headers/source |
| `libs/` | Fat (arm64+x86_64) static libs: boost_thread, gmp, mpfr, pugixml |
| `libs src/` | Dependency source (not tracked) |

Install via Homebrew if needed, but the prebuilt libs are provided. simdjson is vendored as source in `src/DataManager/simdjson.{cpp,h}`.

## Source layout

| Path | Purpose |
|------|---------|
| `src/Controller.swift` | App delegate, window setup, file loading pipeline |
| `src/MetalView.swift` | MTKView, rendering, camera controls, picking |
| `src/Math.swift` | Matrix/vector math helpers |
| `src/Shaders.metal` | Metal vertex/fragment shaders |
| `src/DataManager/DataManager.{cpp,hpp}` | Core data model and operations |
| `src/DataManager/DataModel.hpp` | Internal data structures (AzulObject, etc.) |
| `src/DataManager/DataManagerWrapperWrapper.{h,mm}` | ObjC++ bridge exposing C++ DataManager to Swift |
| `src/DataManager/PerformanceHelperWrapperWrapper.{h,mm}` | ObjC++ bridge for performance timing/memory |
| `src/DataManager/TableCellView.{h,m}` | Custom NSTableCellView with checkbox + icon + label |
| `src/DataManager/*ParsingHelper.hpp` | Format-specific parsers (GML, JSON, JSONL, OBJ, OFF, POLY) |
| `src/DataManager/simdjson.{cpp,h}` | Vendored simdjson 4.6.3 |
| `src/Base.lproj/MainMenu.xib` | Menu bar (XIB) |
| `src/Assets.xcassets/` | App icon + CityGML type icons |
| `src/Icons/` | Document type icons (.icns) |
| `data/` | Sample city JSON files for testing |
| `azul.entitlements` | Sandbox entitlements |

## Data flow (file loading pipeline)

This ordering matters — it's the exact sequence in `Controller.swift:loadData(from:)`:

1. `parse(filePath)` — reads file, populates `AzulObject` tree
2. `clearHelpers()` — releases parser memory
3. `updateBoundsWithLastFile()` — computes bounding box
4. `triangulateLastFile()` — CGAL triangulation of concave polygons
5. `generateEdgesForLastFile()` — extracts edges
6. `clearPolygonsOfLastFile()` — frees polygon memory (only triangles/edges kept)
7. `regenerateTriangleBuffers(maxBufferSize: 16*1024*1024)` — builds GPU buffers
8. `regenerateEdgeBuffers(maxBufferSize: 16*1024*1024)` — builds edge buffers
9. (Swift side) `reloadTriangleBuffers()`, `reloadEdgeBuffers()`, `regenerateBoundingBoxBuffer()`

## Key conventions

- Functions bridging to Swift return C types (`float *`, `const char *`); Swift side wraps with `UnsafeBufferPointer`/`Data`.
- Colour = `(r, g, b, a)` float tuple. `a == 1.0` renders opaque first, `a < 1.0` renders second (transparent overlay).
- Selection overlay colour is yellow (`(1,1,0,1)`) applied in the fragment shader.
- Object picking uses a dedicated GPU-only render pass (`vertexPicking`/`fragmentPicking`) that encodes `objectId` into pixel bytes.
- `selectionStateCount` on GPU side = `objectsById.size()`; represents number of selectable flat objects.
- LOD filter is a string match; empty string = no filter. LOD detected from objects with type `"LoD"` (id = lod string) or type starting with `"lod"` + digits.
- Search string is matched against object IDs, types, and attribute keys/values.
- Visible state is a tri-state char: `'Y'` (all visible), `'N'` (all invisible), `'P'` (partly). Toggling regenerates GPU buffers.
- View parameters can be saved/loaded as `.azulview` JSON files.
- `BOOL` return values in ObjC wrappers are `YES`/`NO` proper, not `true`/`false`.
