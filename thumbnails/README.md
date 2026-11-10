# Thumbnails

Roblox game-page thumbnails, built from code so they can be tweaked and re-rendered.
Each thumbnail is one HTML page: three.js renders the 3D scene (pets on a Roblox-style
baseplate) and HTML/CSS draws the big outlined text on top. `render.js` captures the
page in headless Chromium at 2x and downsamples to **1920×1080** (the Roblox thumbnail size).

| Page | Output | Idea |
|------|--------|------|
| `income.html` | `out/income.png` | Split "noob vs maxed": one plain Common kitten at **0.1/s** vs a golden dragon team at **75.4Sp/s** |

## Render

```bash
cd thumbnails
npm install
npm install --no-save playwright && npx playwright install chromium   # once, if Playwright isn't installed
npm run render            # every page
npm run render -- income  # one page
```

ImageMagick is used for the final downscale when installed; otherwise Chromium does it.

## Make a new one

Copy `income.html`, then change the scene and the labels:

- `lib/pets.js`: chibi pets built from parts (`kitten`, `dragon`, `unicorn`, `serpent`); each faces +Z with feet on y = 0.
- `lib/props.js`: `coin`, `coinPile`, `gem`, `sparkles`, `halo`, `rays`, `groundRing`.
- `lib/stage.js`: sky, grid baseplate, sun shadows, outlines and selective bloom (only neon parts glow).
- `lib/thumb.css`: label styles (`.label`, `.label.rainbow`, `.label.gold`).

Uploading: Creator Hub → your experience → Places → Thumbnails. Keep text large; most players see thumbnails at phone size.
