#version 120
uniform mat4 mvp;
uniform mat3 m;
attribute vec3 v_coord;
attribute vec3 v_normal;
uniform vec3 v_color;
varying vec3 f_color;

struct lightSource {
  vec4 position;
  vec4 diffuse;
};
lightSource light0 = lightSource(vec4(-1.0, 1.0, 0.0, 0.0),
                                 vec4(1.0, 1.0, 1.0, 1.0));

void main(void) {
  vec3 normalDirection = normalize(m * v_normal);
  vec3 lightDirection = normalize(vec3(light0.position));

  gl_Position = mvp * vec4(v_coord, 1.0);
  f_color = 0.75 * v_color + vec3(light0.diffuse) * v_color * max(0.0, dot(normalDirection, lightDirection));
}
