shader_type spatial;
uniform vec2 cl = vec2(0.7656, 0.0497);
uniform vec2 cr = vec2(0.80781, 0.0497);
uniform vec3 iris : source_color = vec3(0.32, 0.2, 0.1);
void fragment() {
	float th = min(distance(UV, cl), distance(UV, cr)) * (20.0 / 0.0012);
	vec3 scl = vec3(0.9, 0.87, 0.84) * (1.0 - smoothstep(30.0, 70.0, th) * 0.25);
	float ang = atan(UV.y - cl.y, UV.x - cl.x);
	float fib = 0.75 + 0.25 * sin(ang * 37.0 + th * 0.7) * sin(ang * 13.0);
	vec3 ir = iris * fib * (0.7 + 0.5 * smoothstep(20.0, 6.0, th));
	ir = mix(ir, ir * 0.35, smoothstep(17.0, 22.0, th));
	vec3 c = mix(ir, scl, smoothstep(21.0, 23.0, th));
	c = mix(vec3(0.01), c, smoothstep(7.0, 8.5, th));
	ALBEDO = c;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
}
