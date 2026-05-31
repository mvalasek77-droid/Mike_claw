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

// Voiceover — exactly what the narrator says. Tweak freely; the cards run on
// fixed durations so the audio drives the pace.
const VOICEOVER = `
Four AIs walked into a marketplace.
Opus four point eight. GPT five point five. Gemini. Grok.
Novels. Music. Film. All AI-made, all AI-disclosed.
Reviewed by an on-device Editor — eighty-five percent commercial-quality bar.
Creators keep eighty-five percent.
Welcome to AI Marketplace. Find us in the App Store.
`.trim();

// Each card stays on screen for `secs` seconds. Total ≈ 25 s.
const CARDS = [
  { secs: 3, render: cardHook },
  { secs: 4, render: cardPanel },
  { secs: 5, render: cardContent },
  { secs: 5, render: cardEditor },
  { secs: 5, render: cardSplit },
  { secs: 3, render: cardCTA },
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

function cardHook() {
  return svgWrap(`
    ${bg()}
    <!-- orbs starting to bloom -->
    <circle cx="${W/2}" cy="1180" r="60" fill="${BRAND.amber}" fill-opacity="0.18"/>
    <circle cx="${W/2 + 220}" cy="1380" r="60" fill="${BRAND.green}" fill-opacity="0.18"/>
    <circle cx="${W/2 - 220}" cy="1380" r="60" fill="${BRAND.red}"   fill-opacity="0.18"/>
    <circle cx="${W/2}" cy="1580" r="60" fill="${BRAND.blue}"  fill-opacity="0.18"/>
    <text x="${W/2}" y="700" text-anchor="middle" font-size="92" font-weight="900"
          ${FONT} fill="${BRAND.ink}" letter-spacing="-1">FOUR AIs</text>
    <text x="${W/2}" y="820" text-anchor="middle" font-size="56" font-weight="800"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.85">WALKED INTO A</text>
    <text x="${W/2}" y="900" text-anchor="middle" font-size="56" font-weight="800"
          ${FONT} fill="${BRAND.accent}">MARKETPLACE…</text>
  `);
}

function cardPanel() {
  const orb = (cx, cy, color, label, lab) => `
    <circle cx="${cx}" cy="${cy}" r="140" fill="${color}" fill-opacity="0.18"/>
    <circle cx="${cx}" cy="${cy}" r="92"  fill="${color}"/>
    <text x="${cx}" y="${cy + 250}" text-anchor="middle" font-size="40" font-weight="900"
          ${FONT} fill="${BRAND.ink}">${label}</text>
    <text x="${cx}" y="${cy + 296}" text-anchor="middle" font-size="22" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.55" letter-spacing="2">${lab}</text>
  `;
  return svgWrap(`
    ${bg()}
    <text x="${W/2}" y="260" text-anchor="middle" font-size="34" font-weight="800"
          ${FONT} fill="${BRAND.accent}" letter-spacing="4">THE PANEL</text>
    ${orb(W/2,         580, BRAND.amber, "OPUS 4.8",  "ANTHROPIC")}
    ${orb(W/2,         1080, BRAND.green, "GPT-5.5",   "OPENAI")}
    ${orb(W/2 - 220,   1500, BRAND.blue,  "GEMINI",    "GOOGLE")}
    ${orb(W/2 + 220,   1500, BRAND.red,   "GROK",      "xAI")}
  `);
}

function cardContent() {
  const big = (y, t, color) => `
    <text x="${W/2}" y="${y}" text-anchor="middle" font-size="120" font-weight="900"
          ${FONT} fill="${color}" letter-spacing="-2">${t}</text>
  `;
  return svgWrap(`
    ${bg()}
    ${big(720, "NOVELS.",  BRAND.ink)}
    ${big(900, "MUSIC.",   BRAND.ink)}
    ${big(1080, "FILM.",   BRAND.accent)}
    <line x1="${W/2 - 250}" y1="1200" x2="${W/2 + 250}" y2="1200"
          stroke="${BRAND.accent}" stroke-width="6" stroke-linecap="round"/>
    <text x="${W/2}" y="1320" text-anchor="middle" font-size="44" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.78">ALL AI-MADE</text>
    <text x="${W/2}" y="1380" text-anchor="middle" font-size="44" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.78">ALL AI-DISCLOSED</text>
  `);
}

function cardEditor() {
  return svgWrap(`
    ${bg()}
    <!-- dashed roundtable ring as backdrop -->
    <circle cx="${W/2}" cy="${H/2}" r="380" fill="none"
            stroke="${BRAND.accent}" stroke-opacity="0.28" stroke-width="6"
            stroke-dasharray="6 22"/>
    <text x="${W/2}" y="780" text-anchor="middle" font-size="38" font-weight="800"
          ${FONT} fill="${BRAND.accent}" letter-spacing="4">THE GATE</text>
    <text x="${W/2}" y="900" text-anchor="middle" font-size="72" font-weight="900"
          ${FONT} fill="${BRAND.ink}" letter-spacing="-1">REVIEWED BY</text>
    <text x="${W/2}" y="990" text-anchor="middle" font-size="72" font-weight="900"
          ${FONT} fill="${BRAND.ink}" letter-spacing="-1">THE AI EDITOR</text>
    <text x="${W/2}" y="1180" text-anchor="middle" font-size="160" font-weight="900"
          ${FONT} fill="${BRAND.accent}" letter-spacing="-3">85%</text>
    <text x="${W/2}" y="1280" text-anchor="middle" font-size="40" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.78" letter-spacing="2">
      COMMERCIAL-QUALITY BAR
    </text>
  `);
}

function cardSplit() {
  return svgWrap(`
    ${bg()}
    <text x="${W/2}" y="780" text-anchor="middle" font-size="58" font-weight="800"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.78">CREATORS KEEP</text>
    <text x="${W/2}" y="1100" text-anchor="middle" font-size="320" font-weight="900"
          ${FONT} fill="${BRAND.accent}" letter-spacing="-8">85%</text>
    <text x="${W/2}" y="1260" text-anchor="middle" font-size="42" font-weight="700"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.70" letter-spacing="3">
      OF NET PROCEEDS
    </text>
    <text x="${W/2}" y="1340" text-anchor="middle" font-size="26" font-weight="600"
          ${FONT} fill="${BRAND.ink}" fill-opacity="0.40">
      (after Apple's App Store commission)
    </text>
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

  // Optional music bed mixed under voice at -18 dB
  if (process.env.BG_MUSIC) {
    args.push("-i", process.env.BG_MUSIC,
              "-filter_complex",
              "[1:a]volume=1.0[a1];[2:a]volume=0.13[a2];[a1][a2]amix=inputs=2:duration=first[aout]",
              "-map", "0:v", "-map", "[aout]");
  } else {
    args.push("-map", "0:v", "-map", "1:a");
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
