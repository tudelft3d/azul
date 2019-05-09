// azul
// Copyright © 2016-2019 Ken Arroyo Ohori
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef ENHANCED_TRIANGULATION_2_H
#define ENHANCED_TRIANGULATION_2_H

template <class T>
class Enhanced_constrained_triangulation_2;

template <class T>
class Is_Delaunay {
public:
  typedef T Triangulation;
  typedef typename Triangulation::List_edges List_edges;
  
  static void if_Delaunay_make_Delaunay(Enhanced_constrained_triangulation_2<T> &et, List_edges &e) {
    std::cout << "Unknown triangulation: cannot make Delaunay" << std::endl;
  }
};

template <class K, class TDS, class Itag>
class Is_Delaunay<CGAL::Constrained_Delaunay_triangulation_2<K, TDS, Itag> > {
public:
  typedef CGAL::Constrained_Delaunay_triangulation_2<K, TDS, Itag> Triangulation;
  typedef typename Triangulation::List_edges List_edges;
  
  static void if_Delaunay_make_Delaunay(Enhanced_constrained_triangulation_2<Triangulation> &et, List_edges &e) {
    et.propagating_flip(e);
  }
};

template <class K, class TDS, class Itag>
class Is_Delaunay<CGAL::Constrained_triangulation_2<K, TDS, Itag> > {
public:
  typedef CGAL::Constrained_triangulation_2<K, TDS, Itag> Triangulation;
  typedef typename Triangulation::List_edges List_edges;
  
  static void if_Delaunay_make_Delaunay(Enhanced_constrained_triangulation_2<Triangulation> &et, List_edges &e) {
    // Do nothing
  }
};

template <class T>
class Enhanced_constrained_triangulation_2 : public T {
public:
  typedef typename T::Point Point;
  typedef typename T::Vertex Vertex;
  typedef typename T::Edge Edge;
  typedef typename T::Vertex_handle Vertex_handle;
  typedef typename T::Face_handle Face_handle;
  typedef typename T::Locate_type Locate_type;
  typedef typename T::List_faces List_faces;
  typedef typename T::List_edges List_edges;
  
  Vertex_handle insert(const Point &p, Face_handle f = Face_handle()) {
    // std::cout << "Enhanced_triangulation_2::insert(const Point &, Face_handle)" << std::endl;
    Locate_type location_type;
    int location_vertex;
    Face_handle location = T::locate(p, location_type, location_vertex, f);
    return insert(p, location_type, location, location_vertex);
  }
  
  Vertex_handle insert(const Point &p, Locate_type &lt, Face_handle loc, int li) {
    // std::cout << "Enhanced_triangulation_2::insert(const Point &, Locate_type &, Face_handle, int)" << std::endl;
    // TODO: Read and reset info on faces & edges that are split because of the insertion
    return T::insert(p, lt, loc, li);
  }
  
  void odd_even_insert_constraint(const Point& a, const Point& b) {
    Vertex_handle va = insert(a);
    Vertex_handle vb = insert(b);
    if (va != vb) odd_even_insert_constraint(va, vb);
  }
  
  void odd_even_insert_constraint(Vertex_handle va, Vertex_handle vb) {
    CGAL_triangulation_precondition(va != vb);
    
//    std::cout << "Triangulation:" << std::endl;
//    for (typename T::All_faces_iterator current_face = T::all_faces_begin(); current_face != T::all_faces_end(); ++current_face) {
//      std::cout << "\tTriangle [0]: " << current_face->vertex(0)->point() << " [1]: " << current_face->vertex(1)->point() << " [2]: " << current_face->vertex(2)->point() << std::endl;
//    } std::cout.precision(15);
//    std::cout << "Adding constraint from " << va->point() << " to " << vb->point() << std::endl;
    
    // If [va, vb] lies on an existing edge
    Vertex_handle vertex_on_other_end;
    Face_handle incident_face;
    int vertex_opposite_to_incident_edge;
    if (T::includes_edge(va, vb, vertex_on_other_end, incident_face, vertex_opposite_to_incident_edge)) {
      if (T::is_constrained(Edge(incident_face, vertex_opposite_to_incident_edge))) {
        T::remove_constrained_edge(incident_face, vertex_opposite_to_incident_edge);
        if (T::number_of_faces() == 0) return;
        List_edges possibly_non_Delaunay_edges;
        possibly_non_Delaunay_edges.push_back(Edge(incident_face, vertex_opposite_to_incident_edge));
        Is_Delaunay<T>::if_Delaunay_make_Delaunay(*this, possibly_non_Delaunay_edges);
      } else T::mark_constraint(incident_face, vertex_opposite_to_incident_edge);
      if (vertex_on_other_end != vb) odd_even_insert_constraint(vertex_on_other_end, vb);
      return;
    }
    
    // If [va, vb] intersects a constrained edge or an existing vertex
    List_faces intersected_faces;
    List_edges conflict_boundary_ab, conflict_boundary_ba;
    Vertex_handle intersection;
    if (T::find_intersected_faces(va, vb, intersected_faces, conflict_boundary_ab, conflict_boundary_ba, intersection)) {
      if (intersection != va && intersection != vb) {
        odd_even_insert_constraint(va, intersection);
        odd_even_insert_constraint(intersection, vb);
      } else odd_even_insert_constraint(va, vb);
      return;
    }
    
    // Otherwise
    T::triangulate_hole(intersected_faces, conflict_boundary_ab, conflict_boundary_ba);
    if (intersection != vb) {
      odd_even_insert_constraint(intersection, vb);
    }
  }
};

#endif
