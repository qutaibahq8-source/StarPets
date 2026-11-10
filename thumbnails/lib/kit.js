// Primitive "parts" kit for thumbnail scenes: Roblox-style shapes with
// cartoon outlines (screen-space inverted hull, constant pixel width).
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeVertices } from 'three/addons/utils/BufferGeometryUtils.js';

export const V3 = (x = 0, y = 0, z = 0) => new THREE.Vector3(x, y, z);
const toV = (p) => (p instanceof THREE.Vector3 ? p.clone() : V3(p[0], p[1], p[2]));

// [r,g,b] 0-255 (like Color3.fromRGB), hex number, css string or THREE.Color
export function color(c) {
  if (c instanceof THREE.Color) return c.clone();
  if (Array.isArray(c)) return new THREE.Color().setRGB(c[0] / 255, c[1] / 255, c[2] / 255, THREE.SRGBColorSpace);
  return new THREE.Color(c);
}

// Deterministic RNG so every render of a thumbnail is identical.
export function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const OUTLINE_VERT = /* glsl */ `
uniform float uPx;
uniform vec2 uRes;
void main() {
  vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  vec3 n = normalize(normalMatrix * normal);
  vec2 d = (projectionMatrix * vec4(n, 0.0)).xy;
  float l = length(d);
  if (l > 1e-6) d /= l;
  clip.xy += d * (uPx * 2.0 / uRes) * clip.w;
  gl_Position = clip;
}`;
const OUTLINE_FRAG = /* glsl */ `
uniform vec3 uColor;
void main() { gl_FragColor = vec4(uColor, 1.0); }`;

const SPEC_KEYS = ['color', 'metal', 'rough', 'emissive', 'ei', 'neon', 'glow', 'flat', 'env', 'unlit', 'double', 'opacity'];

export function makeKit({ px = 5, dpr = 1, outlineColor = 0x0d0d16 } = {}) {
  const uRes = { value: new THREE.Vector2(1, 1) };
  const hullMats = new Map();
  const hullGeos = new Map();
  const mats = new Map();
  const geos = new Map();

  const cached = (key, make) => {
    if (!geos.has(key)) geos.set(key, make());
    return geos.get(key);
  };

  function hullMat(p) {
    if (!hullMats.has(p)) {
      hullMats.set(p, new THREE.ShaderMaterial({
        uniforms: { uPx: { value: p * dpr }, uRes, uColor: { value: color(outlineColor) } },
        vertexShader: OUTLINE_VERT,
        fragmentShader: OUTLINE_FRAG,
        side: THREE.BackSide,
      }));
    }
    return hullMats.get(p);
  }

  // Smooth-normal copy of a geometry so the extruded hull has no cracks at hard edges.
  function hullGeo(geo) {
    if (!hullGeos.has(geo.uuid)) {
      let g = geo.clone();
      for (const a of Object.keys(g.attributes)) if (a !== 'position') g.deleteAttribute(a);
      g = mergeVertices(g, 1e-4);
      g.computeVertexNormals();
      hullGeos.set(geo.uuid, g);
    }
    return hullGeos.get(geo.uuid);
  }

  function material(spec) {
    const key = JSON.stringify(spec, (k, v) => (v instanceof THREE.Color ? v.getHexString() : v));
    if (mats.has(key)) return mats.get(key);
    let m;
    if (spec.neon) {
      m = new THREE.MeshBasicMaterial({ color: color(spec.color).multiplyScalar(spec.glow ?? 2.5) });
    } else if (spec.unlit) {
      m = new THREE.MeshBasicMaterial({ color: color(spec.color) });
    } else {
      m = new THREE.MeshStandardMaterial({
        color: color(spec.color ?? [200, 200, 200]),
        roughness: spec.rough ?? 0.5,
        metalness: spec.metal ?? 0,
        emissive: spec.emissive != null ? color(spec.emissive) : new THREE.Color(0),
        emissiveIntensity: spec.ei ?? 1,
        flatShading: !!spec.flat,
        envMapIntensity: spec.env ?? 1,
        side: spec.double ? THREE.DoubleSide : THREE.FrontSide,
      });
    }
    if (spec.opacity != null) { m.transparent = true; m.opacity = spec.opacity; }
    mats.set(key, m);
    return m;
  }

  function place(o, opt) {
    if (opt.pos) o.position.copy(toV(opt.pos));
    if (opt.quat) o.quaternion.copy(opt.quat);
    else if (opt.rot) o.rotation.set(opt.rot[0], opt.rot[1], opt.rot[2]);
    if (opt.scale != null) {
      if (Array.isArray(opt.scale)) o.scale.set(opt.scale[0], opt.scale[1], opt.scale[2]);
      else o.scale.setScalar(opt.scale);
    }
  }

  function group(parent, opt = {}) {
    const g = new THREE.Group();
    place(g, opt);
    parent.add(g);
    if (opt.look) g.lookAt(toV(opt.look));
    return g;
  }

  function mesh(parent, geo, opt = {}) {
    const spec = {};
    for (const k of SPEC_KEYS) if (opt[k] !== undefined) spec[k] = opt[k];
    const m = new THREE.Mesh(geo, material(spec));
    place(m, opt);
    m.castShadow = opt.shadow ?? true;
    m.receiveShadow = opt.receive ?? true;
    if (opt.bloom ?? opt.neon) m.userData.bloom = true;
    parent.add(m);
    if (opt.look) m.lookAt(toV(opt.look));
    if (opt.outline ?? true) {
      const h = new THREE.Mesh(hullGeo(geo), hullMat(opt.outlinePx ?? px));
      h.castShadow = false;
      h.receiveShadow = false;
      m.add(h);
    }
    return m;
  }

  const scaled = (opt, r) => {
    const s = opt.scale;
    if (Array.isArray(s)) return [s[0] * r, s[1] * r, s[2] * r];
    return (s ?? 1) * r;
  };

  return {
    px,
    uRes,
    setResolution(w, h) { uRes.value.set(w, h); },
    material,
    group,
    mesh,
    ball: (p, o) => mesh(p, cached('sphere', () => new THREE.SphereGeometry(1, 48, 32)), { ...o, scale: scaled(o, o.r ?? 1) }),
    cone: (p, o) => mesh(p, cached(`cone${o.r},${o.h},${o.seg}`, () => new THREE.ConeGeometry(o.r, o.h, o.seg ?? 32)), o),
    cyl: (p, o) => mesh(p, cached(`cyl${o.rt ?? o.r},${o.rb ?? o.r},${o.h},${o.seg}`,
      () => new THREE.CylinderGeometry(o.rt ?? o.r, o.rb ?? o.r, o.h, o.seg ?? 32)), o),
    rbox: (p, o) => mesh(p, cached(`rbox${o.size},${o.radius}`,
      () => new RoundedBoxGeometry(o.size[0], o.size[1], o.size[2], 4, o.radius ?? 0.08)), o),
    torus: (p, o) => mesh(p, cached(`torus${o.R},${o.r},${o.arc}`,
      () => new THREE.TorusGeometry(o.R, o.r, 16, 48, o.arc ?? Math.PI * 2)), o),
    tube: (p, o) => mesh(p, new THREE.TubeGeometry(
      new THREE.CatmullRomCurve3(o.points.map(toV)), o.segments ?? 48, o.r, 14, false), o),
    extrude: (p, o) => mesh(p, cached(o.key ?? Math.random(), () => {
      const g = new THREE.ExtrudeGeometry(o.shape, o.extrude);
      if (o.center) g.center();
      return g;
    }), o),
  };
}
