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

// A circular "repeat" arrow around a check mark, centred on Apple's 1024 pt icon grid.
function glyph(stroke) {
  return `
  <g fill="none" stroke="${stroke}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M 294 330 A 288 288 0 1 1 225 532" stroke-width="64"/>
    <path d="M 180 551 L 225 505 L 270 551" stroke-width="64"/>
    <path d="M 353 512 L 462 621 L 645 420" stroke-width="82"/>
  </g>`;
}

function svg(defs, background, stroke) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>${defs}</defs>
  <rect width="1024" height="1024" fill="${background}"/>${glyph(stroke)}
</svg>`;
}

const variants = {
  light: svg(
    `<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#19C75A"/><stop offset="1" stop-color="#00A23C"/>
    </linearGradient>`,
    "url(#bg)",
    "#FFFFFF"
  ),
  dark: svg(
    `<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#2A2A2C"/><stop offset="1" stop-color="#0E0E0F"/>
    </linearGradient>
    <linearGradient id="fg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#3EDB68"/><stop offset="1" stop-color="#22B94F"/>
    </linearGradient>`,
    "url(#bg)",
    "url(#fg)"
  ),
  tinted: svg("", "#000000", "#FFFFFF"),
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
