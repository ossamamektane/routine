// Draws the app icon (light, dark and tinted) and the small logo used on the welcome screen.
// Run from the repository root:  node scripts/make-icons.cjs
// Needs the "sharp" package (npm install sharp).
const fs = require("fs");
const path = require("path");
let sharp;
for (const candidate of ["sharp", "/data/node_modules/sharp", "/vercel/sandbox/node_modules/sharp"]) {
  try {
    sharp = require(candidate);
    break;
  } catch {}
}
if (!sharp) throw new Error("Install sharp first: npm install sharp");

const root = path.resolve(__dirname, "..");
const assets = path.join(root, "Routine/Resources/Assets.xcassets");
const design = path.join(root, "design");

// The Routine mark: a loop that comes round again (a routine) around a check mark (done).
// Drawn the way Apple draws Messages, Phone and FaceTime, so it sits naturally next to them:
// the same green, one solid white symbol, a single stroke weight and a soft lift.

// Apple's green, as on Messages, Phone and FaceTime.
const GREEN_TOP = "#5BF675";
const GREEN_BOTTOM = "#0CBD2A";

// Geometry on Apple's 1024 pt icon grid.
const W = 78;                 // stroke weight of the loop
const CW = 83;                // the check is a little heavier: diagonals read thinner than curves
const R = 284;                // loop radius, to the middle of the stroke
const O = { x: 524, y: 512 }; // nudged right so the arrowhead's extra weight on the left balances out
const END = 180;              // the loop ends at the far left; the arrowhead points straight up (clockwise)
const GAP = 40;               // opening at the upper left, in degrees: about one stroke of clear space
const CORNER = 24;            // rounds the arrowhead's corners to match the round stroke ends

const rad = (d) => (d * Math.PI) / 180;
const f = (n) => Math.round(n * 10) / 10;
const onLoop = (deg) => [O.x + R * Math.cos(rad(deg)), O.y + R * Math.sin(rad(deg))];

function mark(paint) {
  const [sx, sy] = onLoop(END + GAP);
  const [ex, ey] = onLoop(END);
  const loop = `M ${f(sx)} ${f(sy)} A ${R} ${R} 0 1 1 ${f(ex)} ${f(ey)}`;

  // Arrowhead: base across the end of the loop, tip along the direction of travel.
  const t = [-Math.sin(rad(END)), Math.cos(rad(END))];
  const n = [Math.cos(rad(END)), Math.sin(rad(END))];
  const half = 1.15 * W - CORNER / 2;
  const length = 1.25 * W - CORNER / 2;
  const base = [ex - t[0] * 4, ey - t[1] * 4];
  const outer = [base[0] + n[0] * half, base[1] + n[1] * half];
  const inner = [base[0] - n[0] * half, base[1] - n[1] * half];
  const tip = [ex + t[0] * length, ey + t[1] * length];
  const head = `M ${f(outer[0])} ${f(outer[1])} L ${f(tip[0])} ${f(tip[1])} L ${f(inner[0])} ${f(inner[1])} Z`;

  // Check: short arm at 45°, long arm at 50°, about 1 : 2, optically centred inside the loop.
  const k = 1.12;
  const a = [O.x - 118.5 * k, O.y + 15 * k];
  const v = [O.x - 37.5 * k, O.y + 96 * k];
  const b = [O.x + 110.5 * k, O.y - 80 * k];
  const check = `M ${f(a[0])} ${f(a[1])} L ${f(v[0])} ${f(v[1])} L ${f(b[0])} ${f(b[1])}`;

  return `
    <path d="${loop}" fill="none" stroke="${paint}" stroke-width="${W}" stroke-linecap="round"/>
    <path d="${head}" fill="${paint}" stroke="${paint}" stroke-width="${CORNER}" stroke-linejoin="round"/>
    <path d="${check}" fill="none" stroke="${paint}" stroke-width="${CW}" stroke-linecap="round" stroke-linejoin="round"/>`;
}

function lift(color, opacity) {
  return `<filter id="lift" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
      <feGaussianBlur in="SourceAlpha" stdDeviation="16"/>
      <feOffset dy="12" result="blur"/>
      <feFlood flood-color="${color}" flood-opacity="${opacity}"/>
      <feComposite in2="blur" operator="in"/>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>`;
}

function svg({ background, ink, shadow }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${background[0]}"/><stop offset="1" stop-color="${background[1]}"/>
    </linearGradient>
    <linearGradient id="ink" gradientUnits="userSpaceOnUse" x1="0" y1="190" x2="0" y2="840">
      <stop offset="0" stop-color="${ink[0]}"/><stop offset="1" stop-color="${ink[1]}"/>
    </linearGradient>
    ${shadow ? lift(shadow[0], shadow[1]) : ""}
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <g${shadow ? ' filter="url(#lift)"' : ""}>${mark("url(#ink)")}
  </g>
</svg>`;
}

const variants = {
  // Light: white on Apple green.
  light: svg({ background: [GREEN_TOP, GREEN_BOTTOM], ink: ["#FFFFFF", "#F0FFF3"], shadow: ["#00561E", 0.26] }),
  // Dark: the mark turns green on a dark background, as Apple's own apps do in dark mode.
  dark: svg({ background: ["#2A2A2C", "#0B0B0C"], ink: [GREEN_TOP, GREEN_BOTTOM], shadow: ["#000000", 0.45] }),
  // Tinted: plain white on black; iOS adds the tint.
  tinted: svg({ background: ["#000000", "#000000"], ink: ["#FFFFFF", "#FFFFFF"], shadow: null }),
};

async function png(source, size, file) {
  await sharp(Buffer.from(source))
    .resize(size, size)
    .flatten({ background: "#000000" })
    .removeAlpha()
    .png()
    .toFile(file);
}

function writeJSON(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n");
}

(async () => {
  fs.mkdirSync(design, { recursive: true });
  const iconDir = path.join(assets, "AppIcon.appiconset");
  const markDir = path.join(assets, "AppMark.imageset");
  fs.mkdirSync(iconDir, { recursive: true });
  fs.mkdirSync(markDir, { recursive: true });

  for (const [name, source] of Object.entries(variants)) {
    fs.writeFileSync(path.join(design, `app-icon-${name}.svg`), source);
  }
  await png(variants.light, 1024, path.join(iconDir, "AppIcon.png"));
  await png(variants.dark, 1024, path.join(iconDir, "AppIcon-Dark.png"));
  await png(variants.tinted, 1024, path.join(iconDir, "AppIcon-Tinted.png"));
  await png(variants.light, 512, path.join(markDir, "AppMark.png"));
  await png(variants.light, 192, path.join(root, "docs", "icon.png"));

  writeJSON(path.join(assets, "Contents.json"), { info: { author: "xcode", version: 1 } });
  writeJSON(path.join(iconDir, "Contents.json"), {
    images: [
      { filename: "AppIcon.png", idiom: "universal", platform: "ios", size: "1024x1024" },
      {
        appearances: [{ appearance: "luminosity", value: "dark" }],
        filename: "AppIcon-Dark.png", idiom: "universal", platform: "ios", size: "1024x1024",
      },
      {
        appearances: [{ appearance: "luminosity", value: "tinted" }],
        filename: "AppIcon-Tinted.png", idiom: "universal", platform: "ios", size: "1024x1024",
      },
    ],
    info: { author: "xcode", version: 1 },
  });
  writeJSON(path.join(markDir, "Contents.json"), {
    images: [{ filename: "AppMark.png", idiom: "universal" }],
    info: { author: "xcode", version: 1 },
  });
  writeJSON(path.join(assets, "AccentColor.colorset", "Contents.json"), {
    colors: [
      {
        color: { "color-space": "srgb", components: { red: "0x00", green: "0xA8", blue: "0x3E", alpha: "1.000" } },
        idiom: "universal",
      },
      {
        appearances: [{ appearance: "luminosity", value: "dark" }],
        color: { "color-space": "srgb", components: { red: "0x30", green: "0xD1", blue: "0x58", alpha: "1.000" } },
        idiom: "universal",
      },
    ],
    info: { author: "xcode", version: 1 },
  });

  // A preview of the three looks with the iPhone's rounded mask, for the README.
  const size = 300, gap = 40;
  const mask = Buffer.from(`<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${size * 0.2237}" ry="${size * 0.2237}"/></svg>`);
  const tiles = [];
  for (const name of ["light", "dark", "tinted"]) {
    const tile = await sharp(Buffer.from(variants[name])).resize(size, size).composite([{ input: mask, blend: "dest-in" }]).png().toBuffer();
    tiles.push(tile);
  }
  const width = size * 3 + gap * 4, height = size + gap * 2;
  await sharp({ create: { width, height, channels: 4, background: "#F2F2F7" } })
    .composite(tiles.map((input, i) => ({ input, left: gap + i * (size + gap), top: gap })))
    .png()
    .toFile(path.join(design, "app-icon-preview.png"));
  console.log("Icons written.");
})();
