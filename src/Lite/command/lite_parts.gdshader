// Smoke, fire, sparks and the rest in the command look, on the GPU (phase 4c;
// see LiteParticles.use_gpu). Each particle is one MultiMesh instance written
// once, when it is born: where (the transform's origin), its velocity (the
// x axis), when it was born and how long it lives (the y axis), and in the
// custom data its two sizes, its kind and a number of its own. From its age
// this moves it (every kind's motion has a closed form: straight lines with
// drag, wind, a falling piece's pull) and draws it as pixel art snapped to
// the terrain's grid, as LiteParticles._draw_pixel once did on the CPU.
shader_type canvas_item;
render_mode skip_vertex_transform, unshaded;

uniform float now = 0.0;
uniform float grid = 1.25;

const vec2 WIND = vec2(6.0, -2.5);
const vec2 UP = vec2(-0.42, -0.91);
const vec3 SMOKE_DARK = vec3(0.13, 0.13, 0.14);
const vec3 SMOKE_LIGHT = vec3(0.36, 0.36, 0.38);
const vec3 FIRE_HOT = vec3(1.0, 0.9, 0.55);
const vec3 FIRE_MID = vec3(1.0, 0.5, 0.1);
const vec3 FIRE_COOL = vec3(0.6, 0.1, 0.03);
// LiteParticles' kinds.
const int SMOKE = 0;
const int FIRE = 1;
const int EMBER = 2;
const int SPARK = 3;
const int SHOCK = 4;
const int FLASH = 5;
const int FLAME = 6;
const int DEBRIS = 7;
const int HAZE = 8;

varying vec2 wp;
varying flat vec4 data;   // r0, r1, kind, seed
varying flat vec4 state;  // t, age, centre x, centre y
varying flat vec2 vel;    // its velocity now

void vertex() {
	vec2 p0 = MODEL_MATRIX[3].xy;
	vec2 v0 = MODEL_MATRIX[0].xy;
	float birth = MODEL_MATRIX[1].x;
	float life = MODEL_MATRIX[1].y;
	data = INSTANCE_CUSTOM;
	float age = now - birth;
	float t = age / max(life, 0.0001);
	int kind = int(data.z + 0.5);
	vec2 pos = p0 + v0 * age;
	vec2 v = v0;
	if (kind == SPARK) {
		pos = p0 + v0 * (1.0 - exp(-3.5 * age)) / 3.5;
		v = v0 * exp(-3.5 * age);
	} else if (kind == FIRE) {
		pos = p0 + v0 * (1.0 - exp(-4.0 * age)) / 4.0;
		v = v0 * exp(-4.0 * age);
	} else if (kind == SMOKE || kind == HAZE) {
		pos = p0 + WIND * age + (v0 - WIND) * (1.0 - exp(-0.35 * age)) / 0.35;
	} else if (kind == DEBRIS) {
		vec2 g = 70.0 * UP / 1.2;
		pos = p0 - g * age + (v0 + g) * (1.0 - exp(-1.2 * age)) / 1.2;
		v = (v0 + g) * exp(-1.2 * age) - g;
	}
	float inv = 1.0 - t;
	float r0 = data.x;
	float r1 = data.y;
	// How far it reaches from its centre, to size its quad.
	float ext = grid * 2.0;
	vec2 centre = pos;
	if (kind == SMOKE || kind == HAZE) {
		ext = mix(r0, r1, 1.0 - inv * inv) * 0.62 * 1.3 + grid;
	} else if (kind == FIRE) {
		ext = mix(r0, r1, 1.0 - inv * inv) + grid;
	} else if (kind == FLASH) {
		ext = mix(r0, r1, t) * 0.6 + grid * 1.5;
	} else if (kind == SHOCK) {
		ext = mix(r0, r1, 1.0 - inv * inv * inv) + grid * 1.5;
	} else if (kind == SPARK) {
		ext = max(grid * 1.5, length(v) * 0.03 + grid * 1.5);
	} else if (kind == DEBRIS) {
		ext = 6.5;
	} else if (kind == FLAME) {
		float rise = min(1.0, t * 4.0) * (1.0 - t * t);
		centre = pos + UP * r1 * rise * 0.5;
		ext = r0 + grid;
	}
	state = vec4(t, age, centre);
	vel = v;
	if (age < 0.0 || t >= 1.0 || life <= 0.0) {
		// Not alive: a quad of no size, far off.
		VERTEX = vec2(-100000.0);
	} else {
		VERTEX = centre + VERTEX * 2.0 * ext;
	}
	wp = VERTEX;
}

// Inside a square of half-size `r` round `p`, snapped to the grid (as LiteParticles._sq).
bool sq(vec2 q, vec2 p, float r) {
	float h = max(grid * 0.5, round(r / grid) * grid);
	vec2 c = floor(p / grid) * grid;
	return q.x >= c.x - h && q.x < c.x + h && q.y >= c.y - h && q.y < c.y + h;
}

float flicker(float seed) {
	return 0.55 + 0.45 * sin(now * 17.0 + seed * 2.3) * sin(now * 7.0 + seed);
}

void fragment() {
	// The pixel this fragment is in.
	vec2 q = floor(wp / grid) * grid + grid * 0.5;
	float t = state.x;
	float inv = 1.0 - t;
	vec2 p = state.zw;
	float r0 = data.x;
	float r1 = data.y;
	int kind = int(data.z + 0.5);
	float seed = data.w;
	vec4 col = vec4(0.0);
	if (kind == SMOKE || kind == HAZE) {
		float a = min(1.0, t * 12.0) * pow(inv, 1.5) * 0.55;
		float r = mix(r0, r1, 1.0 - inv * inv) * 0.62;
		vec3 tone = t < 0.33 ? SMOKE_DARK : (t < 0.66 ? mix(SMOKE_DARK, SMOKE_LIGHT, 0.5) : SMOKE_LIGHT);
		float ang = mod(seed, 7.0) * 0.9;
		vec2 o = vec2(cos(ang), sin(ang)) * r * 0.45;
		if (sq(q, p + vec2(-r * 0.2, -r * 0.3), r * 0.4)) {
			col = vec4(tone + (1.0 - tone) * 0.12, a);
		} else if (sq(q, p + o, r * 0.6) || sq(q, p - o, r * 0.6) || sq(q, p + vec2(o.y, -o.x), r * 0.5)) {
			col = vec4(tone * 0.75, a);
		}
	} else if (kind == FIRE) {
		vec3 c = t < 0.2 ? FIRE_HOT : (t < 0.55 ? FIRE_MID : FIRE_COOL);
		float r = mix(r0, r1, 1.0 - inv * inv);
		if (t < 0.5 && sq(q, p + vec2(0.0, -r * 0.3), r * 0.45)) {
			col = vec4(FIRE_HOT, 0.9 * inv);
		} else if (sq(q, p, r)) {
			col = vec4(c, 0.95 * inv);
		}
	} else if (kind == FLASH) {
		float r = mix(r0, r1, t) * 0.6;
		float h = max(grid, round(r * 0.35 / grid) * grid);
		vec2 d = q - floor(p / grid) * grid;
		if ((abs(d.x) <= r && abs(d.y) <= h * 0.5) || (abs(d.x) <= h * 0.5 && abs(d.y) <= r)) {
			col = vec4(1.0, 0.97, 0.85, 0.95 * inv);
		}
	} else if (kind == EMBER) {
		if (sq(q, p, grid * 0.5)) {
			col = vec4(1.0, 0.6, 0.2, 0.9 * flicker(seed) * min(1.0, inv * 3.0));
		}
	} else if (kind == SPARK) {
		vec3 c = t < 0.4 ? FIRE_HOT : FIRE_MID;
		if (sq(q, p, grid * 0.5)) {
			col = vec4(c, inv);
		} else if (sq(q, p - vel * 0.03, grid * 0.5)) {
			col = vec4(c, inv * 0.5);
		}
	} else if (kind == DEBRIS) {
		vec2 back = normalize(vel + vec2(0.0001));
		if (sq(q, p, grid * 0.75)) {
			col = vec4(1.0, 0.65, 0.25, 0.95 * inv);
		} else {
			for (int k = 0; k < 3; k++) {
				if (sq(q, p - back * float(k) * 2.5, grid * 0.5)) {
					col = vec4(0.45, 0.45, 0.48, 0.6 * inv * (1.0 - float(k) / 3.0));
					break;
				}
			}
		}
	} else if (kind == SHOCK) {
		float r = mix(r0, r1, 1.0 - inv * inv * inv);
		float n = clamp(floor(r * 0.9), 6.0, 28.0);
		vec2 d = q - p;
		float k = round(atan(d.y, d.x) / (6.2831853 / n));
		float a = k * 6.2831853 / n;
		if (sq(q, p + vec2(cos(a), sin(a)) * r, grid * 0.5)) {
			col = vec4(1.0, 0.92, 0.8, 0.6 * inv * inv);
		}
	} else if (kind == FLAME) {
		float rise = min(1.0, t * 4.0) * (1.0 - t * t);
		vec3 c = t < 0.5 ? FIRE_MID : FIRE_COOL;
		if (sq(q, p, r0 * (0.6 + 0.4 * rise))) {
			col = vec4(c, 0.9 * (1.0 - t));
		}
	}
	if (col.a <= 0.003) {
		discard;
	}
	COLOR = col;
}
