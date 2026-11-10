// Chibi pets built from primitive parts, in the spirit of src/Server/PetModels.lua
// (big glossy eyes with two shines, blush cheeks, part-built bodies).
// Every builder returns a Group that faces +Z with its feet on y = 0.
import * as THREE from 'three';
import { V3 } from './kit.js';

const WHITE = [255, 255, 255];
const UP = V3(0, 1, 0);

function face(k, g, { c, R, iris = [40, 30, 80], irisLight, spread = 0.4, eyeY = 0.06, eyeScale = 1,
  blush = true, mouth = 'smile', mouthAt, mouthR = 1 }) {
  for (const s of [1, -1]) {
    const dir = V3(s * spread, eyeY, 0.92).normalize();
    const eg = k.group(g, { pos: c.clone().addScaledVector(dir, R * 0.9), look: c.clone().addScaledVector(dir, R * 3) });
    const e = R * eyeScale;
    k.ball(eg, { r: 1, scale: [0.25 * e, 0.3 * e, 0.14 * e], color: WHITE, rough: 0.25, outlinePx: k.px * 0.75 });
    k.ball(eg, { r: 1, scale: [0.185 * e, 0.225 * e, 0.1 * e], pos: [0, -0.012 * e, 0.065 * e], color: iris, rough: 0.55, env: 0.15, outline: false });
    if (irisLight) k.ball(eg, { r: 1, scale: [0.12 * e, 0.075 * e, 0.03 * e], pos: [0, -0.12 * e, 0.148 * e], color: irisLight, rough: 0.6, env: 0.2, outline: false, shadow: false });
    k.ball(eg, { r: 1, scale: [0.07 * e, 0.08 * e, 0.03 * e], pos: [0.065 * e, 0.09 * e, 0.155 * e], color: WHITE, unlit: true, outline: false, shadow: false });
    k.ball(eg, { r: 1, scale: [0.034 * e, 0.034 * e, 0.02 * e], pos: [-0.065 * e, -0.065 * e, 0.15 * e], color: WHITE, unlit: true, outline: false, shadow: false });
  }
  if (blush) {
    for (const s of [1, -1]) {
      const dir = V3(s * 0.62, -0.2, 0.76).normalize();
      const bg = k.group(g, { pos: c.clone().addScaledVector(dir, R * 0.985), look: c.clone().addScaledVector(dir, R * 3) });
      k.ball(bg, { r: 1, scale: [0.15 * R, 0.08 * R, 0.035 * R], color: [255, 140, 165], rough: 0.8, outline: false, shadow: false });
    }
  }
  if (mouth) {
    const at = mouthAt ?? c.clone().addScaledVector(V3(0, -0.36, 0.93).normalize(), R * 0.995);
    const mg = k.group(g, { pos: at, look: at.clone().add(V3(0, -0.15, 1)) });
    const mr = 0.085 * R * mouthR;
    const tube = { r: mr * 0.22, R: mr, arc: Math.PI, rot: [0, 0, Math.PI], color: [70, 30, 45], rough: 0.6, outline: false, shadow: false };
    if (mouth === 'w') {
      k.torus(mg, { ...tube, pos: [mr, 0, 0] });
      k.torus(mg, { ...tube, pos: [-mr, 0, 0] });
    } else {
      k.torus(mg, tube);
    }
  }
}

function ear(k, g, { pos, rot, r, h, color, inner }) {
  const eg = k.group(g, { pos, rot });
  k.cone(eg, { r, h, pos: [0, h / 2, 0], color });
  if (inner) {
    const ig = k.group(eg, { pos: [0, h * 0.04, r * 0.62], rot: [-Math.atan(r / h), 0, 0] });
    k.cone(ig, { r: r * 0.55, h: h * 0.72, pos: [0, h * 0.36, 0], scale: [1, 1, 0.32], color: inner, outline: false, shadow: false });
  }
}

// Orient +Y of a part along a direction.
const along = (d) => new THREE.Quaternion().setFromUnitVectors(UP, d.clone().normalize());

// Balls along a curve with tapering radius (tails, serpent bodies).
function chain(k, g, { points, n, r0, r1, color, ...rest }) {
  const curve = new THREE.CatmullRomCurve3(points.map((p) => V3(...p)));
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    k.ball(g, { r: r0 + (r1 - r0) * t, pos: curve.getPoint(t), color, ...rest });
  }
  return curve;
}

// ------------------------------------------------------------------ KITTEN
export function kitten(k, { color = [168, 172, 180], light = [228, 230, 236], iris = [60, 150, 90], earIn = [255, 175, 195] } = {}) {
  const g = new THREE.Group();
  const H = V3(0, 1.3, 0.14), R = 0.64;
  k.ball(g, { r: 0.5, scale: [1.0, 0.88, 1.18], pos: [0, 0.6, -0.2], color });
  k.ball(g, { r: 0.34, scale: [0.95, 0.95, 0.6], pos: [0, 0.6, 0.12], color: light });
  for (const [x, z] of [[0.24, 0.1], [-0.24, 0.1], [0.27, -0.5], [-0.27, -0.5]]) {
    k.cyl(g, { rt: 0.13, rb: 0.14, h: 0.34, pos: [x, 0.2, z], color });
    k.ball(g, { r: 0.15, scale: [1, 0.62, 1.15], pos: [x, 0.07, z + 0.03], color: light });
  }
  k.tube(g, { points: [[0, 0.62, -0.72], [0.18, 0.95, -0.98], [0.1, 1.38, -0.92], [-0.12, 1.52, -0.72]], r: 0.09, color });
  k.ball(g, { r: 0.12, pos: [-0.12, 1.52, -0.72], color: light });
  k.ball(g, { r: R, scale: [1.08, 0.96, 1], pos: H, color });
  for (const s of [1, -1]) {
    ear(k, g, { pos: [s * 0.36, H.y + 0.42, H.z - 0.08], rot: [0.0, 0, -s * 0.36], r: 0.22, h: 0.42, color, inner: earIn });
  }
  const snout = H.clone().add(V3(0, -0.2, 0.5));
  k.ball(g, { r: 0.2, scale: [1.3, 0.85, 0.8], pos: snout, color: light, outline: false });
  k.ball(g, { r: 0.06, scale: [1.2, 0.85, 0.9], pos: snout.clone().add(V3(0, 0.08, 0.15)), color: [255, 140, 170], outline: false });
  face(k, g, { c: H, R, iris, irisLight: [150, 230, 170], spread: 0.42, eyeY: 0.1, mouth: 'w',
    mouthAt: snout.clone().add(V3(0, -0.04, 0.16)), mouthR: 0.75 });
  return g;
}

// ------------------------------------------------------------------ DRAGON
function wingShape() {
  const s = new THREE.Shape();
  s.moveTo(0, 0);
  s.lineTo(0.35, 0.75);
  s.lineTo(1.15, 1.45);
  s.lineTo(1.95, 1.05);
  s.quadraticCurveTo(1.55, 0.85, 1.62, 0.4);
  s.quadraticCurveTo(1.25, 0.45, 1.08, 0.0);
  s.quadraticCurveTo(0.6, 0.25, 0.0, -0.12);
  s.closePath();
  return s;
}

export function dragon(k, {
  color = [255, 204, 42], light = [255, 238, 170], neon = [70, 235, 255], horn = [255, 248, 228], iris = [40, 25, 95],
  membrane = [118, 48, 235],
} = {}) {
  const g = new THREE.Group();
  const gold = { color, metal: 0.55, rough: 0.36, emissive: [255, 150, 0], ei: 0.04, env: 0.95 };
  const pale = { color: light, metal: 0.15, rough: 0.45, emissive: [255, 190, 60], ei: 0.05 };
  const H = V3(0, 2.0, 0.28), R = 0.8;

  // wings (behind everything)
  for (const s of [1, -1]) {
    const wg = k.group(g, { pos: [s * 0.4, 1.32, -0.52], rot: [-0.12, s * 0.42, s * 0.2], scale: [s, 1, 1] });
    k.extrude(wg, { key: 'wing', shape: wingShape(), extrude: { depth: 0.05, bevelEnabled: false }, pos: [0, 0, -0.025],
      color: membrane, emissive: membrane, ei: 0.3, rough: 0.5, double: true });
    for (const tip of [[1.15, 1.45], [1.95, 1.05], [1.62, 0.4], [1.08, 0.0]]) {
      const mid = tip[0] === 1.15 ? [0.35, 0.75, 0.03] : [tip[0] * 0.5, tip[1] * 0.5, 0.03];
      k.tube(wg, { points: [[0, 0, 0.03], mid, [tip[0], tip[1], 0.03]], r: 0.042, segments: 16, ...gold });
      k.ball(wg, { r: 0.075, pos: [tip[0], tip[1], 0.03], ...gold });
    }
  }

  // tail
  const tail = chain(k, g, { points: [[0, 0.6, -0.85], [0.6, 0.42, -1.25], [1.2, 0.55, -1.2], [1.55, 0.95, -0.85], [1.6, 1.32, -0.5]],
    n: 13, r0: 0.3, r1: 0.09, ...gold });
  const tEnd = tail.getPoint(1), tDir = tail.getTangent(1);
  k.cone(g, { r: 0.2, h: 0.36, seg: 4, pos: tEnd.clone().addScaledVector(tDir, 0.18), quat: along(tDir), scale: [1, 1, 0.45], color: neon, neon: true, glow: 3.2 });

  // body, belly, legs
  const B = V3(0, 0.9, -0.15);
  k.ball(g, { r: 0.74, scale: [1.05, 0.95, 1.12], pos: B, ...gold });
  k.ball(g, { r: 0.55, scale: [0.8, 0.88, 0.5], pos: [0, 0.84, 0.32], ...pale });
  for (let i = 0; i < 3; i++) {
    k.torus(g, { R: 0.36 - i * 0.04, r: 0.018, arc: Math.PI * 0.9, pos: [0, 1.08 - i * 0.2, 0.55 - i * 0.012], rot: [0.12, 0, Math.PI * 1.05],
      color: [230, 170, 60], rough: 0.5, outline: false, shadow: false });
  }
  for (const s of [1, -1]) {
    k.ball(g, { r: 0.34, scale: [0.8, 1, 1.1], pos: [s * 0.58, 0.45, -0.25], ...gold });
    k.ball(g, { r: 0.22, scale: [1, 0.55, 1.45], pos: [s * 0.6, 0.11, -0.02], ...gold });
    for (const cx of [-0.08, 0, 0.08]) {
      k.cone(g, { r: 0.04, h: 0.1, pos: [s * 0.6 + cx, 0.08, 0.3], rot: [Math.PI / 2, 0, 0], color: horn, rough: 0.35, outlinePx: k.px * 0.6 });
    }
    k.ball(g, { r: 0.17, scale: [1, 1.45, 1], pos: [s * 0.44, 0.55, 0.44], rot: [0.3, 0, s * 0.35], ...gold });
    k.ball(g, { r: 0.15, scale: [1.05, 0.85, 1.1], pos: [s * 0.47, 0.32, 0.55], ...gold });
  }

  // back spines
  for (const b of [0.85, 1.25, 1.65, 2.05]) {
    const p = B.clone().add(V3(0, Math.cos(b) * 0.7, -Math.sin(b) * 0.82));
    k.cone(g, { r: 0.13, h: 0.3, pos: p, rot: [-b, 0, 0], color: neon, neon: true, glow: 3.2 });
  }

  // head
  k.ball(g, { r: R, scale: [1.08, 0.95, 1], pos: H, ...gold });
  for (const a of [0.3, 0.72, 1.12]) {
    const d = V3(0, Math.cos(a), -Math.sin(a));
    k.cone(g, { r: 0.12, h: 0.32, pos: H.clone().addScaledVector(d, R * 0.93), rot: [-a, 0, 0], color: neon, neon: true, glow: 3.2 });
  }
  for (const s of [1, -1]) {
    const hg = k.group(g, { pos: H.clone().add(V3(s * 0.44, 0.52, -0.22)), rot: [-0.55, 0, -s * 0.32] });
    k.cone(hg, { r: 0.14, h: 0.64, pos: [0, 0.3, 0], color: horn, rough: 0.35 });
    k.torus(hg, { R: 0.12, r: 0.035, pos: [0, 0.08, 0], rot: [Math.PI / 2, 0, 0], color: neon, neon: true, glow: 3.0, outline: false });
    k.cone(g, { r: 0.13, h: 0.4, seg: 24, pos: H.clone().add(V3(s * 0.86, 0.02, -0.12)), rot: [0, 0, -s * 1.15], scale: [1, 1, 0.45], ...gold });
  }
  const snout = H.clone().add(V3(0, -0.3, 0.62));
  k.ball(g, { r: 0.42, scale: [1.12, 0.76, 0.92], pos: snout, ...pale });
  for (const s of [1, -1]) {
    k.ball(g, { r: 0.045, scale: [1.3, 0.8, 0.8], pos: snout.clone().add(V3(s * 0.13, 0.13, 0.33)), color: [120, 70, 20], outline: false, shadow: false });
  }
  k.cone(g, { r: 0.045, h: 0.11, pos: snout.clone().add(V3(0.14, -0.2, 0.3)), rot: [Math.PI, 0, 0], color: WHITE, outlinePx: k.px * 0.6 });
  face(k, g, { c: H, R, iris, irisLight: [130, 110, 255], spread: 0.4, eyeY: 0.14, eyeScale: 1.05,
    mouthAt: snout.clone().add(V3(0, -0.13, 0.36)), mouthR: 1.1 });
  return g;
}

// ------------------------------------------------------------------ UNICORN
export function unicorn(k, { color = [250, 247, 255], muzzle = [255, 228, 240], hoof = [255, 200, 70], horn = [255, 215, 80], iris = [110, 50, 170] } = {}) {
  const g = new THREE.Group();
  const coat = { color, rough: 0.45 };
  const rainbow = [[255, 90, 170], [255, 150, 60], [255, 225, 60], [80, 230, 120], [60, 200, 255], [150, 100, 255]];
  for (const [x, z] of [[0.3, 0.2], [-0.3, 0.2], [0.3, -0.62], [-0.3, -0.62]]) {
    k.cyl(g, { rt: 0.13, rb: 0.12, h: 0.7, pos: [x, 0.45, z], ...coat });
    k.cyl(g, { r: 0.145, h: 0.16, pos: [x, 0.08, z], color: hoof, metal: 0.5, rough: 0.3 });
  }
  k.ball(g, { r: 0.6, scale: [0.95, 0.82, 1.28], pos: [0, 1.0, -0.22], ...coat });
  chain(k, g, { points: [[0, 1.15, -0.95], [0.1, 1.05, -1.3], [0.2, 0.7, -1.45], [0.12, 0.42, -1.4]], n: 7, r0: 0.2, r1: 0.12,
    color: rainbow[4], emissive: rainbow[4], ei: 0.35, rough: 0.4 });
  k.ball(g, { r: 0.33, scale: [1, 1.45, 1], pos: [0, 1.45, 0.22], rot: [0.45, 0, 0], ...coat });
  const H = V3(0, 1.98, 0.42), R = 0.56;
  k.ball(g, { r: R, scale: [1, 0.95, 1.06], pos: H, ...coat });
  const mz = H.clone().add(V3(0, -0.24, 0.42));
  k.ball(g, { r: 0.32, scale: [1.08, 0.82, 0.95], pos: mz, color: muzzle, rough: 0.45 });
  for (const s of [1, -1]) {
    k.ball(g, { r: 0.04, pos: mz.clone().add(V3(s * 0.12, 0.06, 0.29)), color: [200, 110, 150], outline: false, shadow: false });
    ear(k, g, { pos: H.clone().add(V3(s * 0.27, 0.4, -0.16)), rot: [-0.15, 0, -s * 0.3], r: 0.11, h: 0.3, color, inner: [255, 190, 215] });
  }
  for (let i = 0; i < 6; i++) {
    const t = i / 5;
    const p = V3(0, 2.48 - t * 1.1, 0.14 - t * 0.38 + Math.sin(t * 3) * 0.08);
    k.ball(g, { r: 0.2 - t * 0.03, pos: p, color: rainbow[i], emissive: rainbow[i], ei: 0.35, rough: 0.4 });
  }
  const hg = k.group(g, { pos: H.clone().add(V3(0, 0.5, 0.2)), rot: [0.38, 0, 0] });
  k.cone(hg, { r: 0.11, h: 0.78, pos: [0, 0.39, 0], color: horn, neon: true, glow: 3.0 });
  for (let i = 0; i < 3; i++) {
    k.torus(hg, { R: 0.09 - i * 0.024, r: 0.022, pos: [0, 0.14 + i * 0.2, 0], rot: [Math.PI / 2 + 0.25, 0, 0], color: [255, 245, 200], neon: true, glow: 2.6, outline: false });
  }
  face(k, g, { c: H, R, iris, irisLight: [210, 150, 255], spread: 0.44, eyeY: 0.18, eyeScale: 1.05,
    mouthAt: mz.clone().add(V3(0, -0.12, 0.28)), mouthR: 1.0 });
  return g;
}

// ------------------------------------------------------------------ VOID SERPENT
export function serpent(k, { color = [110, 50, 210], belly = [200, 160, 255], neon = [255, 70, 230], iris = [255, 60, 220], rings } = {}) {
  const g = new THREE.Group();
  const skin = { color, rough: 0.35, metal: 0.15, emissive: [70, 0, 160], ei: 0.25 };
  const pts = [[0.95, 0.12, 0.55], [0.25, 0.2, 0.98], [-0.6, 0.26, 0.62], [-0.88, 0.3, -0.2], [-0.3, 0.33, -0.78],
    [0.52, 0.38, -0.6], [0.78, 0.55, 0.05], [0.38, 0.98, 0.32], [0.08, 1.5, 0.3], [0, 1.88, 0.28]];
  const curve = chain(k, g, { points: pts, n: 64, r0: 0.08, r1: 0.31, ...skin });
  for (let i = 1; i <= 6; i++) {
    const t = 0.22 + i * 0.11;
    const r = 0.08 + 0.23 * t;
    k.torus(g, { R: r * 1.0, r: 0.035, pos: curve.getPoint(t), quat: new THREE.Quaternion().setFromUnitVectors(V3(0, 0, 1), curve.getTangent(t)),
      color: rings ? rings[(i - 1) % rings.length] : neon, neon: true, glow: 1.5, outline: false });
  }
  const H = V3(0, 2.12, 0.4), R = 0.5;
  k.ball(g, { r: 0.8, scale: [1.05, 1.1, 0.13], pos: [0, 2.0, 0.02], color: neon, emissive: neon, ei: 0.9, rough: 0.4 });
  k.ball(g, { r: 0.62, scale: [1.0, 1.05, 0.14], pos: [0, 1.98, 0.06], color: [60, 20, 120], rough: 0.4, outline: false });
  k.ball(g, { r: R, scale: [1.12, 0.95, 1.0], pos: H, ...skin });
  const snout = H.clone().add(V3(0, -0.3, 0.33));
  k.ball(g, { r: 0.27, scale: [1.25, 0.6, 0.95], pos: snout, color: belly, rough: 0.4 });
  for (const s of [1, -1]) {
    k.ball(g, { r: 0.035, scale: [1.3, 0.8, 0.8], pos: snout.clone().add(V3(s * 0.1, 0.1, 0.22)), color: [60, 20, 90], outline: false, shadow: false });
    k.cone(g, { r: 0.045, h: 0.14, pos: snout.clone().add(V3(s * 0.11, -0.16, 0.17)), rot: [Math.PI + 0.15, 0, 0], color: WHITE, outlinePx: k.px * 0.6 });
    k.cone(g, { r: 0.075, h: 0.34, pos: H.clone().add(V3(s * 0.27, 0.36, -0.18)), rot: [-1.05, 0, -s * 0.25], color: neon, neon: true, glow: 2.0 });
  }
  face(k, g, { c: H, R, iris, irisLight: [255, 190, 250], spread: 0.46, eyeY: 0.14, eyeScale: 1.15, mouth: 'smile',
    mouthAt: snout.clone().add(V3(0, -0.06, 0.25)), mouthR: 1.0 });
  return g;
}
