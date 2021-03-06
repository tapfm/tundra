#version 130

#define MAX_LIGHTS 64
#define DEFAULT_HIGHLIGHT 1.0
#define AMBIENT 0.05

in vec3 frag_normal;
in vec3 frag_pos;
in vec2 frag_tex_coord;
in vec3 frag_pos_light_space;
in mat3 tbn_matrix;
flat in int frag_material;

uniform vec3 cam_pos;

uniform vec4 col;
uniform bool texturing;
uniform vec2 tex_start;
uniform vec2 tex_size;
uniform sampler2D tex;

struct Light {
    vec3 pos;
    vec3 dir;
    vec3 col;

    float constant;
    float linear;
    float quadratic;

    float theta;

    bool on;
    bool shadow_mapped;
    bool spotlight;
    bool directional;
};

uniform bool lighting;
uniform Light lights[MAX_LIGHTS];

uniform bool shadow_mapping;
uniform sampler2D depth_map;
uniform vec3 shadow_dir;

uniform int light_count;

uniform float opacity;
uniform bool flash;

struct Material {
  bool map_diff;
  bool map_spec;
  bool map_amb;
  bool map_highlight;
  bool map_bump;

  sampler2D diff_map;
  sampler2D spec_map;
  sampler2D amb_map;
  sampler2D highlight_map;
  
  sampler2D bump_map;
  float bump_param;

  vec3 diff;
  vec3 spec;
  vec3 amb;
  float highlight;
};

uniform bool materialed;
uniform int current_material;
uniform Material material;

out vec4 colour;

float shadow(vec3 normal, vec3 light_dir) {
  vec3 proj = frag_pos_light_space * 0.5 + 0.5;
  if (proj.z > 1.)
    return 0.;
  float current = proj.z;
  float bias = 0.005 * tan(acos(abs(dot(normal, shadow_dir))));
  bias = clamp(bias, 0, 0.01);
  float shadow = 0.0;
  vec2 size = 1.0 / textureSize(depth_map, 0);
  for(int i = -2; i < 2; i++) {
    for(int j = -2; j < 2; j++) {
      float depth = texture(depth_map, proj.xy + vec2(i, j) * size).r;
      shadow += current - bias > depth ? 1.0 : 0.0;
    }
  }
  return shadow / 25.;
}

void main() {
  vec2 material_tex_coord = vec2(frag_tex_coord.x, 1. - frag_tex_coord.y);

  vec3 spec_col;
  vec3 diff_col;
  vec3 amb_col;
  float highlight;
  float final_opacity = opacity;

  if (materialed) {
    if (frag_material != current_material)
      discard;
    if (material.map_diff) {
      vec4 temp = texture(material.diff_map, material_tex_coord);
      diff_col = temp.rgb * temp.a + material.diff * (1. - temp.a);
    } else diff_col = material.diff;
    
    if (material.map_spec) {
      vec4 temp = texture(material.spec_map, material_tex_coord);
      spec_col = temp.rgb * temp.a + material.spec * (1. - temp.a);
    } else spec_col = material.spec;
    
    if (material.map_amb) {
      vec4 temp = texture(material.amb_map, material_tex_coord);
      amb_col = temp.rgb * temp.a + material.amb * (1. - temp.a);
    } else amb_col = material.amb;

    if (material.map_highlight)
      highlight = texture(material.highlight_map, frag_tex_coord).r;
    else highlight = material.highlight;
  } else if (texturing) {
    vec4 temp = texture(tex, tex_start + frag_tex_coord * tex_size);
    if (temp.a != 1.0 && lighting)
      discard;
    else if (temp.a != 1.0)
      final_opacity = temp.a * opacity;
    amb_col = vec3(1.);
    diff_col = temp.rgb;
    spec_col = temp.rgb;
    highlight = DEFAULT_HIGHLIGHT;
  } else {
    amb_col = vec3(1.);
    diff_col = col.rgb;
    spec_col = col.rgb; 
    highlight = DEFAULT_HIGHLIGHT;
  }
  
  if (flash) {
    diff_col = col.rgb * col.a + diff_col * (1. - col.a);
    spec_col = col.rgb * col.a + spec_col * (1. - col.a);
  }

  if (lighting) {
    vec3 temp = AMBIENT * amb_col;
    for(int i = 0; i < light_count; i++) {
      Light light = lights[i];
      if (light.on) {
        vec3 N = normalize(frag_normal);
        if (materialed && material.map_bump) {
          N = normalize(2 * texture(material.bump_map, material_tex_coord).xyz - vec3(1.));
          N = normalize(tbn_matrix * N);
          // colour = vec4(0.5 * N + 0.5, 1.);
          // return;
        }
        vec3 L = normalize(-light.dir);
        if (!light.directional)
          L = normalize(light.pos - frag_pos);
        vec3 V = normalize(cam_pos - frag_pos);
        vec3 R = reflect(-L, N);

        if (light.spotlight && dot(L, normalize(-light.dir)) < cos(light.theta)) {
          continue; 
        } else {
          float distance = length(light.pos - frag_pos);
          float attentuation = 1.0;
          if (!light.directional)
            attentuation = 1.0 / (light.constant + light.linear * distance +
                                           light.quadratic * (distance * distance));

          vec3 diff = light.col * max((dot(N, L)), 0.0) * vec3(diff_col);
          vec3 spec = light.col * pow(max(dot(V, R), 0.0), highlight) * vec3(spec_col);

          float shadow_scalar = 1.;
          if (light.shadow_mapped)
            shadow_scalar = 1. - shadow(N, L);
          temp += attentuation * (diff + spec) * shadow_scalar;
        }
      }
    } 
    
    colour = vec4(temp, 1.);
  } else colour = vec4(diff_col, 1.);
    
  if (!materialed && !lighting && !texturing) {
    colour.a = col.a;
    return;
  } else if (!materialed && !lighting) {
    colour.a = final_opacity;
    return;
  }
}
