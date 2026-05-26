# ![Icon](https://3d.bk.tudelft.nl/ken/img/azul-small.png) azul

azul is a 3D city model viewer. It is intended for viewing 3D city models in CityGML, CityJSON (including CityJSON Text Sequences), IndoorGML, OBJ, OFF and POLY. It supports loading multiple files, selecting objects by clicking them or selecting them in the sidebar, toggling the visibility of individual items, filtering by level of detail, and browsing their attributes. It is research software, but it is pretty stable and most datasets already work without problems. It is available under the GPLv3 licence.

The current version of azul runs on **macOS 13+** (Apple Silicon and Intel) and **iOS 15+** (iPhone and iPad).

## Controls

### macOS

* Pan: scroll
* Rotate: drag on (left) click, rotate on trackpad
* Zoom: pinch on trackpad, drag on right click
* Select: click on object (in view or sidebar)
* Centre view: double click (in view or sidebar object), h or cmd+shift+h (to dataset centre)

* New file (clear view): n or cmd+n
* Open file (import): o or cmd+o
* Load view (camera) parameters: l or cmd+l
* Save view (camera) parameters: shift+cmd+s
* Export image: cmd+e
* Copy selected object ids: c or cmd+c
* Find objects: f or cmd+f
* Filter by level of detail: click LoD segment in sidebar
* Show bounding box: b or cmd+shift+b
* Show edges: e or cmd+shift+e
* Appearance: select theme in toolbar dropdown
* Preferences: cmd+,
* Object type colours: shift+cmd+c

* Show sidebar: cmd+ctrl+s
* Go full screen: cmd+ctrl+f
* Close window (quits): cmd+w
* Quit: cmd+q

### iOS

* Pan (truck): drag with one finger
* Rotate (orbit): drag with two fingers
* Zoom: pinch
* Twist: rotate two fingers
* Select: tap on object
* Centre view: tap **Centre** (viewfinder) button
* Open file: tap **Open** button
* Browse objects: tap **Objects** (cube) button
* Filter by level of detail: tap **LoD** (± capsule) button

## Download

You can download the latest stable release of azul in the [releases page](https://github.com/tudelft3d/azul/releases) or from the [App Store](https://apps.apple.com/app/azul/id1173239678). If you want more information on how to compile it from source, see below.

![Random3DCity](https://3d.bk.tudelft.nl/ken/img/azul/random.jpg)

![LOD2 example](https://3d.bk.tudelft.nl/ken/img/azul/lod2.jpg)

![Railway](https://3d.bk.tudelft.nl/ken/img/azul/railway.jpg)

![New York City](https://3d.bk.tudelft.nl/ken/img/azul/nyc.jpg)

![Leiden](https://3d.bk.tudelft.nl/ken/img/azul/leiden.jpg)

![Zurich](https://3d.bk.tudelft.nl/ken/img/azul/zurich.jpg)

![iPhone](https://3d.bk.tudelft.nl/ken/img/azul/iphone.jpg)

![iPad](https://3d.bk.tudelft.nl/ken/img/azul/ipad.jpg)

## Technical details

azul is written in a mix of C++17, Swift 5, Objective-C 2 and Objective-C++. The core is written in C++ for future portability, but it uses Apple's Metal for visualisation and SIMD for fast vector/matrix computations. It uses [pugixml](https://pugixml.org) to parse XML, [simdjson](https://github.com/lemire/simdjson) to parse JSON, and the [CGAL](https://www.cgal.org) Triangulation and Polygon repair packages to triangulate concave polygons for display.

## Not implemented / ideas for the future

* Removing (unloading) individual files
* Icons for missing types
* Improved search with live viewing of matching objects
* More complex materials
* Shifting the rotation point out of the data plane
* Using a rotation point at a visible object in the centre (good for zooming in and rotating)
* Showing the data plane and rotation point
* Animations when re-centering
* Keyboard navigation
* QuickLook support
* Icon previews

## Compilation

We have included an Xcode 26 project to easily compile azul, which runs on macOS 26 (Tahoe), but it should open on older versions of Xcode and the compiled application should run on macOS 13.0 or later.

### macOS

Open `azul.xcodeproj` in Xcode, select the **azul** scheme, build and run.

### iOS

Open `azul.xcodeproj` in Xcode, select the **azul-iOS** scheme, build and run on a simulator or a real device.

The iOS target requires static libraries built for the target platform. Prebuilt libraries are provided:
- `libs-ios-device/` — for real devices (iphoneos SDK)
- `libs-ios-sim/` — for the simulator (iphonesimulator SDK)

Copy the appropriate set to `libs-ios/` before building.

azul depends on the following libraries: [Boost](http://www.boost.org), [CGAL](http://www.cgal.org), [GMP](https://gmplib.org), [MPFR](http://www.mpfr.org), [pugixml](http://pugixml.org) and [simdjson](https://github.com/simdjson/simdjson). Most of these can be easily obtained using [Homebrew](http://brew.sh), but we provide fat libraries (arm64 + x86_64) of them all for convenience.

## Licence

azul is available under the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html) licence.
