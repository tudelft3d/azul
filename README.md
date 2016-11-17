# ![Icon](https://3d.bk.tudelft.nl/ken/img/azul-small.png) azul

azul is a CityGML viewer for macOS 10.12, although it also works with minor issues on 10.11. It supports loading multiple files, selecting objects by clicking them or selecting them in the sidebar, and browsing their attributes. It is currently pre-release software, but it is pretty stable and most CityGML datasets already work without problems. It is available under the GPLv3 licence.

## Controls

* Pan: scroll
* Rotate: drag on left click, rotate on trackpad
* Zoom: pinch on trackpad, drag on right click
* Select: click on object (in view or sidebar)
* Centre view: double click (in view or sidebar object), h or cmd+shift+h (to dataset centre)

* New file (clear view): n or cmd+n
* Open file: o or cmd+o
* Show bounding box: b or cmd+shift+b
* Show edges: e or cmd+shift+e
* Toggle Metal/OpenGL rendering: g or cmd+opt+ctrl+g

## Download

You can download the latest stable release of azul in the [releases page](https://github.com/tudelft3d/azul/releases) or from the [App Store](https://itunes.apple.com/app/azul/id1173239678?mt=12). If you want more information on how to compile it from source, see below.

![Random3DCity](https://3d.bk.tudelft.nl/img/2016/azul0.png)

![CityGML 2.0 sample dataset](https://3d.bk.tudelft.nl/img/2016/azul1.png)

![Ettenheim](https://3d.bk.tudelft.nl/img/2016/azul2.png)

![Lyon](https://3d.bk.tudelft.nl/img/2016/azul3.png)

![New York City](https://3d.bk.tudelft.nl/img/2016/azul4.png)

## Technical details

azul is written mostly in Swift 3 and C++11 with a bit of Objective-C and Objective-C++ to bind them together. It uses Metal (when available) or OpenGL (otherwise) for visualisation and simd (with Metal) or GLKit (with OpenGL) for matrix computations. It uses pugixml in order to parse XML since it is much faster than Apple's XMLParser, as well as the CGAL Triangulation package to triangulate concave polygons for display.

## Not implemented / ideas for the future

* Textures: not shown
* Implicit representations: coordinate transformations are not applied
* Support for very big datasets (over around 2 GB): app crashes if any single Metal buffer is > 1 GB
* Shifting the rotation point out of the data plane
* Showing the data plane and rotation point
* Animations when re-centering
* Keyboard navigation
* Sorting and grouping objects in sidebar
* Multi-threaded file loading and ray shooting
* Customising colours
* QuickLook plug-in
* Icon previews
* iOS support

## Compilation

We have included an Xcode 8 project to easily compile azul. Note that older versions of Xcode cannot compile Swift 3.

azul depends on the following libraries: [Boost](http://www.boost.org), [CGAL](http://www.cgal.org), [GMP](https://gmplib.org), [MPFR](http://www.mpfr.org) and [pugixml](http://pugixml.org). These can be easily obtained using [Homebrew](http://brew.sh). However, we also provide bundled versions of the first four for convenience, and pugixml works well as a static library. The provided libraries assume that they will be put into the Frameworks folder in the azul app bundle (i.e. their install names and cross dependencies are set to @rpath/xxx.dylib), but they are otherwise identical to those that can be obtained from Homebrew.

## Licence

In order to comply with the CGAL Triangulation package license, azul is available under the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html) licence.
