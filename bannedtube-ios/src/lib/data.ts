export interface Video {
  id: string;
  title: string;
  thumbnailColors: [string, string];
  channel: Channel;
  views: number;
  uploadedAt: string;
  duration: string;
  description: string;
  likes: number;
  dislikes: number;
  category: string;
  tags: string[];
  videoUrl: string;
}

export interface Channel {
  id: string;
  name: string;
  avatarColor: string;
  initial: string;
  subscribers: number;
  verified: boolean;
  bannerColors?: [string, string, string];
  description?: string;
  joinedDate?: string;
  totalViews?: number;
}

export interface Comment {
  id: string;
  author: string;
  avatarColor: string;
  initial: string;
  text: string;
  likes: number;
  timeAgo: string;
  replies?: Comment[];
}

export interface AIContentSuggestion {
  id: string;
  type: "title" | "thumbnail" | "script" | "hashtag" | "schedule";
  content: string;
  reasoning: string;
}

export interface AITrendingTopic {
  id: string;
  topic: string;
  growth: number;
  category: string;
  relatedKeywords: string[];
  suggestedAngle: string;
}

export interface CreatorInsight {
  id: string;
  metric: string;
  value: string;
  change: number;
  trend: "up" | "down" | "stable";
  suggestion: string;
}

export const THEME = {
  bgPrimary: "#0c0c14",
  bgSecondary: "#161620",
  bgTertiary: "#22222e",
  bgHover: "#333340",
  textPrimary: "#eaeaf0",
  textSecondary: "#9898aa",
  accent: "#e83a3a",
  accentHover: "#f05a5a",
  border: "#2e2e3c",
  glass: "rgba(255,255,255,0.06)",
  glassBorder: "rgba(255,255,255,0.1)",
  accentGlow: "rgba(232,58,58,0.15)",
  success: "#34d399",
  warning: "#fbbf24",
  info: "#60a5fa",
};

/**
 * Demo catalog.
 *
 * Everything below is real, openly-licensed material — the Blender Foundation's
 * "open movie" films, which are published under Creative Commons Attribution
 * licences and are free to redistribute. Engagement figures (views, likes,
 * subscribers) are deliberately zero: this app has no backend, so there are no
 * real numbers to show and inventing them would misrepresent the platform.
 *
 * Replace this file's contents with your own catalog when you have one.
 */

export const channels: Channel[] = [
  {
    id: "blender-foundation",
    name: "Blender Foundation",
    avatarColor: "#ea7600",
    initial: "B",
    subscribers: 0,
    verified: true,
    bannerColors: ["#1a0f05", "#2a1a0a", "#1a1205"],
    description:
      "The Blender Foundation's open movie projects. Every film is produced with free software and released under a Creative Commons Attribution licence.",
  },
];

export const videos: Video[] = [
  {
    id: "big-buck-bunny",
    title: "Big Buck Bunny",
    thumbnailColors: ["#1d5c3a", "#8fbf4d"],
    channel: channels[0],
    views: 0,
    uploadedAt: "2008",
    duration: "9:56",
    description:
      "The Blender Foundation's third open movie, directed by Sacha Goedegebure. A good-natured giant rabbit is tormented by three rodents and sets about an elaborate revenge. Released under the Creative Commons Attribution 3.0 licence.",
    likes: 0,
    dislikes: 0,
    category: "Animation",
    tags: ["animation", "open movie", "blender", "short film"],
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
  },
  {
    id: "elephants-dream",
    title: "Elephants Dream",
    thumbnailColors: ["#2b2440", "#6d5a8c"],
    channel: channels[0],
    views: 0,
    uploadedAt: "2006",
    duration: "10:54",
    description:
      "The first Blender open movie, directed by Bassam Kurdali. Proog and Emo journey through a strange, shifting machine world that neither of them fully understands. Released under the Creative Commons Attribution 2.5 licence.",
    likes: 0,
    dislikes: 0,
    category: "Animation",
    tags: ["animation", "open movie", "blender", "surreal"],
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
  },
  {
    id: "sintel",
    title: "Sintel",
    thumbnailColors: ["#3a2a22", "#b5794a"],
    channel: channels[0],
    views: 0,
    uploadedAt: "2010",
    duration: "14:48",
    description:
      "Directed by Colin Levy. A lone traveller named Sintel searches across harsh country for the dragon hatchling she once nursed back to health. Released under the Creative Commons Attribution 3.0 licence.",
    likes: 0,
    dislikes: 0,
    category: "Animation",
    tags: ["animation", "open movie", "blender", "fantasy"],
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
  },
  {
    id: "tears-of-steel",
    title: "Tears of Steel",
    thumbnailColors: ["#1c2733", "#4e7a99"],
    channel: channels[0],
    views: 0,
    uploadedAt: "2012",
    duration: "12:14",
    description:
      "Directed by Ian Hubert. A live-action science-fiction short set in a future Amsterdam, made to test Blender's visual-effects and compositing pipeline. Released under the Creative Commons Attribution 3.0 licence.",
    likes: 0,
    dislikes: 0,
    category: "Short Film",
    tags: ["sci-fi", "open movie", "blender", "visual effects"],
    videoUrl:
      "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
  },
];

export const categories = ["All", "Trending", "Animation", "Short Film"];

export function formatViews(views: number): string {
  if (views <= 0) return "No views yet";
  if (views >= 1000000) return `${(views / 1000000).toFixed(1)}M views`;
  if (views >= 1000) return `${(views / 1000).toFixed(0)}K views`;
  return `${views} views`;
}

export function formatSubscribers(subs: number): string {
  if (subs <= 0) return "No subscribers yet";
  if (subs >= 1000000) return `${(subs / 1000000).toFixed(1)}M subscribers`;
  if (subs >= 1000) return `${(subs / 1000).toFixed(0)}K subscribers`;
  return `${subs} subscribers`;
}

export function formatCompact(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(0)}K`;
  return `${n}`;
}

export function getVideoById(id: string): Video | undefined {
  return videos.find((v) => v.id === id);
}

export function getChannelById(id: string): Channel | undefined {
  return channels.find((c) => c.id === id);
}

export function getVideosByChannel(channelId: string): Video[] {
  return videos.filter((v) => v.channel.id === channelId);
}

export function getVideosByCategory(category: string): Video[] {
  if (category === "All") return videos;
  if (category === "Trending")
    return [...videos].sort((a, b) => b.views - a.views).slice(0, 10);
  if (category === "Live")
    return videos.filter((v) => v.title.includes("LIVE"));
  return videos.filter((v) => v.category === category);
}

export function searchVideos(query: string): Video[] {
  const q = query.toLowerCase();
  return videos.filter(
    (v) =>
      v.title.toLowerCase().includes(q) ||
      v.channel.name.toLowerCase().includes(q) ||
      v.tags.some((t) => t.includes(q)) ||
      v.category.toLowerCase().includes(q)
  );
}

/**
 * Comments are stored locally, per device. Nothing ships pre-populated —
 * anything shown here was written by the person using this install.
 */
export function getComments(): Comment[] {
  return [];
}

/**
 * Title formulas. These are generic copywriting patterns applied to whatever
 * topic you type in — not an analysis of your channel, and not ranked by any
 * measured performance data.
 */
export function getAITitleSuggestions(topic: string): AIContentSuggestion[] {
  if (!topic.trim()) return [];
  const t = topic.trim();
  return [
    {
      id: "t1",
      type: "title",
      content: `${t}: What I Got Wrong`,
      reasoning:
        "Admitting a mistake sets up a clear question the viewer wants answered.",
    },
    {
      id: "t2",
      type: "title",
      content: `The Honest Guide to ${t}`,
      reasoning: "Signals a practical walkthrough rather than a hot take.",
    },
    {
      id: "t3",
      type: "title",
      content: `I Tried ${t} for 30 Days`,
      reasoning:
        "A fixed time frame tells the viewer up front how the story ends.",
    },
    {
      id: "t4",
      type: "title",
      content: `${t}, Explained in 10 Minutes`,
      reasoning: "Naming the length sets expectations and suits short sessions.",
    },
    {
      id: "t5",
      type: "title",
      content: `Why ${t} Is Harder Than It Looks`,
      reasoning: "Frames the video around a tension rather than a description.",
    },
  ];
}

/**
 * Trending data requires real platform activity to compute. This install has
 * no backend, so there is nothing to report — returning an empty list keeps the
 * Trends tab honest instead of showing invented growth figures.
 */
export function getAITrendingTopics(): AITrendingTopic[] {
  return [];
}

/**
 * Creator analytics require real watch data. Until this install is connected to
 * a backend that measures it, there are no insights to show.
 */
export function getCreatorInsights(): CreatorInsight[] {
  return [];
}
