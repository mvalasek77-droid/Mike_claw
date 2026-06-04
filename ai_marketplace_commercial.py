#!/usr/bin/env python3
"""
AI Marketplace Commercial — v5: Elon's Chaos vs AI Marketplace's Future
========================================================================
Scene 1-3: Tesla crash, rocket explosion, crypto crash — dark, saturated red
Scene 4:   Black → "AI Marketplace" reveal
Scene 5-6: Beautiful nature, sunrise, peace — bright, vivid, hopeful
Voiceover: "AI Marketplace. Free on the App Store. Where the future is Next."
"""

import subprocess, os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path("/tmp/ai_marketplace_commercial")
W, H = 1920, 1080
FPS = 30

def get_font(size, bold=True):
    for p in ["/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial Bold.ttf", "/Library/Fonts/Arial.ttf"]:
        if os.path.exists(p):
            try: return ImageFont.truetype(p, size)
            except: continue
    return ImageFont.load_default()

def clip(src, start, duration, name, w=W, h=H):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    cmd = ["ffmpeg", "-y", "-i", str(src), "-ss", str(start), "-t", str(duration),
           "-vf", f"scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:black,fps={FPS}",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-an", str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return out if r.returncode == 0 else None

def grade(src, name, brightness=1.0, contrast=1.0, saturation=1.0):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    cmd = ["ffmpeg", "-y", "-i", str(src),
           "-vf", f"eq=brightness={brightness-1}:contrast={contrast}:saturation={saturation}",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-an", str(out)]
    subprocess.run(cmd, capture_output=True, text=True)
    return out

def fade(src, name, dur):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    fi, fo = min(0.5, dur/4), min(0.5, dur/4)
    cmd = ["ffmpeg", "-y", "-i", str(src),
           "-vf", f"fade=t=in:st=0:d={fi},fade=t=out:st={dur-fo}:d={fo}",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-an", str(out)]
    subprocess.run(cmd, capture_output=True, text=True)
    return out

def text_overlay(video, text, font_size, color, y_off, name):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = get_font(font_size, bold=True)
    bbox = draw.textbbox((0,0), text, font=font)
    tw = bbox[2] - bbox[0]
    x, y = (W - tw) // 2, H // 2 + y_off
    # Multi-layer shadow
    for dx, dy, a in [(6,6,80),(4,4,120),(2,2,180)]:
        draw.text((x+dx, y+dy), text, font=font, fill=(0,0,0,a))
    draw.text((x, y), text, font=font, fill=(*color, 255))
    tp = OUT / f"txt_{name}.png"
    img.save(tp)
    cmd = ["ffmpeg", "-y", "-i", str(video), "-i", str(tp),
           "-filter_complex", "[0:v][1:v]overlay=0:0",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-an", str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return out if r.returncode == 0 else video

def title_card(text, subtitle, duration, name, bg=(0,0,0), tc=(255,255,255), sc=(0,230,255)):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    total = int(duration * FPS)
    font_big = get_font(min(120, int(W / max(len(text),1) * 1.2)) if text else 120)
    font_sub = get_font(48)
    
    img = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(img)
    # Glow
    cx, cy = W//2, H//2 - 40
    max_r = 400
    for r in range(max_r, 0, -3):
        a = int(18 * (1 - r/max_r))
        draw.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(max(0,a//3 if bg[0]<10 else a), max(0,a//2 if bg[1]<10 else a*2), max(0,a*3 if bg[2]<10 else a)))
    
    if text:
        bbox = draw.textbbox((0,0), text, font=font_big)
        tw = bbox[2] - bbox[0]
        x = (W - tw) // 2
        draw.text((x+5, 415), text, font=font_big, fill=(15,15,25))
        draw.text((x, 410), text, font=font_big, fill=tc)
    if subtitle:
        bbox2 = draw.textbbox((0,0), subtitle, font=font_sub)
        tw2 = bbox2[2] - bbox2[0]
        x2 = (W - tw2) // 2
        draw.text((x2+2, 522), subtitle, font=font_sub, fill=(8,8,15))
        draw.text((x2, 520), subtitle, font=font_sub, fill=sc)
    
    frame_dir = OUT / f"frames_{name}"
    frame_dir.mkdir(exist_ok=True)
    black = Image.new("RGB", (W, H), bg)
    fade_n = int(0.8 * FPS)
    for f in range(total):
        if f < fade_n:
            frame = Image.blend(black, img, f/fade_n)
        elif f > total - fade_n:
            frame = Image.blend(black, img, (total-f)/fade_n)
        else:
            frame = img
        frame.save(frame_dir / f"frame_{f:05d}.png")
    
    cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", str(frame_dir / "frame_%05d.png"),
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-an", str(out)]
    subprocess.run(cmd, capture_output=True, text=True)
    for f in frame_dir.glob("*.png"): f.unlink()
    frame_dir.rmdir()
    print(f"  Title '{text}' ✓ ({duration}s)")
    return out

def concat(clips, name):
    out = OUT / f"{name}.mp4"
    if out.exists(): return out
    cf = OUT / "concat_list.txt"
    with open(cf, "w") as f:
        for c in clips: f.write(f"file '{c}'\n")
    cmd = ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(cf),
           "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-an", str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return out if r.returncode == 0 else None

def mux(video, audio, name):
    out = OUT / f"{name}.mp4"
    cmd = ["ffmpeg", "-y", "-i", str(video), "-i", str(audio),
           "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", str(out)]
    subprocess.run(cmd, capture_output=True, text=True)
    return out if out.exists() else video

def build():
    print("🎬 AI Marketplace Commercial — Elon's Chaos vs Our Future\n")
    
    # ─── CHAOS: Elon's world falling apart ───
    
    # Scene 1: Tesla crash (3s) — dark, red-tinged, dramatic
    print("🚗 Scene 1: Tesla crash...")
    c = clip(OUT/"tesla_crash.mp4", 1, 3, "c1_raw")
    if c:
        # Extra dark, high contrast, desaturated with red tint
        c = grade(c, "c1", brightness=0.35, contrast=1.6, saturation=0.2)
        c = text_overlay(c, "TESLA", 160, (220, 30, 30), -220, "c1_text")
        c = fade(c, "c1_final", 3)
    
    # Scene 2: Rocket explosion (3s) — fiery, intense
    print("🚀 Scene 2: Rocket explosion...")
    c2 = clip(OUT/"rocket_boom.mp4", 4, 3, "c2_raw")
    if c2:
        c2 = grade(c2, "c2", brightness=0.45, contrast=1.5, saturation=0.35)
        c2 = text_overlay(c2, "BOOM", 160, (255, 100, 20), -220, "c2_text")
        c2 = fade(c2, "c2_final", 3)
    
    # Scene 3: Crypto crash (3s) — cold, data-screens, red
    print("📉 Scene 3: Crypto crash...")
    c3 = clip(OUT/"crypto_crash.mp4", 1, 3, "c3_raw")
    if c3:
        c3 = grade(c3, "c3", brightness=0.25, contrast=1.7, saturation=0.15)
        c3 = text_overlay(c3, "CRYPTO", 160, (220, 30, 30), -220, "c3_text")
        c3 = fade(c3, "c3_final", 3)
    
    # ─── TRANSITION: Black screen with brief red flash ───
    print("⚡ Scene 4: Black transition...")
    # Black pause — let the chaos sink in
    black = title_card("", "", 1.5, "c4_black", bg=(2,2,2), tc=(2,2,2), sc=(2,2,2))
    
    # ─── FUTURE: AI Marketplace reveal ───
    print("✨ Scene 5: AI Marketplace reveal...")
    banner = title_card("AI Marketplace", "", 4, "c5_banner",
                         bg=(2, 4, 14), tc=(255, 255, 255), sc=(0, 230, 255))
    
    # Scene 6: Beautiful nature (5s) — bright, vivid, hopeful
    print("🌄 Scene 6: Beautiful nature...")
    c6 = clip(OUT/"nature_ocean.mp4", 5, 5, "c6_raw")
    if not c6:
        c6 = clip(OUT/"nature_aerial.mp4", 3, 5, "c6_raw")
    if not c6:
        c6 = clip(OUT/"nature_mountain.mp4", 3, 5, "c6_raw")
    if c6:
        c6 = grade(c6, "c6", brightness=1.15, contrast=1.05, saturation=1.4)
        c6 = text_overlay(c6, "Where the future is Next", 60, (255, 255, 255), 160, "c6_tag")
        c6 = text_overlay(c6, "Free on the App Store", 40, (0, 230, 255), 230, "c6_sub")
        c6 = fade(c6, "c6_final", 5)
    
    # Scene 7: Final nature beauty shot (4s) — tagline, app store
    print("🏔️ Scene 7: Final beauty...")
    c7 = clip(OUT/"nature_mountain.mp4", 2, 4, "c7_raw")
    if not c7:
        c7 = clip(OUT/"nature_aerial.mp4", 4, 4, "c7_raw")
    if c7:
        c7 = grade(c7, "c7", brightness=1.2, contrast=1.1, saturation=1.5)
        c7 = text_overlay(c7, "AI Marketplace", 80, (255, 255, 255), -60, "c7_title")
        c7 = text_overlay(c7, "Free on the App Store", 40, (0, 230, 255), 20, "c7_appstore")
        c7 = fade(c7, "c7_final", 4)
    
    # ─── Compose ───
    clips = [c for c in [c, c2, c3, black, banner, c6, c7] if c is not None]
    
    if not clips:
        print("❌ No clips!")
        return
    
    print(f"\n🔗 Composing {len(clips)} clips...")
    final = concat(clips, "final_narration")
    if not final:
        print("❌ Concat failed")
        return
    
    # Voiceover — pad with silence to hit at the right moment
    voice = OUT / "voiceover_final.ogg"
    # Convert to wav, pad 10s silence before, 3s after
    subprocess.run(["ffmpeg", "-y", "-i", str(voice), "-ar", "44100", "-ac", "2", OUT/"voice.wav"],
                   capture_output=True, text=True)
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "10",
                   "-c:a", "pcm_s16le", OUT/"silence_before.wav"], capture_output=True, text=True)
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "3",
                   "-c:a", "pcm_s16le", OUT/"silence_after.wav"], capture_output=True, text=True)
    
    # Concat silence + voice + silence
    with open(OUT/"audio_parts.txt", "w") as f:
        f.write(f"file 'silence_before.wav'\n")
        f.write(f"file 'voice.wav'\n")
        f.write(f"file 'silence_after.wav'\n")
    subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(OUT/"audio_parts.txt"),
                   "-c:a", "aac", "-b:a", "192k", OUT/"audio_final.m4a"],
                   capture_output=True, text=True)
    
    audio = OUT / "audio_final.m4a"
    if audio.exists():
        print(f"🎤 Adding voiceover (delayed 10s)")
        final = mux(final, audio, "ai_marketplace_commercial")
    
    if final and final.exists():
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                           "-of", "default=noprint_wrappers=1:nokey=1", str(final)],
                          capture_output=True, text=True)
        dur = float(r.stdout.strip()) if r.stdout.strip() else 0
        sz = final.stat().st_size / (1024*1024)
        print(f"\n✅ COMMERCIAL READY")
        print(f"   Duration: {dur:.1f}s | Size: {sz:.1f}MB | {W}x{H}")
        print(f"   MEDIA:{final}")
        return final
    print("❌ Failed")

if __name__ == "__main__":
    build()