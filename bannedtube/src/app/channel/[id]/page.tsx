"use client";

import { use } from "react";
import Link from "next/link";
import { CheckCircle, Bell } from "lucide-react";
import Shell from "@/components/Shell";
import VideoCard from "@/components/VideoCard";
import {
  getChannelById,
  getVideosByChannel,
  formatSubscribers,
  formatViews,
} from "@/lib/data";

export default function ChannelPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const channel = getChannelById(id);

  if (!channel) {
    return (
      <Shell>
        <div className="flex items-center justify-center h-[60vh]">
          <p className="text-[var(--text-secondary)] text-lg">
            Channel not found
          </p>
        </div>
      </Shell>
    );
  }

  const channelVideos = getVideosByChannel(id);

  return (
    <Shell>
      <div>
        {channel.banner && (
          <div className="w-full h-[120px] sm:h-[180px] overflow-hidden">
            <img
              src={channel.banner}
              alt={`${channel.name} banner`}
              className="w-full h-full object-cover"
            />
          </div>
        )}

        <div className="max-w-[1200px] mx-auto px-4 sm:px-6">
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 py-4 border-b border-[var(--border)]">
            <img
              src={channel.avatar}
              alt={channel.name}
              className="w-20 h-20 rounded-full"
            />
            <div className="flex-1">
              <h1 className="text-2xl font-bold flex items-center gap-2">
                {channel.name}
                {channel.verified && (
                  <CheckCircle
                    size={18}
                    className="text-[var(--text-secondary)]"
                  />
                )}
              </h1>
              <p className="text-sm text-[var(--text-secondary)] mt-1">
                {formatSubscribers(channel.subscribers)} &middot;{" "}
                {channelVideos.length} videos
                {channel.totalViews &&
                  ` · ${formatViews(channel.totalViews)} total views`}
              </p>
              {channel.description && (
                <p className="text-sm text-[var(--text-secondary)] mt-1 line-clamp-2">
                  {channel.description}
                </p>
              )}
            </div>
            <div className="flex gap-2">
              <button className="btn-subscribe flex items-center gap-2">
                Subscribe
              </button>
              <button className="like-btn">
                <Bell size={18} />
              </button>
            </div>
          </div>

          <div className="flex gap-6 border-b border-[var(--border)] mt-2">
            {["Videos", "Playlists", "Community", "About"].map((tab) => (
              <button
                key={tab}
                className={`py-3 text-sm font-medium border-b-2 transition-colors ${
                  tab === "Videos"
                    ? "border-[var(--text-primary)] text-[var(--text-primary)]"
                    : "border-transparent text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                }`}
              >
                {tab}
              </button>
            ))}
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-x-4 gap-y-8 py-6">
            {channelVideos.map((video) => (
              <VideoCard key={video.id} video={video} />
            ))}
          </div>

          {channelVideos.length === 0 && (
            <div className="text-center py-20">
              <p className="text-[var(--text-secondary)]">
                This channel hasn&apos;t uploaded any videos yet
              </p>
            </div>
          )}
        </div>
      </div>
    </Shell>
  );
}
