// AI Marketplace · TikTok spot generator
//
// Produces tiktok-ad.mp4: a ~25-second 1080×1920 vertical commercial with a
// voiceover (ElevenLabs) and six hard-cut frame cards. Plug and play: one
// command, no editing required.
//
// Required env (see .env.example):
//   ELEVENLABS_API_KEY   for the voiceover
//   OPENAI_API_KEY       fallback TTS if no ElevenLabs key
//
// Optional:
//   BG_MUSIC=/path/to/track.mp3   mix in a music bed at -18 dB under voice
//
// Usage:
//   cd AIMarketplace/tools/tiktok
//   cp .env.example .env   # paste your ELEVENLABS_API_KEY
//   node generate.mjs

import { promises as fs } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";

// ─── .env loader ─────────────────────────────────────────────────────────────
try {
  const env = await fs.readFile(".env", "utf-8");
  for (const line of env.split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.+?)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
} catch {}

// ─── Spec ────────────────────────────────────────────────────────────────────
const W = 1080, H = 1920, FPS = 30;
const VOICE_ELEVEN = "Adam";       // energetic male; change to taste
const VOICE_OPENAI = "ash";        // fallback if no ElevenLabs key

// Voiceover — minimal, lands at the slogan reveal so the visuals carry the
// front of the spot. `VOICE_DELAY_S` shifts the audio so the voice arrives
// when the slogan appears on screen.
const VOICEOVER = `AI Marketplace. The future is next.`;
const VOICE_DELAY_S = 9;

// Storyboard — the crash and the reveal. Hard cuts; total ≈ 17 s.
const CARDS = [
  { secs: 3.0, render: cardRocketStanding },     //  0.0 –  3.0  rocket on the pad
  { secs: 1.8, render: cardTruckApproaching },   //  3.0 –  4.8  cybertruck enters L→R
  { secs: 0.4, render: cardImpact },             //  4.8 –  5.2  IMPACT flash
  { secs: 1.0, render: cardFireball },           //  5.2 –  6.2  initial blast
  { secs: 1.8, render: cardMushroomGrow },       //  6.2 –  8.0  mushroom rising
  { secs: 2.0, render: cardMushroomFull },       //  8.0 – 10.0  full mushroom, slogan emerges
  { secs: 4.0, render: cardSloganHold },         // 10.0 – 14.0  "AI Marketplace · The Future is Next"
  { secs: 3.0, render: cardCTA },                // 14.0 – 17.0  App Store CTA + four-orb echo
];

// ─── Brand ───────────────────────────────────────────────────────────────────
const BRAND = {
  accent: "#FF7A45",
  amber:  "#E8A34A",
  green:  "#10A37F",
  blue:   "#4F8FF7",
  red:    "#E8453C",
  ink:    "#FFFFFF",
  inkSoft:"#C7C7D1",
  inkFaint:"#8A8A96",
};

function bg() {
  return `
    <defs>
      <radialGradient id="bg" cx="50%" cy="32%" r="80%">
        <stop offset="0%"  stop-color="#1d1129"/>
        <stop offset="55%" stop-color="#0d0a14"/>
        <stop offset="100%" stop-color="#050507"/>
      </radialGradient>
    </defs>
    <rect width="${W}" height="${H}" fill="url(#bg)"/>
  `;
}

const FONT = `font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', system-ui, sans-serif"`;

// ─── Cards ───────────────────────────────────────────────────────────────────

// ─── Shared scene elements ────────────────────────────────────────────────

// Stylized — NO logos, NO branded color schemes. Silhouettes read as the
// real things; nothing in the SVG actually claims to be them.
function rocket(x, deformed = false) {
  const tilt = deformed ? "rotate(-6 540 1000)" : "";
  return `
    <g transform="${tilt}">
      <!-- nose cone -->
      <polygon points="${x-10},520 ${x+30},420 ${x+70},520"
               fill="#F4F4F2"/>
      <!-- body -->
      <rect x="${x-10}" y="520" width="80" height="920" fill="#F8F8F6"/>
      <rect x="${x-10}" y="800" width="80" height="4" fill="#444"/>
      <rect x="${x-10}" y="1100" width="80" height="4" fill="#444"/>
      <text x="${x+30}" y="1000" text-anchor="middle"
            font-size="28" font-weight="900" fill="#1a1a1a" ${FONT}>↑</text>
      <!-- fins -->
      <polygon points="${x-10},1440 ${x-70},1500 ${x-10},1500" fill="#C8C8C6"/>
      <polygon points="${x+70},1440 ${x+130},1500 ${x+70},1500" fill="#C8C8C6"/>
      <!-- engine bell -->
      <polygon points="${x-10},1500 ${x},1560 ${x+60},1560 ${x+70},1500"
               fill="#666"/>
    </g>
  `;
}

function ground() {
  return `
    <rect x="0" y="1560" width="${W}" height="360" fill="#0c0a14"/>
    <line x1="0" y1="1560" x2="${W}" y2="1560"
          stroke="${BRAND.accent}" stroke-opacity="0.25" stroke-width="2"/>
  `;
}

function stars() {
  // Sprinkled small dots for a night-sky feel
  return [
    [120, 200], [240, 360], [400, 180], [620, 280], [820, 420],
    [950, 200], [60, 540], [880, 660], [320, 640], [720, 540],
  ].map(([x, y]) => `<circle cx="${x}" cy="${y}" r="2" fill="#ffffff" fill-opacity="0.55"/>`).join("");
}

// Cybertruck-style angular wedge — silver, no badges.
function cyberTruck(cx, cy, scale = 1) {
  const s = scale;
  // Body wedge: peak at top-rear, slopes down to the front hood.
  // cx is the FRONT bumper centre (where the impact lands).
  const fx = cx;          // front bumper x
  const rx = cx - 320*s;  // rear x
  return `
    <g>
      <!-- body silhouette -->
      <polygon points="
          ${fx},${cy}           ${fx},${cy - 50*s}
          ${fx - 80*s},${cy - 110*s}
          ${fx - 180*s},${cy - 140*s}
          ${rx + 40*s},${cy - 140*s}
          ${rx},${cy - 60*s}
          ${rx},${cy + 60*s}
          ${fx},${cy + 60*s}
      " fill="#BCBCC0"/>
      <!-- window strip -->
      <polygon points="
          ${fx - 80*s},${cy - 100*s}
          ${fx - 170*s},${cy - 130*s}
          ${rx + 50*s},${cy - 130*s}
          ${rx + 10*s},${cy - 80*s}
      " fill="#222226"/>
      <!-- door line -->
      <line x1="${rx + 130*s}" y1="${cy - 130*s}" x2="${rx + 130*s}" y2="${cy + 60*s}"
            stroke="#909094" stroke-width="2"/>
      <!-- headlight bar (light strip) -->
      <rect x="${fx - 60*s}" y="${cy - 40*s}" width="60" height="6" fill="#fcfcfc" fill-opacity="0.9"/>
      <!-- wheels -->
      <circle cx="${fx - 60*s}" cy="${cy + 70*s}" r="${42*s}" fill="#141416"/>
      <circle cx="${fx - 60*s}" cy="${cy + 70*s}" r="${22*s}" fill="#7c7c80"/>
      <circle cx="${rx + 70*s}" cy="${cy + 70*s}" r="${42*s}" fill="#141416"/>
      <circle cx="${rx + 70*s}" cy="${cy + 70*s}" r="${22*s}" fill="#7c7c80"/>
    </g>
  `;
}

// Speed lines trailing behind something at (x, y).
function speedLines(x, y, count = 6) {
  return Array.from({ length: count }, (_, i) => {
    const yy = y - 80 + i * 28;
    return `<line x1="${x - 240 - i*30}" y1="${yy}" x2="${x - 30}" y2="${yy}"
            stroke="#ffffff" stroke-opacity="${0.45 - i*0.05}" stroke-width="3"/>`;
  }).join("");
}

// ─── Cards ─────────────────────────────────────────────────────────────────

function cardRocketStanding() {
  return svgWrap(`
    ${bg()}
    ${stars()}
    ${rocket(540)}
    ${ground()}
  `);
}

function cardTruckApproaching() {
  // Truck mid-stage, charging toward the rocket from the left.
  return svgWrap(`
    ${bg()}
    ${stars()}
    ${rocket(540)}
    ${speedLines(420, 1240, 8)}
    ${cyberTruck(420, 1240)}
    ${ground()}
  `);
}

function cardImpact() {
  // Front bumper kisses the rocket. Big yellow-white flash at the contact.
  return svgWrap(`
    <defs>
      <radialGradient id="flash" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#FFFFFF"/>
        <stop offset="35%"  stop-color="#FFE07A"/>
        <stop offset="70%"  stop-color="#FF7A45" stop-opacity="0.7"/>
        <stop offset="100%" stop-color="#FF7A45" stop-opacity="0"/>
      </radialGradient>
    </defs>
    ${bg()}
    ${stars()}
    ${rocket(540, true)}
    ${cyberTruck(530, 1240)}
    <circle cx="540" cy="1180" r="320" fill="url(#flash)"/>
    ${ground()}
  `);
}

function cardFireball() {
  // The blast eats both vehicles. Big chunky fireball.
  return svgWrap(`
    <defs>
      <radialGradient id="core" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#FFFFFF"/>
        <stop offset="25%"  stop-color="#FFD089"/>
        <stop offset="55%"  stop-color="#FF7A45"/>
        <stop offset="85%"  stop-color="#7A1F00"/>
        <stop offset="100%" stop-color="#1a0000" stop-opacity="0"/>
      </radialGradient>
      <radialGradient id="halo" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#FF7A45" stop-opacity="0.65"/>
        <stop offset="100%" stop-color="#FF7A45" stop-opacity="0"/>
      </radialGradient>
    </defs>
    ${bg()}
    <circle cx="540" cy="1120" r="600" fill="url(#halo)"/>
    <circle cx="540" cy="1120" r="380" fill="url(#core)"/>
    <!-- debris fragments -->
    <rect x="180" y="900"  width="60" height="14" fill="#C8C8C6" transform="rotate(28 210 907)"/>
    <rect x="820" y="980"  width="80" height="14" fill="#C8C8C6" transform="rotate(-42 860 987)"/>
    <rect x="320" y="700"  width="40" height="10" fill="#F4F4F2" transform="rotate(12 340 705)"/>
    <rect x="780" y="640"  width="50" height="10" fill="#F4F4F2" transform="rotate(-22 805 645)"/>
    ${ground()}
  `);
}

function cardMushroomGrow() {
  // Stem rising from the blast point; cap not fully formed yet.
  return svgWrap(`
    <defs>
      <radialGradient id="smokeBall" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#3a342f" stop-opacity="0.95"/>
        <stop offset="70%"  stop-color="#231e1a" stop-opacity="0.9"/>
        <stop offset="100%" stop-color="#0d0a08" stop-opacity="0"/>
      </radialGradient>
      <radialGradient id="ember" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#FFD089"/>
        <stop offset="55%"  stop-color="#FF7A45"/>
        <stop offset="100%" stop-color="#7A1F00" stop-opacity="0"/>
      </radialGradient>
    </defs>
    ${bg()}
    <!-- stem -->
    <ellipse cx="540" cy="1300" rx="180" ry="280" fill="url(#smokeBall)"/>
    <ellipse cx="540" cy="900"  rx="220" ry="200" fill="url(#smokeBall)"/>
    <!-- forming cap -->
    <circle cx="380" cy="700" r="180" fill="url(#smokeBall)"/>
    <circle cx="540" cy="650" r="240" fill="url(#smokeBall)"/>
    <circle cx="700" cy="700" r="180" fill="url(#smokeBall)"/>
    <!-- ember core -->
    <circle cx="540" cy="1100" r="120" fill="url(#ember)"/>
    ${ground()}
  `);
}

function cardMushroomFull() {
  // Cap fully formed. "AI MARKETPLACE" emerges from the top of the cloud.
  return svgWrap(`
    <defs>
      <radialGradient id="smokeBall2" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#4a423a" stop-opacity="0.92"/>
        <stop offset="65%"  stop-color="#2a2421" stop-opacity="0.9"/>
        <stop offset="100%" stop-color="#0d0a08" stop-opacity="0"/>
      </radialGradient>
      <radialGradient id="ember2" cx="50%" cy="50%" r="50%">
        <stop offset="0%"   stop-color="#FFD089" stop-opacity="0.55"/>
        <stop offset="100%" stop-color="#FF7A45" stop-opacity="0"/>
      </radialGradient>
    </defs>
    ${bg()}
    <!-- billowing cap, larger -->
    <circle cx="280" cy="600" r="220" fill="url(#smokeBall2)"/>
    <circle cx="540" cy="500" r="320" fill="url(#smokeBall2)"/>
    <circle cx="800" cy="600" r="220" fill="url(#smokeBall2)"/>
    <!-- stem -->
    <ellipse cx="540" cy="950"  rx="240" ry="200" fill="url(#smokeBall2)"/>
    <ellipse cx="540" cy="1300" rx="200" ry="280" fill="url(#smokeBall2)"/>
    <!-- glowing core at the base -->
    <circle cx="540" cy="1180" r="200" fill="url(#ember2)"/>
    <!-- "AI Marketplace" emerging at the top of the cap -->
    <text x="${W/2}" y="380" text-anchor="middle" font-size="76" font-weight="900"
          ${FONT} fill="#FFFFFF" letter-spacing="-1" opacity="0.85">AI Marketplace</text>
    ${ground()}
  `);
}

function cardSloganHold() {
  // Final slogan with smoke residue behind.
  return svgWrap(`
    <defs>
      <radialGradient id="residue" cx="50%" cy="60%" r="60%">
        <stop offset="0%"   stop-color="#2a2421" stop-opacity="0.65"/>
        <stop offset="100%" stop-color="#0d0a08" stop-opacity="0"/>
      </radialGradient>
    </defs>
    ${bg()}
    <ellipse cx="540" cy="1300" rx="500" ry="500" fill="url(#residue)"/>
    <text x="${W/2}" y="800" text-anchor="middle" font-size="110" font-weight="900"
          ${FONT} fill="${BRAND.ink}" letter-spacing="-2">AI Marketplace</text>
    <line x1="${W/2 - 200}" y1="900" x2="${W/2 + 200}" y2="900"
          stroke="${BRAND.accent}" stroke-width="6" stroke-linecap="round"/>
    <text x="${W/2}" y="1040" text-anchor="middle" font-size="60" font-weight="800"
          ${FONT} fill="${BRAND.accent}" letter-spacing="-1">The Future</text>
    <text x="${W/2}" y="1130" text-anchor="middle" font-size="60" font-weight="800"
          ${FONT} fill="${BRAND.accent}" letter-spacing="-1">is Next.</text>
  `);
}

function cardCTA() {
  return svgWrap(`
    ${bg()}
    <!-- bloomed orbs as backdrop -->
    <circle cx="${W/2 - 200}" cy="${H/2 - 50}" r="180" fill="${BRAND.amber}" fill-opacity="0.20"/>
    <circle cx="${W/2 + 200}" cy="${H/2 - 50}" r="180" fill="${BRAND.green}" fill-opacity="0.20"/>
    <circle cx="${W/2 - 200}" cy="${H/2 + 200}" r="180" fill="${BRAND.red}"   fill-opacity="0.20"/>
    <circle cx="${W/2 + 200}" cy="${H/2 + 200}" r="180" fill="${BRAND.blue}"  fill-opacity="0.20"/>
    <text x="${W/2}" y="780" text-anchor="middle" font-size="36" font-weight="800"
          ${FONT} fill="${BRAND.accent}" letter-spacing="5">WELCOME TO</text>
    <text x="${W/2}" y="900" text-anchor="middle" font-size="100" font-weight="900"
          ${FONT} fill="${BRAND.ink}" letter-spacing="-2">AI Marketplace</text>
    <text x="${W/2}" y="1180" text-anchor="middle" font-size="40" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.78">Available in the</text>
    <text x="${W/2}" y="1240" text-anchor="middle" font-size="48" font-weight="900"
          ${FONT} fill="${BRAND.accent}">App Store</text>
  `);
}

function svgWrap(inner) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
function runCmd(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], ...opts });
    let err = "";
    p.stderr.on("data", d => { err += d; });
    p.on("error", reject);
    p.on("close", code => code === 0 ? resolve() : reject(new Error(`${cmd} exit ${code}: ${err.trim()}`)));
  });
}

async function svgToPng(svg, outPath) {
  const tmpSvg = outPath.replace(/\.png$/, ".svg");
  await fs.writeFile(tmpSvg, svg);
  const qlOut = path.dirname(outPath);
  await runCmd("qlmanage", ["-t", "-s", String(W), "-f", "1.0", tmpSvg, "-o", qlOut]);
  // qlmanage saves as <basename>.svg.png — rename it
  const produced = path.join(qlOut, path.basename(tmpSvg) + ".png");
  await fs.rename(produced, outPath);
  await fs.unlink(tmpSvg);
}

async function ttsElevenLabs(text, outPath) {
  const key = process.env.ELEVENLABS_API_KEY;
  // resolve voice name → voiceId
  const list = await fetch("https://api.elevenlabs.io/v1/voices", { headers: { "xi-api-key": key } });
  if (!list.ok) throw new Error(`ElevenLabs /voices ${list.status}`);
  const voices = (await list.json()).voices;
  const v = voices.find(x => x.name.toLowerCase() === VOICE_ELEVEN.toLowerCase());
  if (!v) throw new Error(`Voice "${VOICE_ELEVEN}" not in your ElevenLabs library`);
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${v.voice_id}`, {
    method: "POST",
    headers: { "xi-api-key": key, "content-type": "application/json", "accept": "audio/mpeg" },
    body: JSON.stringify({
      text, model_id: "eleven_turbo_v2_5",
      voice_settings: { stability: 0.45, similarity_boost: 0.78, style: 0.35 },
    }),
  });
  if (!res.ok) throw new Error(`ElevenLabs TTS ${res.status}: ${await res.text()}`);
  await fs.writeFile(outPath, Buffer.from(await res.arrayBuffer()));
}

async function ttsOpenAI(text, outPath) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY required (or set ELEVENLABS_API_KEY)");
  const res = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ model: "tts-1-hd", voice: VOICE_OPENAI, input: text, response_format: "mp3" }),
  });
  if (!res.ok) throw new Error(`OpenAI TTS ${res.status}: ${await res.text()}`);
  await fs.writeFile(outPath, Buffer.from(await res.arrayBuffer()));
}

async function renderVoice(outPath) {
  if (process.env.ELEVENLABS_API_KEY) return ttsElevenLabs(VOICEOVER, outPath);
  return ttsOpenAI(VOICEOVER, outPath);
}

// ─── ffmpeg compose ──────────────────────────────────────────────────────────
async function composeMP4(framePaths, voicePath, outPath) {
  // Build a concat list: each frame for its declared duration as a still
  const listPath = ".tiktok-work/list.txt";
  const lines = framePaths.map((p, i) => {
    const secs = CARDS[i].secs;
    return `file '${path.resolve(p)}'\nduration ${secs}`;
  });
  // ffmpeg concat demuxer needs the last file repeated WITHOUT a duration
  lines.push(`file '${path.resolve(framePaths[framePaths.length - 1])}'`);
  await fs.writeFile(listPath, lines.join("\n"));

  const args = [
    "-y",
    "-f", "concat", "-safe", "0", "-i", listPath,
    "-i", voicePath,
  ];

  // Voice lands at VOICE_DELAY_S so the slogan is voiced exactly when it
  // appears on screen. adelay needs ms; provide for both stereo channels.
  const delayMs = Math.round(VOICE_DELAY_S * 1000);
  const voiceDelay = `[1:a]adelay=${delayMs}|${delayMs}[vo]`;

  if (process.env.BG_MUSIC) {
    // Voice delayed, then mixed with a music bed at -18 dB.
    args.push("-i", process.env.BG_MUSIC,
              "-filter_complex",
              `${voiceDelay};[vo]volume=1.0[a1];[2:a]volume=0.13[a2];[a1][a2]amix=inputs=2:duration=first[aout]`,
              "-map", "0:v", "-map", "[aout]");
  } else {
    args.push("-filter_complex", voiceDelay,
              "-map", "0:v", "-map", "[vo]");
  }

  args.push(
    "-r", String(FPS),
    "-s", `${W}x${H}`,
    "-pix_fmt", "yuv420p",
    "-c:v", "libx264", "-preset", "medium", "-crf", "21",
    "-c:a", "aac", "-b:a", "192k",
    "-shortest",
    "-movflags", "+faststart",
    outPath,
  );
  await runCmd("ffmpeg", args, { stdio: "inherit" });
}

// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {
  if (!process.env.ELEVENLABS_API_KEY && !process.env.OPENAI_API_KEY) {
    throw new Error("Set ELEVENLABS_API_KEY (preferred) or OPENAI_API_KEY for the voiceover.");
  }

  const work = ".tiktok-work";
  await fs.mkdir(work, { recursive: true });

  console.log("Rendering 6 frames…");
  const framePaths = [];
  for (let i = 0; i < CARDS.length; i++) {
    const png = path.join(work, `frame-${i + 1}.png`);
    await svgToPng(CARDS[i].render(), png);
    framePaths.push(png);
    console.log(`  ✓ frame ${i + 1}/${CARDS.length}`);
  }

  console.log(`Voicing (${process.env.ELEVENLABS_API_KEY ? "ElevenLabs " + VOICE_ELEVEN : "OpenAI TTS " + VOICE_OPENAI})…`);
  const voicePath = path.join(work, "voice.mp3");
  await renderVoice(voicePath);

  console.log("Composing tiktok-ad.mp4…");
  await composeMP4(framePaths, voicePath, "tiktok-ad.mp4");

  const stat = await fs.stat("tiktok-ad.mp4");
  console.log(`\n✓ tiktok-ad.mp4  (${(stat.size / 1024 / 1024).toFixed(1)} MB · 1080×1920)`);
  console.log("Upload to TikTok. Suggested caption + hashtags are in README.md.");
}

main().catch(e => { console.error("\n✗", e.message); process.exit(1); });
