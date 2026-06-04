#!/usr/bin/env python3
"""
AI Marketplace Commercial — v6: Cinematic Pro
===============================================
Real crash/explosion footage + typography that looks like a Super Bowl ad.

Chaos sequence: Real car crashes, real explosions, real fire
                Overlay: kinetic type (large, tracked, Helvetica Neue Bold)
Transition:  Black gap → WHITE FLASH → AI MARKETPLACE reveal
Hope:        Bright nature, sunrise, freedom
              Tagline: clean, centered, breathing typography
Voiceover:   "AI Marketplace. Free on the App Store. Where the future is Next."
"""

import subprocess, os, math, shutil
from pathlib import Path

OUT = Path("/tmp/ai_marketplace_commercial_v6")
OUT.mkdir(exist_ok=True)
W, H = 1920, 1080
FPS = 30
FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_BOLD = "/System/Library/Fonts/HelveticaNeue.ttc"  # Helvetica Neue Bold is index 1 in TTC

def ff(cmd, **kw):
    """Run ffmpeg command, return result."""
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=kw.get("timeout", 120))
    if r.returncode != 0 and kw.get("check", True):
        print(f"  FF ERROR: {r.stderr[-500:]}")
    return r

def clip(src, start, duration, name, w=W, h=H):
    """Extract and scale a clip from source video."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    cmd = [
        "ffmpeg", "-y", "-i", str(src), "-ss", str(start), "-t", str(duration),
        "-vf", f"scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2:black,fps={FPS}",
        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-an", str(out)
    ]
    ff(cmd)
    return out if out.exists() else None

def grade(src, name, brightness=0, contrast=1, saturation=1, gamma=1, tint_r=0, tint_g=0, tint_b=0):
    """Color grade: brightness (-1..1), contrast, saturation, gamma, and color tint."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    # Build filter chain
    filters = []
    # Color adjustments
    if brightness != 0 or contrast != 1 or gamma != 1 or saturation != 1:
        b = brightness
        filters.append(f"eq=brightness={b}:contrast={contrast}:gamma={gamma}:saturation={saturation}")
    # Color tint overlay (subtle color wash)
    if tint_r > 0 or tint_g > 0 or tint_b > 0:
        filters.append(f"colorbalance=rs={tint_r}:gs={tint_g}:bs={tint_b}")
    filter_str = ",".join(filters) if filters else "null"
    cmd = [
        "ffmpeg", "-y", "-i", str(src),
        "-vf", filter_str,
        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-an", str(out)
    ]
    ff(cmd)
    return out if out.exists() else src

def cinematic_text(video, text, name, font_size=140, color="white", 
                    shadow=True, shadow_color="black", shadow_offset=4,
                    y_offset=0, enable_start=0, enable_end=None,
                    font=FONT, font_si=1,  # font_si = font face index in TTC (1 = Bold)
                    borderw=0, bordercolor="black",
                    x_align="center"):
    """
    Professional text overlay using ffmpeg drawtext with:
    - Multi-layer drop shadow for depth
    - Optional border/stroke
    - Precise timing control
    - Center/left/right alignment
    """
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    
    dur_cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", 
               "-of", "default=noprint_wrappers=1:nokey=1", str(video)]
    r = ff(dur_cmd, check=False)
    vid_dur = float(r.stdout.strip()) if r.stdout.strip() else 10
    if enable_end is None:
        enable_end = vid_dur
    
    # Calculate Y position
    if y_offset == 0:
        y_pos = "(h-text_h)/2"
    else:
        y_pos = f"(h-text_h)/2+{y_offset}"
    
    # X alignment
    if x_align == "center":
        x_pos = "(w-text_w)/2"
    elif x_align == "left":
        x_pos = f"(w*0.08)"
    elif x_align == "right":
        x_pos = f"(w-text_w-w*0.08)"
    else:
        x_pos = "(w-text_w)/2"
    
    # Build drawtext filter chain - shadow first, then main text
    drawtexts = []
    
    # Layer 1: Deep shadow (offset 6px, semi-transparent)
    if shadow:
        for dx, dy, alpha in [(6,6,"0x60000000"), (3,3,"0xA0000000"), (1,1,"0xC0000000")]:
            drawtexts.append(
                f"drawtext=fontfile='{font}':fontindex={font_si}:text='{text}'"
                f":fontsize={font_size}:fontcolor={shadow_color}@0.8"
                f":x={x_pos}+{dx}:y={y_pos}+{dy}"
                f":enable='between(t,{enable_start},{enable_end})'"
                f":borderw=0"
            )
    
    # Layer 2: Main text with border
    drawtexts.append(
        f"drawtext=fontfile='{font}':fontindex={font_si}:text='{text}'"
        f":fontsize={font_size}:fontcolor={color}"
        f":x={x_pos}:y={y_pos}"
        f":enable='between(t,{enable_start},{enable_end})'"
        f":borderw={borderw}:bordercolor={bordercolor}"
    )
    
    filter_str = ",".join(drawtexts)
    # Need to split input for multiple drawtexts
    # Actually for same text we just stack them in one filter
    # But ffmpeg drawtext can't do multiple on same stream easily, use overlay approach instead
    
    # Simpler approach: render text as PNG overlay with PIL for maximum control
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    
    # Create text overlay frame
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Load font
    try:
        font_obj = ImageFont.truetype(font, font_size, index=font_si)
    except:
        font_obj = ImageFont.truetype(font, font_size)
    
    bbox = draw.textbbox((0, 0), text, font=font_obj)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    
    if x_align == "center":
        tx = (W - tw) // 2
    elif x_align == "left":
        tx = int(W * 0.08)
    else:
        tx = W - tw - int(W * 0.08)
    
    if y_offset == 0:
        ty = (H - th) // 2 - bbox[1]
    else:
        ty = (H - th) // 2 + y_offset - bbox[1]
    
    # Multi-layer shadow for cinematic depth
    if shadow:
        # Deep shadow
        for dx, dy, a in [(8, 8, 60), (5, 5, 100), (3, 3, 150)]:
            draw.text((tx + dx, ty + dy), text, font=font_obj, fill=(0, 0, 0, a))
        # Glow spread
        shadow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        shadow_draw = ImageDraw.Draw(shadow_layer)
        for dx, dy, a in [(4, 4, 80), (2, 2, 120)]:
            shadow_draw.text((tx + dx, ty + dy), text, font=font_obj, fill=(0, 0, 0, a))
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=3))
        img = Image.alpha_composite(img, shadow_layer)
        draw = ImageDraw.Draw(img)
    
    # Border/stroke
    if borderw > 0:
        bc = (0, 0, 0, 255)  # black border
        for adj in range(-borderw, borderw + 1):
            for adj2 in range(-borderw, borderw + 1):
                if adj != 0 or adj2 != 0:
                    draw.text((tx + adj, ty + adj2), text, font=font_obj, fill=bc)
    
    # Main text
    if color == "white":
        fill = (255, 255, 255, 255)
    elif color.startswith("#"):
        r, g, b = int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
        fill = (r, g, b, 255)
    elif color == "red":
        fill = (220, 30, 30, 255)
    elif color == "cyan":
        fill = (0, 230, 255, 255)
    elif color == "orange":
        fill = (255, 140, 20, 255)
    elif color == "gold":
        fill = (255, 215, 0, 255)
    else:
        fill = (255, 255, 255, 255)
    
    draw.text((tx, ty), text, font=font_obj, fill=fill)
    
    # Subtle outer glow on text
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.text((tx, ty), text, font=font_obj, fill=(*fill[:3], 40))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=8))
    img = Image.alpha_composite(glow, img)
    
    tp = OUT / f"txt_{name}.png"
    img.save(tp)
    
    cmd = [
        "ffmpeg", "-y", "-i", str(video), "-i", str(tp),
        "-filter_complex", "[0:v][1:v]overlay=0:0:enable='between(t,0,999)'",
        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-an", str(out)
    ]
    ff(cmd)
    return out if out.exists() else video

def fade(src, name, dur, fi=0.5, fo=0.5, fade_to="black"):
    """Fade in/out."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    color = "0x000000" if fade_to == "black" else "0xFFFFFF"
    vfs = f"fade=t=in:st=0:d={min(fi, dur/4)},fade=t=out:st={dur-min(fo, dur/4)}:d={min(fo, dur/4)}"
    cmd = ["ffmpeg", "-y", "-i", str(src), "-vf", vfs,
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-an", str(out)]
    ff(cmd)
    return out if out.exists() else src

def title_reveal(text, subtitle, duration, name, 
                 bg_color=(2, 2, 10), text_color=(255, 255, 255), 
                 sub_color=(0, 220, 255),
                 glow_color=(0, 100, 200)):
    """Cinematic title card with glow reveal animation."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    
    total_frames = int(duration * FPS)
    
    # Render the main text
    font_big = ImageFont.truetype(FONT, 140, index=1)  # Helvetica Neue Bold
    font_sub = ImageFont.truetype(FONT, 52, index=1)
    
    # Pre-render the text image
    text_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(text_img)
    
    # Calculate text position
    bbox = draw.textbbox((0, 0), text, font=font_big)
    tw = bbox[2] - bbox[0]
    tx = (W - tw) // 2
    ty = H // 2 - 80 - bbox[1]
    
    # Multi-layer shadow
    for dx, dy, a in [(10, 10, 40), (6, 6, 80), (3, 3, 140), (1, 1, 200)]:
        draw.text((tx + dx, ty + dy), text, font=font_big, fill=(0, 0, 0, a))
    
    # Main text
    draw.text((tx, ty), text, font=font_big, fill=(*text_color, 255))
    
    # Subtitle
    if subtitle:
        bbox2 = draw.textbbox((0, 0), subtitle, font=font_sub)
        tw2 = bbox2[2] - bbox2[0]
        tx2 = (W - tw2) // 2
        ty2 = ty + 180
        draw.text((tx2 + 2, ty2 + 2), subtitle, font=font_sub, fill=(0, 0, 0, 160))
        draw.text((tx2, ty2), subtitle, font=font_sub, fill=(*sub_color, 255))
    
    # Create glow layer
    glow_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.text((tx, ty), text, font=font_big, fill=(*glow_color, 60))
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=20))
    
    # Create darkened text for fade
    dim_img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dim_draw = ImageDraw.Draw(dim_img)
    dim_draw.text((tx, ty), text, font=font_big, fill=(*text_color, 80))
    if subtitle:
        bbox2 = draw.textbbox((0, 0), subtitle, font=font_sub)
        tw2 = bbox2[2] - bbox2[0]
        tx2 = (W - tw2) // 2
        ty2 = ty + 180
        dim_draw.text((tx2, ty2), subtitle, font=font_sub, fill=(*sub_color, 50))
    
    # Background
    bg = Image.new("RGB", (W, H), bg_color)
    # Subtle radial gradient
    from PIL import ImageDraw
    bg_draw = ImageDraw.Draw(bg)
    # Dark vignette effect
    for i in range(20):
        r = W - i * 50
        a = max(0, 3 - i // 7)
        bg_draw.ellipse([W//2-r, H//2-r, W//2+r, H//2+r], fill=(bg_color[0]+a, bg_color[1]+a, bg_color[2]+a))
    
    # Render frames with animation
    frame_dir = OUT / f"frames_{name}"
    frame_dir.mkdir(exist_ok=True)
    
    fade_in_frames = int(1.2 * FPS)  # 1.2s fade in
    fade_out_frames = int(0.8 * FPS)  # 0.8s fade out
    glow_peak = int(0.6 * FPS)  # glow peaks at 0.6s
    
    for f in range(total_frames):
        frame = bg.copy().convert("RGBA")
        
        if f < fade_in_frames:
            # Fade in: dim text → full text with expanding glow
            alpha = f / fade_in_frames
            # Text alpha grows
            text_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            if f < glow_peak:
                # During glow: blend dim → full
                glow_alpha = min(1.0, f / glow_peak)
                text_layer = Image.alpha_composite(
                    Image.new("RGBA", (W, H), (0, 0, 0, 0)),
                    dim_img if glow_alpha < 0.5 else text_img
                )
                # Overlay glow
                glow_scaled = glow_img.copy()
                # Scale glow from small to full
                glow_alpha_val = int(255 * glow_alpha * 0.7)
                glow_scaled.putalpha(glow_scaled.split()[-1].point(lambda x: min(255, int(x * glow_alpha_val / 255))))
                text_layer = Image.alpha_composite(text_layer, glow_scaled)
            else:
                # Glow fading, text solid
                glow_decay = max(0, 1.0 - (f - glow_peak) / (fade_in_frames - glow_peak))
                text_layer = text_img.copy()
                if glow_decay > 0:
                    glow_scaled = glow_img.copy()
                    glow_scaled.putalpha(glow_scaled.split()[-1].point(lambda x: min(255, int(x * glow_decay * 0.5))))
                    text_layer = Image.alpha_composite(text_layer, glow_scaled)
            frame = Image.alpha_composite(frame, text_layer)
        elif f > total_frames - fade_out_frames:
            # Fade out
            alpha = (total_frames - f) / fade_out_frames
            text_layer = text_img.copy()
            text_layer.putalpha(text_layer.split()[-1].point(lambda x: int(x * alpha)))
            frame = Image.alpha_composite(frame, text_layer)
        else:
            # Full text, subtle glow
            frame = Image.alpha_composite(frame, text_img)
        
        frame = frame.convert("RGB")
        frame.save(frame_dir / f"frame_{f:05d}.png")
    
    # Encode video
    cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", str(frame_dir / "frame_%05d.png"),
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-an", str(out)]
    ff(cmd)
    
    # Cleanup frames
    for f in frame_dir.glob("*.png"):
        f.unlink()
    frame_dir.rmdir()
    
    print(f"  Title '{text}' ✓ ({duration}s)")
    return out

def flash_transition(duration=0.3, name="flash"):
    """White flash transition."""
    from PIL import Image
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    total = int(duration * FPS)
    frame_dir = OUT / f"frames_{name}"
    frame_dir.mkdir(exist_ok=True)
    for f in range(total):
        if f < total // 2:
            # Fade to white
            v = int(255 * (f / (total // 2)))
        else:
            # Fade from white to black
            v = int(255 * (1 - (f - total // 2) / (total // 2)))
        img = Image.new("RGB", (W, H), (v, v, v))
        img.save(frame_dir / f"frame_{f:05d}.png")
    cmd = ["ffmpeg", "-y", "-framerate", str(FPS), "-i", str(frame_dir / "frame_%05d.png"),
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-an", str(out)]
    ff(cmd)
    for f in frame_dir.glob("*.png"):
        f.unlink()
    frame_dir.rmdir()
    return out

def concat(clips, name):
    """Concatenate video clips."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    cf = OUT / "concat_list.txt"
    with open(cf, "w") as f:
        for c in clips:
            f.write(f"file '{c}'\n")
    cmd = ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(cf),
           "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-an", str(out)]
    ff(cmd)
    return out if out.exists() else None

def mux(video, audio, name):
    """Mux video + audio."""
    out = OUT / f"{name}.mp4"
    if out.exists():
        return out
    cmd = ["ffmpeg", "-y", "-i", str(video), "-i", str(audio),
           "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", str(out)]
    ff(cmd)
    return out if out.exists() else video


def build():
    print("🎬 AI Marketplace Commercial — v6 CINEMATIC PRO\n")
    SRC = Path("/tmp/ai_marketplace_commercial")
    
    # ─── SCENE 1: TESLA CRASH (3.5s) ─── Dark, red-tinted, dramatic
    print("🚗 Scene 1: Tesla crash — dark, red-tinged...")
    s1 = clip(SRC / "mixkit_car_crash.mp4", 0, 3.5, "s1_raw")
    if s1:
        s1 = grade(s1, "s1_dark", brightness=-0.25, contrast=1.4, saturation=0.3, 
                   tint_r=0.4, tint_g=-0.05, tint_b=-0.15)
        s1 = cinematic_text(s1, "TESLA", "s1_text", font_size=180, color="red",
                            shadow=True, y_offset=-180)
        s1 = fade(s1, "s1_final", 3.5, fi=0.6, fo=0.5)
    
    # ─── SCENE 2: ROCKET EXPLOSION (3.5s) ─── Bright fire, orange, explosive
    print("🚀 Scene 2: Rocket explosion — fiery, intense...")
    s2 = clip(SRC / "mixkit_explosion.mp4", 2, 3.5, "s2_raw")
    if s2:
        s2 = grade(s2, "s2_hot", brightness=-0.1, contrast=1.5, saturation=0.5,
                   tint_r=0.5, tint_g=0.1, tint_b=-0.2)
        s2 = cinematic_text(s2, "BOOM", "s2_text", font_size=200, color="orange",
                            shadow=True, y_offset=-200)
        s2 = fade(s2, "s2_final", 3.5, fi=0.4, fo=0.5)
    
    # ─── SCENE 3: FIRE / AFTERMATH (3s) ─── Burning, apocalyptic
    print("🔥 Scene 3: Fire aftermath...")
    s3 = clip(SRC / "fire.mp4", 3, 3, "s3_raw")
    if s3:
        s3 = grade(s3, "s3_burn", brightness=-0.15, contrast=1.3, saturation=0.8,
                   tint_r=0.3, tint_g=0.0, tint_b=-0.2)
        s3 = fade(s3, "s3_final", 3, fi=0.3, fo=0.8)
    
    # ─── SCENE 4: BLACK PAUSE + WHITE FLASH (1.2s) ───
    print("⚡ Scene 4: Black → White flash...")
    s4_black = title_reveal("", "", 0.8, "s4_black", bg_color=(1, 1, 3))
    s4_flash = flash_transition(0.4, "s4_flash")
    
    # ─── SCENE 5: AI MARKETPLACE REVEAL (4s) ─── Dark bg, text glows in
    print("✨ Scene 5: AI MARKETPLACE reveal — cinematic glow animation...")
    s5 = title_reveal("AI Marketplace", "Free on the App Store", 4, "s5_reveal",
                      bg_color=(2, 4, 14), text_color=(255, 255, 255),
                      sub_color=(0, 220, 255), glow_color=(0, 120, 255))
    
    # ─── SCENE 6: NATURE — bright, hopeful (5s) ───
    print("🌄 Scene 6: Nature — bright, vivid...")
    s6 = clip(SRC / "mixkit_river.mp4", 3, 5, "s6_raw")
    if not s6:
        s6 = clip(SRC / "mixkit_aerial.mp4", 3, 5, "s6_raw")
    if not s6:
        s6 = clip(SRC / "mixkit_sunset.mp4", 2, 5, "s6_raw")
    if s6:
        s6 = grade(s6, "s6_bright", brightness=0.08, contrast=1.1, saturation=1.4)
        s6 = cinematic_text(s6, "Where the future is Next", "s6_tag", 
                           font_size=70, color="white", shadow=True, y_offset=180)
        s6 = fade(s6, "s6_final", 5, fi=0.8, fo=0.6)
    
    # ─── SCENE 7: FINAL BEAUTY SHOT (4s) ─── Tagline, App Store
    print("🏔️ Scene 7: Final beauty — sunset/mountain...")
    s7 = clip(SRC / "mixkit_sunset.mp4", 3, 4, "s7_raw")
    if not s7:
        s7 = clip(SRC / "mixkit_aerial.mp4", 5, 4, "s7_raw")
    if s7:
        s7 = grade(s7, "s7_warm", brightness=0.05, contrast=1.05, saturation=1.5,
                   tint_r=0.05, tint_g=0.0, tint_b=-0.05)
        s7 = cinematic_text(s7, "AI Marketplace", "s7_title",
                           font_size=100, color="white", shadow=True, y_offset=-80)
        s7 = cinematic_text(s7, "Free on the App Store", "s7_cta",
                           font_size=48, color="cyan", shadow=True, y_offset=10,
                           enable_start=1, enable_end=4)
        s7 = fade(s7, "s7_final", 4, fi=0.5, fo=1.2)
    
    # ─── COMPOSE ───
    clips = [c for c in [s1, s2, s3, s4_black, s4_flash, s5, s6, s7] if c is not None]
    
    if not clips:
        print("❌ No clips!")
        return
    
    print(f"\n🔗 Composing {len(clips)} clips...")
    final = concat(clips, "final_raw")
    if not final:
        print("❌ Concat failed")
        return
    
    # ─── VOICEOVER ───
    voice = SRC / "voiceover_final.ogg"
    if voice.exists():
        # Convert and pad
        subprocess.run(["ffmpeg", "-y", "-i", str(voice), "-ar", "44100", "-ac", "2",
                        OUT / "voice.wav"], capture_output=True, text=True)
        subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                        "-t", "10", "-c:a", "pcm_s16le", OUT / "silence_before.wav"],
                       capture_output=True, text=True)
        subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                        "-t", "4", "-c:a", "pcm_s16le", OUT / "silence_after.wav"],
                       capture_output=True, text=True)
        
        with open(OUT / "audio_parts.txt", "w") as f:
            f.write(f"file 'silence_before.wav'\n")
            f.write(f"file 'voice.wav'\n")
            f.write(f"file 'silence_after.wav'\n")
        
        subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0",
                        "-i", str(OUT / "audio_parts.txt"),
                        "-c:a", "aac", "-b:a", "192k", OUT / "audio_final.m4a"],
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
        sz = final.stat().st_size / (1024 * 1024)
        print(f"\n✅ COMMERCIAL READY")
        print(f"   Duration: {dur:.1f}s | Size: {sz:.1f}MB | {W}x{H}")
        print(f"   MEDIA:{final}")
        
        # Also make a 540p version for Telegram
        small = OUT / "ai_marketplace_commercial_small.mp4"
        cmd = ["ffmpeg", "-y", "-i", str(final),
               "-vf", "scale=960:540", "-c:v", "libx264", "-preset", "medium",
               "-crf", "23", "-c:a", "aac", "-b:a", "128k", str(small)]
        ff(cmd)
        if small.exists():
            sz2 = small.stat().st_size / (1024 * 1024)
            print(f"   Small: {sz2:.1f}MB (540p)")
        
        return final
    
    print("❌ Failed")


if __name__ == "__main__":
    build()