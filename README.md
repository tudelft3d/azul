# azul

azul is a CityGML viewer for macOS 10.12, although it works with minor issues on 10.11. It supports loading multiple files, selecting objects by clicking them or selecting them in the sidebar, and browsing their attributes. It is currently pre-release software, but it is pretty stable and most CityGML datasets already work without problems. It is available under the GPLv3 licence.

## Download

You can download the latest stable release of azul in the [releases page](https://github.com/tudelft3d/azul/releases). It should also be available in the App Store in the near future.

![CityGML 2.0 sample dataset](https://3d.bk.tudelft.nl/img/2016/azul1.png)

![Ettenheim](https://3d.bk.tudelft.nl/img/2016/azul2.png)

![Lyon](https://3d.bk.tudelft.nl/img/2016/azul3.png)

![New York City](https://3d.bk.tudelft.nl/img/2016/azul4.png)

## Technical details

azul is written mostly in Swift 3 and C++ with a bit of Objective-C and Objective-C++ to bind them together. It uses Metal (when available) or OpenGL (otherwise) for visualisation and simd (with Metal) or GLKit (with OpenGL) for matrix computations. It uses pugixml in order to parse XML since it is much faster than Apple's XMLParser, as well as the CGAL Triangulation package to triangulate concave polygons for display.

## Compilation

We have included an Xcode 8 project to easily compile azul. In the libs folder there are bundled versions of [Boost](http://www.boost.org), [CGAL](http://www.cgal.org), [GMP](https://gmplib.org) and [MPFR](http://www.mpfr.org). These assume that they will be put into the Frameworks folder in the azul app bundle.

## Licence

In order to comply with the CGAL license, azul is available under the [GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html) licence.