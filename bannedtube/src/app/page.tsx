"use client";

import { useState } from "react";
import Shell from "@/components/Shell";
import VideoCard from "@/components/VideoCard";
import CategoryBar from "@/components/CategoryBar";
import { getVideosByCategory } from "@/lib/data";

export default function Home() {
  const [category, setCategory] = useState("All");
  const filteredVideos = getVideosByCategory(category);

  return (
    <Shell>
      <div className="px-4 sm:px-6 lg:px-8 py-4">
        <CategoryBar active={category} onChange={setCategory} />

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-x-4 gap-y-8 mt-4">
          {filteredVideos.map((video) => (
            <VideoCard key={video.id} video={video} />
          ))}
        </div>

        {filteredVideos.length === 0 && (
          <div className="text-center py-20">
            <p className="text-[var(--text-secondary)] text-lg">
              No videos found in this category
            </p>
          </div>
        )}
      </div>
    </Shell>
  );
}
