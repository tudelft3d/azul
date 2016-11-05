# azul

azul is a CityGML viewer for macOS 11.12. It is available under the GPLv3 licence.

It is written mostly in Swift 3 and C++ with a bit of Objective-C and Objective-C++ to bind them together. In addition to Cocoa, it uses OpenGL for visualisation and GLKit for matrix computations. It uses pugixml in order to parse XML since it is much faster than Apple's XMLParser, as well as the CGAL Triangulation package to triangulate concave polygons for display.
