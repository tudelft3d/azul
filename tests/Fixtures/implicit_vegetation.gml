<?xml version="1.0" encoding="UTF-8"?>
<CityModel xmlns="http://www.opengis.net/citygml/2.0"
           xmlns:veg="http://www.opengis.net/citygml/vegetation/2.0"
           xmlns:gml="http://www.opengis.net/gml"
           xmlns:xlink="http://www.w3.org/1999/xlink">
  <gml:Polygon gml:id="template-poly-1">
    <gml:exterior>
      <gml:LinearRing>
        <gml:posList srsDimension="3">0.0 0.0 0.0 1.0 0.0 0.0 1.0 1.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0</gml:posList>
      </gml:LinearRing>
    </gml:exterior>
  </gml:Polygon>
  <cityObjectMember>
    <veg:SolitaryVegetationObject gml:id="veg-1">
      <veg:lod2ImplicitRepresentation>
        <gml:ImplicitGeometry>
          <gml:transformationMatrix>1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1</gml:transformationMatrix>
          <gml:referencePoint>
            <gml:Point>
              <gml:pos>10.0 20.0 30.0</gml:pos>
            </gml:Point>
          </gml:referencePoint>
          <gml:relativeGMLGeometry xlink:href="#template-poly-1"/>
        </gml:ImplicitGeometry>
      </veg:lod2ImplicitRepresentation>
    </veg:SolitaryVegetationObject>
  </cityObjectMember>
</CityModel>
