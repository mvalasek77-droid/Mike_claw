"use client";

import { categories } from "@/lib/data";

interface CategoryBarProps {
  active: string;
  onChange: (category: string) => void;
}

export default function CategoryBar({ active, onChange }: CategoryBarProps) {
  return (
    <div className="flex gap-3 overflow-x-auto pb-3 px-1 no-scrollbar">
      {categories.map((cat) => (
        <button
          key={cat}
          onClick={() => onChange(cat)}
          className={`category-pill ${active === cat ? "active" : ""}`}
        >
          {cat}
        </button>
      ))}
    </div>
  );
}
