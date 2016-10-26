#version 120
uniform mat4 mvp;
attribute vec3 coord3d;
uniform vec3 v_color;
varying vec3 f_color;
void main(void) {
  gl_Position = mvp * vec4(coord3d, 1.0);
  f_color = v_color;
}
