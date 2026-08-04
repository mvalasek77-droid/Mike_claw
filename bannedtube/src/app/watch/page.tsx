"use client";

import { useSearchParams } from "next/navigation";
import { Suspense } from "react";
import Link from "next/link";
import {
  ThumbsUp,
  ThumbsDown,
  Share2,
  Download,
  Flag,
  MoreHorizontal,
  CheckCircle,
} from "lucide-react";
import Shell from "@/components/Shell";
import VideoPlayer from "@/components/VideoPlayer";
import VideoCard from "@/components/VideoCard";
import CommentSection from "@/components/CommentSection";
import {
  getVideoById,
  videos,
  formatViews,
  formatSubscribers,
} from "@/lib/data";

function WatchContent() {
  const searchParams = useSearchParams();
  const videoId = searchParams.get("v") || "v1";
  const video = getVideoById(videoId);

  if (!video) {
    return (
      <Shell>
        <div className="flex items-center justify-center h-[60vh]">
          <p className="text-[var(--text-secondary)] text-lg">
            Video not found
          </p>
        </div>
      </Shell>
    );
  }

  const relatedVideos = videos.filter((v) => v.id !== video.id).slice(0, 8);

  return (
    <Shell>
      <div className="flex flex-col lg:flex-row gap-6 px-4 sm:px-6 lg:px-8 py-4 max-w-[1800px] mx-auto">
        <div className="flex-1 min-w-0">
          <VideoPlayer thumbnail={video.thumbnail} title={video.title} />

          <h1 className="text-xl font-semibold mt-3 mb-2">{video.title}</h1>

          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-4">
            <div className="flex items-center gap-3">
              <Link href={`/channel/${video.channel.id}`}>
                <img
                  src={video.channel.avatar}
                  alt={video.channel.name}
                  className="w-10 h-10 rounded-full"
                />
              </Link>
              <div>
                <Link
                  href={`/channel/${video.channel.id}`}
                  className="text-sm font-medium flex items-center gap-1 no-underline text-[var(--text-primary)]"
                >
                  {video.channel.name}
                  {video.channel.verified && (
                    <CheckCircle size={14} className="text-[var(--text-secondary)]" />
                  )}
                </Link>
                <p className="text-xs text-[var(--text-secondary)]">
                  {formatSubscribers(video.channel.subscribers)}
                </p>
              </div>
              <button className="btn-subscribe ml-2">Subscribe</button>
            </div>

            <div className="flex items-center gap-2 flex-wrap">
              <div className="flex items-center rounded-full bg-[var(--bg-tertiary)] overflow-hidden">
                <button className="like-btn rounded-r-none border-r border-[var(--border)]">
                  <ThumbsUp size={18} />
                  {(video.likes / 1000).toFixed(0)}K
                </button>
                <button className="like-btn rounded-l-none">
                  <ThumbsDown size={18} />
                </button>
              </div>
              <button className="like-btn">
                <Share2 size={18} />
                Share
              </button>
              <button className="like-btn">
                <Download size={18} />
                Save
              </button>
              <button className="like-btn">
                <Flag size={18} />
              </button>
              <button className="like-btn">
                <MoreHorizontal size={18} />
              </button>
            </div>
          </div>

          <div className="bg-[var(--bg-tertiary)] rounded-xl p-3 mb-4">
            <p className="text-sm font-medium mb-1">
              {formatViews(video.views)} &middot; {video.uploadedAt}
            </p>
            <p className="text-sm text-[var(--text-primary)] whitespace-pre-line">
              {video.description}
            </p>
            <div className="flex gap-2 mt-2 flex-wrap">
              {video.tags.map((tag) => (
                <span
                  key={tag}
                  className="text-xs text-blue-400 cursor-pointer hover:underline"
                >
                  #{tag}
                </span>
              ))}
            </div>
          </div>

          <CommentSection />
        </div>

        <div className="w-full lg:w-[400px] flex-shrink-0">
          <h3 className="text-sm font-medium mb-4">Up next</h3>
          <div className="flex flex-col gap-3">
            {relatedVideos.map((v) => (
              <VideoCard key={v.id} video={v} layout="list" />
            ))}
          </div>
        </div>
      </div>
    </Shell>
  );
}

export default function WatchPage() {
  return (
    <Suspense
      fallback={
        <Shell>
          <div className="flex items-center justify-center h-[60vh]">
            <div className="text-[var(--text-secondary)]">Loading...</div>
          </div>
        </Shell>
      }
    >
      <WatchContent />
    </Suspense>
  );
}
