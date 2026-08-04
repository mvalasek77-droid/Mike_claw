import Link from "next/link";
import { type Video, formatViews } from "@/lib/data";

interface VideoCardProps {
  video: Video;
  layout?: "grid" | "list";
}

export default function VideoCard({ video, layout = "grid" }: VideoCardProps) {
  if (layout === "list") {
    return (
      <Link
        href={`/watch?v=${video.id}`}
        className="video-card flex gap-4 no-underline"
      >
        <div className="relative flex-shrink-0 w-[168px] h-[94px] sm:w-[246px] sm:h-[138px] rounded-xl overflow-hidden bg-[var(--bg-tertiary)]">
          <img
            src={video.thumbnail}
            alt={video.title}
            className="w-full h-full object-cover"
          />
          <span className="absolute bottom-1 right-1 bg-black/80 text-white text-xs px-1 rounded">
            {video.duration}
          </span>
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-medium text-[var(--text-primary)] line-clamp-2 mb-1">
            {video.title}
          </h3>
          <p className="text-xs text-[var(--text-secondary)] mb-1">
            {video.channel.name}
          </p>
          <p className="text-xs text-[var(--text-secondary)]">
            {formatViews(video.views)} &middot; {video.uploadedAt}
          </p>
        </div>
      </Link>
    );
  }

  return (
    <Link
      href={`/watch?v=${video.id}`}
      className="video-card block no-underline"
    >
      <div className="relative aspect-video rounded-xl overflow-hidden bg-[var(--bg-tertiary)]">
        <img
          src={video.thumbnail}
          alt={video.title}
          className="w-full h-full object-cover"
        />
        <span className="absolute bottom-2 right-2 bg-black/80 text-white text-xs px-1.5 py-0.5 rounded font-medium">
          {video.duration}
        </span>
      </div>
      <div className="flex gap-3 mt-3">
        <Link href={`/channel/${video.channel.id}`}>
          <img
            src={video.channel.avatar}
            alt={video.channel.name}
            className="w-9 h-9 rounded-full flex-shrink-0"
          />
        </Link>
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-medium text-[var(--text-primary)] line-clamp-2 leading-5">
            {video.title}
          </h3>
          <p className="text-xs text-[var(--text-secondary)] mt-1">
            {video.channel.name}
          </p>
          <p className="text-xs text-[var(--text-secondary)]">
            {formatViews(video.views)} &middot; {video.uploadedAt}
          </p>
        </div>
      </div>
    </Link>
  );
}
