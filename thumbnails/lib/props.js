// Coins, gems and glow effects for thumbnail scenes.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { V3, color } from './kit.js';

const COIN = {
  gold: { body: [255, 200, 40], face: [255, 226, 110], rim: [255, 180, 20], metal: 0.6, rough: 0.26, emissive: [255, 150, 0], ei: 0.16 },
  dull: { body: [150, 104, 70], face: [128, 86, 56], rim: [120, 82, 52], metal: 0.25, rough: 0.7, emissive: [0, 0, 0], ei: 0 },
};

function starShape(points = 5, ro = 0.5, ri = 0.22) {
  const s = new THREE.Shape();
  for (let i = 0; i < points * 2; i++) {
    const a = Math.PI / 2 + (i * Math.PI) / points;
    const r = i % 2 ? ri : ro;
    const x = Math.cos(a) * r, y = Math.sin(a) * r;
    i ? s.lineTo(x, y) : s.moveTo(x, y);
  }
  s.closePath();
  return s;
}

// Coin with its face normal on local +Y. rot [PI/2,0,0] turns the face to the camera.
export function coin(k, parent, { r = 0.4, pos = [0, 0, 0], rot, quat, style = 'gold' } = {}) {
  const S = COIN[style];
  const mat = { metal: S.metal, rough: S.rough, emissive: S.emissive, ei: S.ei };
  const g = k.group(parent, { pos, rot, quat, scale: r });
  k.cyl(g, { r: 1, h: 0.18, seg: 56, color: S.body, ...mat });
  for (const s of [1, -1]) {
    k.torus(g, { R: 0.88, r: 0.075, pos: [0, s * 0.09, 0], rot: [Math.PI / 2, 0, 0], color: S.rim, ...mat, outline: false, shadow: false });
    k.extrude(g, { key: 'coinStar', shape: starShape(), extrude: { depth: 0.04, bevelEnabled: true, bevelThickness: 0.025, bevelSize: 0.03, bevelSegments: 2 },
      pos: [0, s * 0.085, 0], rot: [-s * Math.PI / 2, 0, 0], color: S.face, ...mat, outline: false, shadow: false });
  }
  return g;
}

// A dome of coins (with a solid gold core so no gaps show).
export function coinPile(k, parent, { center = [0, 0, 0], radius = 1, height = 0.55, count = 60, r = 0.2, rng, gem } = {}) {
  const c = V3(...center);
  k.ball(parent, { r: 1, scale: [radius * 0.93, height * 0.9, radius * 0.93], pos: c, color: [235, 165, 20], metal: 0.5, rough: 0.35, emissive: [255, 130, 0], ei: 0.12 });
  for (let i = 0; i < count; i++) {
    const th = rng() * Math.PI * 2;
    const ct = Math.pow(rng(), 0.8);
    const st = Math.sqrt(1 - ct * ct);
    const n = V3(st * Math.cos(th), ct, st * Math.sin(th));
    const p = c.clone().add(V3(n.x * radius, n.y * height, n.z * radius));
    const normal = V3(n.x / radius, n.y / height, n.z / radius).normalize();
    normal.x += (rng() - 0.5) * 0.7; normal.z += (rng() - 0.5) * 0.7; normal.normalize();
    const q = new THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), normal);
    q.multiply(new THREE.Quaternion().setFromAxisAngle(V3(0, 1, 0), rng() * Math.PI * 2));
    coin(k, parent, { r: r * (0.85 + rng() * 0.3), pos: p, quat: q });
  }
  if (gem) k.group(parent, {}).add(gemMesh(k, { ...gem, pos: c.clone().add(V3(0, height + gem.size * 0.6, 0)) }));
}

// Faceted diamond-cut gem.
let GEM_GEO;
function gemGeometry() {
  if (!GEM_GEO) {
    const crown = new THREE.CylinderGeometry(0.58, 1.0, 0.4, 8, 1);
    crown.translate(0, 0.2, 0);
    const pav = new THREE.ConeGeometry(1.0, 1.1, 8, 1);
    pav.rotateX(Math.PI);
    pav.translate(0, -0.55, 0);
    GEM_GEO = mergeGeometries([crown, pav]);
  }
  return GEM_GEO;
}
export function gemMesh(k, { size = 0.3, color: c = [60, 220, 255], pos = [0, 0, 0], rot = [0, 0.4, 0] } = {}) {
  const holder = new THREE.Group();
  k.mesh(holder, gemGeometry(), { color: c, emissive: c, ei: 0.55, metal: 0.1, rough: 0.06, flat: true, env: 1.8, pos, rot, scale: size });
  return holder;
}
export function gem(k, parent, opt) { const h = gemMesh(k, opt); parent.add(h); return h; }

// ---------------------------------------------------------------- glow sprites
function canvasTex(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
let SPARK, SOFT, RAYS;
const sparkTex = () => SPARK ??= canvasTex(256, (g, s) => {
  const m = s / 2;
  const core = g.createRadialGradient(m, m, 0, m, m, m * 0.5);
  core.addColorStop(0, 'rgba(255,255,255,1)');
  core.addColorStop(0.25, 'rgba(255,255,255,0.6)');
  core.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = core; g.fillRect(0, 0, s, s);
  g.translate(m, m);
  for (const a of [0, Math.PI / 2]) {
    g.save(); g.rotate(a);
    const ray = g.createLinearGradient(-m, 0, m, 0);
    ray.addColorStop(0, 'rgba(255,255,255,0)');
    ray.addColorStop(0.5, 'rgba(255,255,255,1)');
    ray.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = ray;
    g.beginPath(); g.ellipse(0, 0, m, m * 0.06, 0, 0, Math.PI * 2); g.fill();
    g.restore();
  }
});
const softTex = () => SOFT ??= canvasTex(256, (g, s) => {
  const m = s / 2;
  const gr = g.createRadialGradient(m, m, 0, m, m, m);
  gr.addColorStop(0, 'rgba(255,255,255,1)');
  gr.addColorStop(0.35, 'rgba(255,255,255,0.45)');
  gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr; g.fillRect(0, 0, s, s);
});
const raysTex = (n) => RAYS ??= canvasTex(1024, (g, s) => {
  const m = s / 2;
  g.translate(m, m);
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    g.fillStyle = `rgba(255,255,255,${i % 2 ? 0.55 : 1})`;
    g.beginPath(); g.moveTo(0, 0);
    g.arc(0, 0, m, a, a + (Math.PI * 2) / n / 2);
    g.closePath(); g.fill();
  }
  g.globalCompositeOperation = 'destination-in';
  const fade = g.createRadialGradient(0, 0, 0, 0, 0, m);
  fade.addColorStop(0, 'rgba(0,0,0,1)');
  fade.addColorStop(0.15, 'rgba(0,0,0,0.9)');
  fade.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = fade; g.fillRect(-m, -m, s, s);
});

function glowSprite(map, { pos, size, color: c, intensity = 1, rotation = 0 }) {
  const m = new THREE.SpriteMaterial({ map, color: color(c).multiplyScalar(intensity), blending: THREE.AdditiveBlending,
    depthWrite: false, transparent: true, fog: false, rotation });
  const s = new THREE.Sprite(m);
  s.position.copy(Array.isArray(pos) ? V3(...pos) : pos);
  s.scale.setScalar(size);
  return s;
}

export function halo(parent, opt) { const s = glowSprite(softTex(), opt); parent.add(s); return s; }
export function rays(parent, { count = 24, ...opt }) { const s = glowSprite(raysTex(count), opt); parent.add(s); return s; }

export function sparkles(parent, { count = 30, center = [0, 0, 0], box = [4, 3, 2], rng, colors = [[255, 255, 255]], min = 0.15, max = 0.5, intensity = 2.0 }) {
  for (let i = 0; i < count; i++) {
    const p = [center[0] + (rng() - 0.5) * box[0], center[1] + (rng() - 0.5) * box[1], center[2] + (rng() - 0.5) * box[2]];
    const s = glowSprite(sparkTex(), { pos: p, size: min + (max - min) * Math.pow(rng(), 2), color: colors[i % colors.length], intensity, rotation: rng() * 0.6 - 0.3 });
    s.userData.bloom = true;
    parent.add(s);
  }
}

// Glowing rarity ring on the ground.
export function groundRing(k, parent, { pos = [0, 0, 0], R = 1.6, color: c = [255, 210, 60] } = {}) {
  k.torus(parent, { R, r: 0.05, pos: [pos[0], 0.03, pos[2]], rot: [Math.PI / 2, 0, 0], color: c, neon: true, glow: 3.4, outline: false, shadow: false });
  const disc = new THREE.Mesh(new THREE.PlaneGeometry(R * 2.6, R * 2.6), new THREE.MeshBasicMaterial({
    map: softTex(), color: color(c).multiplyScalar(0.5), blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, fog: false }));
  disc.rotation.x = -Math.PI / 2;
  disc.position.set(pos[0], 0.02, pos[2]);
  parent.add(disc);
}
