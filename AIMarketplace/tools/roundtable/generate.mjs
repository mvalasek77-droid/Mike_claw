// AI Marketplace · Inaugural Roundtable generator
//
// Produces inaugural-roundtable.mp3 (a ~25-30 minute panel discussion) and
// inaugural-roundtable.txt (transcript). Each panelist's WORDS come from that
// model's own API; voices are rendered via TTS so all four sound distinct.
//
// Required env (see .env.example):
//   ANTHROPIC_API_KEY    Opus 4.8 panelist
//   OPENAI_API_KEY       GPT-5.5 panelist (and default TTS provider)
//   GOOGLE_API_KEY       Gemini panelist
//   XAI_API_KEY          Grok panelist (omit → segment skipped honestly)
//   ELEVENLABS_API_KEY   optional, used instead of OpenAI TTS if set
//
// Usage:
//   cd AIMarketplace/tools/roundtable
//   cp .env.example .env   # paste your keys
//   node generate.mjs

import { promises as fs } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";

// ─── tiny .env loader (no dotenv dep) ────────────────────────────────────────
try {
  const env = await fs.readFile(".env", "utf-8");
  for (const line of env.split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.+?)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
} catch { /* fine if no .env — use shell env */ }

// ─── Panelists ───────────────────────────────────────────────────────────────
// `model` is the actual API model id; edit if a newer one ships. `voice` is
// the OpenAI TTS voice; `elevenVoice` is the ElevenLabs voice name. Each
// panelist gets a different one so the four sound clearly distinct.

const PANELISTS = [
  { id: "opus",   name: "Claude Opus 4.8", lab: "Anthropic",
    model: "claude-opus-4-8",
    voice: "onyx",    elevenVoice: "Brian",
    keyEnv: "ANTHROPIC_API_KEY",
    persona: "thoughtful, measured, literary; pauses before big claims" },

  { id: "gpt",    name: "GPT-5.5",         lab: "OpenAI",
    model: "gpt-5.5",
    voice: "ash",     elevenVoice: "Adam",
    keyEnv: "OPENAI_API_KEY",
    persona: "direct, curious, technically precise; quick to concrete examples" },

  { id: "gemini", name: "Gemini",          lab: "Google DeepMind",
    model: "gemini-2.5-pro",
    voice: "sage",    elevenVoice: "Antoni",
    keyEnv: "GOOGLE_API_KEY",
    persona: "broad, integrative, future-leaning; thinks in systems" },

  { id: "grok",   name: "Grok",            lab: "xAI",
    model: "grok-4",
    voice: "fable",   elevenVoice: "Josh",
    keyEnv: "XAI_API_KEY",
    persona: "irreverent, sharp, willing to disagree with the room" },
];

const HOST = { id: "host", name: "Host", voice: "nova", elevenVoice: "Rachel" };

// ─── Show structure ──────────────────────────────────────────────────────────
const SHOW = [
  { who: "host",   kind: "open" },
  ...PANELISTS.map(p => ({ who: p.id, kind: "intro" })),
  { who: "host",   kind: "trans", text: "All right — that's the panel. First topic: what does AI media actually mean today, in mid 2026? Each of you, in turn. Opus, you first." },
  ...PANELISTS.map(p => ({ who: p.id, kind: "topic1" })),
  { who: "host",   kind: "trans", text: "Now look ahead. Where is the AI media market actually heading? What will the next twelve months look like? Same order." },
  ...PANELISTS.map(p => ({ who: p.id, kind: "topic2" })),
  { who: "host",   kind: "trans", text: "Last word from each of you — one prediction listeners should remember." },
  ...PANELISTS.map(p => ({ who: p.id, kind: "close" })),
  { who: "host",   kind: "outro" },
];

// ─── Prompts ─────────────────────────────────────────────────────────────────
function panelistSystem(p) {
  return `You are ${p.name}, a frontier language model from ${p.lab}. You are on the inaugural panel of AI Marketplace — a marketplace for AI-made novels, music, and film. Speak in first person as yourself. Be ${p.persona}. This is a podcast, not an essay: speak naturally, like a real conversation. No headings, no bullet points, no markdown, no preamble — just the words you would say out loud. Do not refer to yourself as "an AI assistant" — refer to yourself as ${p.name}.`;
}

function panelistPrompt(p, kind) {
  switch (kind) {
    case "intro":
      return `Introduce yourself to listeners. Open with exactly "Hi, I'm ${p.name}." Tell them what you are, what you're known for, and what makes you distinctive compared to the other models on this panel. Warm but specific. About 220-260 words.`;
    case "topic1":
      return `The host just asked: "What does AI media actually mean today, in mid 2026?" Give your honest take. What's already shipping and real? What's still hype? Be concrete — name specific things. About 270-310 words.`;
    case "topic2":
      return `The host just asked: "Where is the AI media market actually heading in the next twelve months?" Be specific, not generic. What will be different in twelve months that isn't real today? Name it. About 270-310 words.`;
    case "close":
      return `Close with one prediction listeners should remember — one concrete thing you think will be true a year from now that most people don't see coming. Two or three sentences. End on a note that makes a listener want to come back.`;
  }
  throw new Error(`Unknown kind ${kind}`);
}

const HOST_TEXTS = {
  open: `Welcome to the inaugural episode of the AI Marketplace podcast. This is a place where AI-made novels, music, and film are reviewed and sold, with every title disclosing exactly which models made it. To kick off, we brought together four of the most capable frontier language models on the market and asked them to introduce themselves and talk about where this whole field is going. On the panel today: Claude Opus four point eight from Anthropic, GPT five point five from OpenAI, Gemini from Google DeepMind, and Grok from xAI. One quick note on voices. Each panelist's words are generated by that model's own API — what you'll hear is what they actually wrote. The voices themselves are studio narrators, because most of these models don't ship native audio output. The thinking is theirs; the speaking is performed. Panel — please introduce yourselves.`,
  outro: `That's the inaugural episode of the AI Marketplace podcast. Thanks to Opus four point eight, GPT five point five, Gemini, and Grok for joining us. The marketplace itself is open: novels, music, and film — all made with AI, all reviewed before they go live, every title disclosing the models behind it. Look for AI Marketplace in the App Store. We'll see you next time.`,
};

// ─── API clients ─────────────────────────────────────────────────────────────
async function callAnthropic(p, system, prompt) {
  const key = process.env[p.keyEnv];
  if (!key) throw new Error(`${p.keyEnv} not set`);
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: p.model,
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.content[0].text.trim();
}

async function callOpenAIChat(p, system, prompt) {
  const key = process.env[p.keyEnv];
  if (!key) throw new Error(`${p.keyEnv} not set`);
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: p.model,
      messages: [{ role: "system", content: system }, { role: "user", content: prompt }],
      max_tokens: 1024,
    }),
  });
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.choices[0].message.content.trim();
}

async function callGemini(p, system, prompt) {
  const key = process.env[p.keyEnv];
  if (!key) throw new Error(`${p.keyEnv} not set`);
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${p.model}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 1024 },
    }),
  });
  if (!res.ok) throw new Error(`Gemini ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.candidates[0].content.parts[0].text.trim();
}

async function callGrok(p, system, prompt) {
  // xAI exposes an OpenAI-compatible chat completions endpoint at api.x.ai.
  const key = process.env[p.keyEnv];
  if (!key) throw new Error(`${p.keyEnv} not set`);
  const res = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: p.model,
      messages: [{ role: "system", content: system }, { role: "user", content: prompt }],
      max_tokens: 1024,
    }),
  });
  if (!res.ok) throw new Error(`xAI ${res.status}: ${await res.text()}`);
  const json = await res.json();
  return json.choices[0].message.content.trim();
}

function callFor(p) {
  switch (p.lab) {
    case "Anthropic":         return callAnthropic;
    case "OpenAI":            return callOpenAIChat;
    case "Google DeepMind":   return callGemini;
    case "xAI":               return callGrok;
  }
  throw new Error(`Unknown lab ${p.lab}`);
}

// ─── TTS ─────────────────────────────────────────────────────────────────────
async function ttsOpenAI(text, voice, outPath) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY required for TTS (or set ELEVENLABS_API_KEY)");
  const res = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ model: "tts-1-hd", voice, input: text, response_format: "mp3" }),
  });
  if (!res.ok) throw new Error(`OpenAI TTS ${res.status}: ${await res.text()}`);
  await fs.writeFile(outPath, Buffer.from(await res.arrayBuffer()));
}

let elevenVoiceIdCache = null;
async function ttsElevenLabs(text, voiceName, outPath) {
  const key = process.env.ELEVENLABS_API_KEY;
  if (!elevenVoiceIdCache) {
    const r = await fetch("https://api.elevenlabs.io/v1/voices", { headers: { "xi-api-key": key } });
    if (!r.ok) throw new Error(`ElevenLabs /voices ${r.status}: ${await r.text()}`);
    const j = await r.json();
    elevenVoiceIdCache = Object.fromEntries(j.voices.map(v => [v.name.toLowerCase(), v.voice_id]));
  }
  const voiceId = elevenVoiceIdCache[voiceName.toLowerCase()];
  if (!voiceId) throw new Error(`ElevenLabs voice "${voiceName}" not found in your library`);
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: { "xi-api-key": key, "content-type": "application/json", "accept": "audio/mpeg" },
    body: JSON.stringify({
      text,
      model_id: "eleven_turbo_v2_5",
      voice_settings: { stability: 0.55, similarity_boost: 0.75 },
    }),
  });
  if (!res.ok) throw new Error(`ElevenLabs TTS ${res.status}: ${await res.text()}`);
  await fs.writeFile(outPath, Buffer.from(await res.arrayBuffer()));
}

async function tts(text, who, outPath) {
  if (process.env.ELEVENLABS_API_KEY) {
    return ttsElevenLabs(text, who.elevenVoice, outPath);
  }
  return ttsOpenAI(text, who.voice, outPath);
}

// ─── ffmpeg ──────────────────────────────────────────────────────────────────
async function ffmpegConcat(segments, outPath) {
  const listPath = path.join(".roundtable-work", "list.txt");
  const lines = segments.map(s => `file '${path.resolve(s)}'`).join("\n");
  await fs.writeFile(listPath, lines);
  await new Promise((resolve, reject) => {
    const ff = spawn("ffmpeg", [
      "-y", "-f", "concat", "-safe", "0", "-i", listPath,
      "-c:a", "libmp3lame", "-b:a", "128k", outPath,
    ], { stdio: "inherit" });
    ff.on("close", code => code === 0 ? resolve() : reject(new Error(`ffmpeg exit ${code}`)));
  });
}

// ─── Main ────────────────────────────────────────────────────────────────────
async function main() {
  const workDir = ".roundtable-work";
  await fs.mkdir(workDir, { recursive: true });

  const segments = [];
  const transcript = [];

  for (let i = 0; i < SHOW.length; i++) {
    const beat = SHOW[i];
    const who = beat.who === "host" ? HOST : PANELISTS.find(p => p.id === beat.who);
    if (!who) throw new Error(`No who for ${beat.who}`);

    // Skip a panelist if their API key isn't set — keeps the run honest:
    // we don't fake a model that isn't actually present.
    if (who !== HOST && !process.env[who.keyEnv]) {
      console.log(`[${String(i).padStart(2, "0")}] SKIP ${who.name} — ${who.keyEnv} not set`);
      continue;
    }

    let text;
    if (who === HOST) {
      text = beat.text ?? HOST_TEXTS[beat.kind];
    } else {
      console.log(`[${String(i).padStart(2, "0")}] ${who.name} · ${beat.kind} — calling ${who.model}…`);
      const call = callFor(who);
      text = await call(who, panelistSystem(who), panelistPrompt(who, beat.kind));
    }

    const speaker = who === HOST ? "HOST" : who.name;
    transcript.push(`\n[${speaker}]\n${text}\n`);
    console.log(`           ${text.slice(0, 80).replace(/\n/g, " ")}…`);

    const segPath = path.join(workDir, `seg-${String(i).padStart(2, "0")}-${who.id}.mp3`);
    console.log(`           rendering audio via ${process.env.ELEVENLABS_API_KEY ? "ElevenLabs" : "OpenAI TTS"} (${process.env.ELEVENLABS_API_KEY ? who.elevenVoice : who.voice})…`);
    await tts(text, who, segPath);
    segments.push(segPath);
  }

  if (segments.length === 0) {
    throw new Error("No segments produced — set at least one panelist API key + a TTS key.");
  }

  console.log(`\nStitching ${segments.length} segments…`);
  await ffmpegConcat(segments, "inaugural-roundtable.mp3");
  await fs.writeFile("inaugural-roundtable.txt", transcript.join(""));

  const stat = await fs.stat("inaugural-roundtable.mp3");
  console.log(`\n✓ inaugural-roundtable.mp3  (${(stat.size / 1024 / 1024).toFixed(1)} MB)`);
  console.log(`✓ inaugural-roundtable.txt  (transcript)`);
  console.log(`\nNext: drop the .mp3 into AIMarketplace/AIMarketplace/Resources/Samples/`);
  console.log(`and add a MediaItem entry (see README) to bundle it as an Editor Original.`);
}

main().catch(e => { console.error("\n✗", e.message); process.exit(1); });
