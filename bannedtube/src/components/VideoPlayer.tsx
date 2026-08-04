"use client";

import { useState } from "react";
import { Play, Pause, Volume2, Maximize, Settings } from "lucide-react";

interface VideoPlayerProps {
  thumbnail: string;
  title: string;
}

export default function VideoPlayer({ thumbnail, title }: VideoPlayerProps) {
  const [playing, setPlaying] = useState(false);

  return (
    <div className="relative w-full aspect-video bg-black rounded-xl overflow-hidden group cursor-pointer">
      <img
        src={thumbnail}
        alt={title}
        className="w-full h-full object-cover"
      />

      {!playing && (
        <div
          className="absolute inset-0 flex items-center justify-center bg-black/30"
          onClick={() => setPlaying(true)}
        >
          <div className="w-[68px] h-[68px] rounded-full flex items-center justify-center transition-transform hover:scale-110" style={{ background: "rgba(255, 68, 68, 0.85)" }}>
            <Play size={30} className="text-white ml-1" fill="white" />
          </div>
        </div>
      )}

      {playing && (
        <div
          className="absolute inset-0 flex items-center justify-center bg-black/10"
          onClick={() => setPlaying(false)}
        />
      )}

      <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 to-transparent p-3 opacity-0 group-hover:opacity-100 transition-opacity">
        <div className="w-full h-1 rounded-full mb-3" style={{ background: "rgba(255,255,255,0.2)" }}>
          <div
            className="bg-[var(--accent)] h-1 rounded-full"
            style={{ width: playing ? "35%" : "0%" }}
          />
        </div>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <button onClick={() => setPlaying(!playing)}>
              {playing ? (
                <Pause size={20} className="text-white" />
              ) : (
                <Play size={20} className="text-white" fill="white" />
              )}
            </button>
            <Volume2 size={20} className="text-white" />
            <span className="text-white text-xs">
              {playing ? "8:24" : "0:00"} / 24:15
            </span>
          </div>
          <div className="flex items-center gap-3">
            <Settings size={18} className="text-white" />
            <Maximize size={18} className="text-white" />
          </div>
        </div>
      </div>
    </div>
  );
}
