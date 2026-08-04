"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Menu,
  Search,
  Bell,
  Upload,
  User,
  Flame,
} from "lucide-react";

interface HeaderProps {
  onToggleSidebar?: () => void;
}

export default function Header({ onToggleSidebar }: HeaderProps) {
  const [query, setQuery] = useState("");
  const router = useRouter();

  function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (query.trim()) {
      router.push(`/search?q=${encodeURIComponent(query.trim())}`);
    }
  }

  return (
    <header className="fixed top-0 left-0 right-0 z-50 flex items-center justify-between px-4 h-[56px] bg-[var(--bg-primary)] border-b border-[var(--border)]">
      <div className="flex items-center gap-4">
        <button
          onClick={onToggleSidebar}
          className="p-2 rounded-full hover:bg-[var(--bg-tertiary)] transition-colors"
          aria-label="Toggle sidebar"
        >
          <Menu size={20} />
        </button>
        <Link href="/" className="flex items-center gap-1.5 no-underline">
          <div className="bg-[var(--accent)] rounded-lg p-1.5 shadow-[0_0_8px_rgba(255,68,68,0.4)]">
            <Flame size={18} className="text-white" />
          </div>
          <span className="text-[17px] font-bold text-[var(--text-primary)] tracking-tight">
            Banned<span className="text-[var(--accent)]">Tube</span>
          </span>
        </Link>
      </div>

      <form
        onSubmit={handleSearch}
        className="hidden md:flex items-center max-w-xl w-full mx-8"
      >
        <input
          type="text"
          placeholder="Search BannedTube"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="search-bar"
        />
        <button type="submit" className="search-btn" aria-label="Search">
          <Search size={20} />
        </button>
      </form>

      <div className="flex items-center gap-2">
        <button className="p-2 rounded-full hover:bg-[var(--bg-tertiary)] transition-colors md:hidden">
          <Search size={20} />
        </button>
        <button className="p-2 rounded-full hover:bg-[var(--bg-tertiary)] transition-colors">
          <Upload size={20} />
        </button>
        <button className="p-2 rounded-full hover:bg-[var(--bg-tertiary)] transition-colors relative">
          <Bell size={20} />
          <span className="absolute top-1 right-1 w-2 h-2 bg-[var(--accent)] rounded-full" />
        </button>
        <button className="ml-2 w-8 h-8 rounded-full bg-purple-600 flex items-center justify-center hover:bg-purple-500 transition-colors">
          <User size={16} className="text-white" />
        </button>
      </div>
    </header>
  );
}
