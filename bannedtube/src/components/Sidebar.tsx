"use client";

import Link from "next/link";
import {
  Home,
  Flame,
  Clock,
  ThumbsUp,
  History,
  PlaySquare,
  Users,
  Shield,
  Flag,
} from "lucide-react";
import { channels } from "@/lib/data";

interface SidebarProps {
  open: boolean;
}

const mainItems = [
  { icon: Home, label: "Home", href: "/" },
  { icon: Flame, label: "Trending", href: "/?category=Trending" },
  { icon: PlaySquare, label: "Subscriptions", href: "/" },
];

const libraryItems = [
  { icon: History, label: "History", href: "/" },
  { icon: Clock, label: "Watch Later", href: "/" },
  { icon: ThumbsUp, label: "Liked Videos", href: "/" },
];

export default function Sidebar({ open }: SidebarProps) {
  return (
    <aside
      className={`fixed top-[56px] left-0 bottom-0 z-40 bg-[var(--bg-primary)] overflow-y-auto transition-all duration-200 ${
        open ? "w-56 p-3" : "w-0 p-0 overflow-hidden"
      }`}
    >
      <nav className="flex flex-col gap-1">
        {mainItems.map((item) => (
          <Link key={item.label} href={item.href} className="sidebar-item">
            <item.icon size={20} />
            <span>{item.label}</span>
          </Link>
        ))}
      </nav>

      <hr className="border-[var(--border)] my-3" />

      <div className="mb-2 px-3 text-sm font-medium text-[var(--text-secondary)]">
        Library
      </div>
      <nav className="flex flex-col gap-1">
        {libraryItems.map((item) => (
          <Link key={item.label} href={item.href} className="sidebar-item">
            <item.icon size={20} />
            <span>{item.label}</span>
          </Link>
        ))}
      </nav>

      <hr className="border-[var(--border)] my-3" />

      <div className="mb-2 px-3 text-sm font-medium text-[var(--text-secondary)]">
        Subscriptions
      </div>
      <nav className="flex flex-col gap-1">
        {channels.slice(0, 7).map((channel) => (
          <Link
            key={channel.id}
            href={`/channel/${channel.id}`}
            className="sidebar-item"
          >
            <img
              src={channel.avatar}
              alt={channel.name}
              className="w-6 h-6 rounded-full"
            />
            <span className="truncate text-sm">{channel.name}</span>
          </Link>
        ))}
      </nav>

      <hr className="border-[var(--border)] my-3" />

      <nav className="flex flex-col gap-1 mb-4">
        <Link href="/" className="sidebar-item">
          <Shield size={20} />
          <span>Community Guidelines</span>
        </Link>
        <Link href="/" className="sidebar-item">
          <Flag size={20} />
          <span>Report an Issue</span>
        </Link>
        <Link href="/" className="sidebar-item">
          <Users size={20} />
          <span>About BannedTube</span>
        </Link>
      </nav>

      <div className="px-3 pb-4 text-xs text-[var(--text-secondary)]">
        <p>&copy; 2025 BannedTube</p>
        <p className="mt-1">Free Speech. No Censorship.</p>
      </div>
    </aside>
  );
}
