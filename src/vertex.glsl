#version 120
uniform mat4 m;
uniform mat4 mvp;
uniform mat3 mit;
uniform mat4 vi;
uniform vec3 v_color;
attribute vec3 v_coord;
attribute vec3 v_normal;
varying vec3 f_color;

vec3 lightPosition = vec3(0.0, -1.0, 1.0);

void main(void) {
  mat4 mvp = mvp;
  vec3 normalDirection = normalize(mit * v_normal);
  vec3 viewDirection = normalize(vec3(vi * vec4(0.0, 0.0, 0.0, 1.0) - m * vec4(v_coord, 1.0)));
  vec3 lightDirection = normalize(lightPosition);
  
  vec3 ambient = 1.0 * v_color;
  vec3 diffuse = 0.2 * v_color * max(0.0, dot(normalDirection, lightDirection));
  vec3 specular = 0.2 * v_color * pow(max(0.0, dot(reflect(-lightDirection, normalDirection), viewDirection)), 1.0);
  
  gl_Position = mvp * vec4(v_coord, 1.0);
  f_color = ambient + diffuse + specular;
}
