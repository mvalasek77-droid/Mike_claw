"use client";

import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import Shell from "@/components/Shell";
import VideoCard from "@/components/VideoCard";
import { searchVideos } from "@/lib/data";

function SearchContent() {
  const searchParams = useSearchParams();
  const query = searchParams.get("q") || "";
  const results = searchVideos(query);

  return (
    <Shell>
      <div className="max-w-[1000px] mx-auto px-4 sm:px-6 py-4">
        {query && (
          <p className="text-sm text-[var(--text-secondary)] mb-4">
            {results.length} results for &ldquo;{query}&rdquo;
          </p>
        )}

        <div className="flex flex-col gap-4">
          {results.map((video) => (
            <VideoCard key={video.id} video={video} layout="list" />
          ))}
        </div>

        {results.length === 0 && query && (
          <div className="text-center py-20">
            <p className="text-[var(--text-secondary)] text-lg mb-2">
              No results found for &ldquo;{query}&rdquo;
            </p>
            <p className="text-sm text-[var(--text-secondary)]">
              Try different keywords or check your spelling
            </p>
          </div>
        )}
      </div>
    </Shell>
  );
}

export default function SearchPage() {
  return (
    <Suspense
      fallback={
        <Shell>
          <div className="flex items-center justify-center h-[60vh]">
            <div className="text-[var(--text-secondary)]">Searching...</div>
          </div>
        </Shell>
      }
    >
      <SearchContent />
    </Suspense>
  );
}
