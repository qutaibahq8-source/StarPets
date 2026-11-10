// A Roblox-style outdoor stage: blue sky, green grid baseplate, hard sun
// shadows, environment reflections and bloom for neon parts.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { makeKit } from './kit.js';

function skyTexture({ top, horizon, horizonAt }) {
  const c = document.createElement('canvas');
  c.width = 4; c.height = 1024;
  const g = c.getContext('2d');
  const gr = g.createLinearGradient(0, 0, 0, 1024);
  gr.addColorStop(0, top);
  gr.addColorStop(horizonAt, horizon);
  gr.addColorStop(1, horizon);
  g.fillStyle = gr;
  g.fillRect(0, 0, 4, 1024);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// Baseplate: bright green tiles with lighter grid lines.
function gridTexture(renderer, { base, line, tiles = 4, size = 1024 }) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  const step = size / tiles;
  for (let y = 0; y < tiles; y++) {
    for (let x = 0; x < tiles; x++) {
      g.fillStyle = base;
      g.fillRect(x * step, y * step, step, step);
      g.fillStyle = `rgba(0,0,0,${((x * 7 + y * 13) % 5) * 0.008})`;
      g.fillRect(x * step, y * step, step, step);
    }
  }
  g.fillStyle = line;
  const w = size / 110;
  for (let i = 0; i <= tiles; i++) {
    g.fillRect(i * step - w / 2, 0, w, size);
    g.fillRect(0, i * step - w / 2, size, w);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy();
  return t;
}

export function makeStage(canvas, opt) {
  const {
    width, height,
    fov = 30, camPos, target,
    sky = { top: '#2f8ff0', horizon: '#c4ecff', horizonAt: 0.5 },
    ground = { base: '#2db92d', line: '#5fd65a' },
    tile = 2.2,
    sunDir = [-9, 15, 6], sunColor = 0xfff1dc, sunIntensity = 2.6,
    shadowCenter = [0, 0, 0], shadowSize = 9,
    hemi = 1.15, env = 0.55, exposure = 1.0,
    bloom = { strength: 0.35, radius: 0.45, threshold: 0.95 },
    outlinePx = 5,
    fog = [35, 140],
  } = opt;

  const dpr = window.devicePixelRatio || 1;
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, preserveDrawingBuffer: true });
  renderer.setPixelRatio(dpr);
  renderer.setSize(width, height);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.toneMappingExposure = exposure;

  const scene = new THREE.Scene();
  scene.background = skyTexture(sky);
  scene.fog = new THREE.Fog(new THREE.Color(sky.horizon), fog[0], fog[1]);

  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = env;

  const camera = new THREE.PerspectiveCamera(fov, width / height, 0.1, 600);
  camera.position.set(...camPos);
  camera.lookAt(...target);

  scene.add(new THREE.HemisphereLight(0xd6eeff, 0x5f9c3c, hemi));
  const sun = new THREE.DirectionalLight(sunColor, sunIntensity);
  sun.position.set(shadowCenter[0] + sunDir[0], shadowCenter[1] + sunDir[1], shadowCenter[2] + sunDir[2]);
  sun.target.position.set(...shadowCenter);
  sun.castShadow = true;
  sun.shadow.mapSize.set(4096, 4096);
  Object.assign(sun.shadow.camera, { left: -shadowSize, right: shadowSize, top: shadowSize, bottom: -shadowSize, near: 1, far: 80 });
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.025;
    scene.add(sun, sun.target);
  const fill = new THREE.DirectionalLight(0xcfe4ff, 0.55);
  fill.position.set(camPos[0] + 4, camPos[1] + 2, camPos[2] + 6);
  scene.add(fill);

  const gt = gridTexture(renderer, ground);
  const groundSize = 600;
  gt.repeat.set(groundSize / (tile * 4), groundSize / (tile * 4));
  const plane = new THREE.Mesh(
    new THREE.PlaneGeometry(groundSize, groundSize),
    new THREE.MeshStandardMaterial({ map: gt, roughness: 0.92, metalness: 0, envMapIntensity: 0.4 }),
  );
  plane.rotation.x = -Math.PI / 2;
  plane.receiveShadow = true;
  scene.add(plane);

  const kit = makeKit({ px: outlinePx, dpr });
  kit.setResolution(width * dpr, height * dpr);

  // Selective bloom: only objects with userData.bloom (neon parts, sparkles)
  // glow, so sunlit white/gold surfaces stay crisp.
  const W = width * dpr, H = height * dpr;
  let bloomComposer = null;
  if (bloom) {
    bloomComposer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType }));
    bloomComposer.renderToScreen = false;
    bloomComposer.addPass(new RenderPass(scene, camera));
    bloomComposer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), bloom.strength, bloom.radius, 0));
  }
  const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: 4 }));
  composer.addPass(new RenderPass(scene, camera));
  if (bloomComposer) {
    composer.addPass(new ShaderPass(new THREE.ShaderMaterial({
      uniforms: { baseTexture: { value: null }, bloomTexture: { value: bloomComposer.renderTarget2.texture } },
      vertexShader: 'varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }',
      fragmentShader: 'uniform sampler2D baseTexture; uniform sampler2D bloomTexture; varying vec2 vUv;\n'
        + 'void main() { gl_FragColor = texture2D(baseTexture, vUv) + vec4(texture2D(bloomTexture, vUv).rgb, 0.0); }',
    }), 'baseTexture'));
  }
  composer.addPass(new OutputPass());

  function renderBloom() {
    const bg = scene.background;
    scene.background = null;
    const swapped = [], hidden = [];
    scene.traverse((o) => {
      if (o.userData.bloom) return;
      if (o.isMesh && !o.material.isShaderMaterial) { swapped.push([o, o.material]); o.material = DARK; }
      else if ((o.isSprite || o.userData.noBloomPass) && o.visible) { hidden.push(o); o.visible = false; }
    });
    bloomComposer.render();
    for (const [o, m] of swapped) o.material = m;
    for (const o of hidden) o.visible = true;
    scene.background = bg;
  }

  return {
    renderer, scene, camera, kit, sun,
    render() {
      if (bloomComposer) renderBloom();
      composer.render();
    },
  };
}

const DARK = new THREE.MeshBasicMaterial({ color: 0x000000, fog: false });
