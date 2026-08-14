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
  confidence: number;
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

export const channels: Channel[] = [
  {
    id: "infowars",
    name: "Alex Jones",
    avatarColor: "#e53e3e",
    initial: "A",
    subscribers: 2400000,
    verified: true,
    bannerColors: ["#1a0505", "#2a1510", "#1a0a05"],
    description:
      "Uncensored commentary and breaking news coverage. Banned from mainstream platforms for speaking truth to power.",
    joinedDate: "2024-01-15",
    totalViews: 890000000,
  },
  {
    id: "milo",
    name: "Milo Yiannopoulos",
    avatarColor: "#805ad5",
    initial: "M",
    subscribers: 1800000,
    verified: true,
    bannerColors: ["#0d0520", "#1a1030", "#0d0815"],
    description:
      "Cultural commentary, provocative takes, and fearless journalism.",
    joinedDate: "2024-02-10",
    totalViews: 450000000,
  },
  {
    id: "gavin",
    name: "Gavin McInnes",
    avatarColor: "#dd6b20",
    initial: "G",
    subscribers: 1200000,
    verified: true,
    bannerColors: ["#1a0f05", "#2a1a10", "#1a1205"],
    description: "Comedy, commentary, and culture. No apologies.",
    joinedDate: "2024-03-05",
    totalViews: 320000000,
  },
  {
    id: "stefan",
    name: "Stefan Molyneux",
    avatarColor: "#3182ce",
    initial: "S",
    subscribers: 950000,
    verified: true,
    bannerColors: ["#050d1a", "#101a2a", "#050f1a"],
    description: "Philosophy, reason, and evidence-based discussions.",
    joinedDate: "2024-01-20",
    totalViews: 280000000,
  },
  {
    id: "laura",
    name: "Laura Loomer",
    avatarColor: "#d53f8c",
    initial: "L",
    subscribers: 780000,
    verified: true,
    bannerColors: ["#1a0515", "#2a1020", "#1a0810"],
    description: "Investigative journalism and political commentary.",
    joinedDate: "2024-04-12",
    totalViews: 190000000,
  },
  {
    id: "project-veritas",
    name: "Project Veritas",
    avatarColor: "#2b6cb0",
    initial: "V",
    subscribers: 3100000,
    verified: true,
    bannerColors: ["#1a0805", "#2a1510", "#1a0a08"],
    description: "Undercover investigations exposing corruption.",
    joinedDate: "2024-01-01",
    totalViews: 1200000000,
  },
  {
    id: "press-for-truth",
    name: "Press For Truth",
    avatarColor: "#38a169",
    initial: "P",
    subscribers: 520000,
    verified: true,
    bannerColors: ["#051a0d", "#102a1a", "#081a0f"],
    description: "Independent media and investigative reporting.",
    joinedDate: "2024-05-20",
    totalViews: 150000000,
  },
  {
    id: "redpill78",
    name: "RedPill78",
    avatarColor: "#c53030",
    initial: "R",
    subscribers: 440000,
    verified: false,
    bannerColors: ["#1a0505", "#2a0a0a", "#1a0808"],
    description: "News analysis and deep dives into current events.",
    joinedDate: "2024-06-01",
    totalViews: 95000000,
  },
  {
    id: "banned-comedy",
    name: "Cancelled Comics",
    avatarColor: "#d69e2e",
    initial: "C",
    subscribers: 890000,
    verified: true,
    bannerColors: ["#1a1505", "#2a2010", "#1a1808"],
    description: "Stand-up comedy too hot for mainstream platforms.",
    joinedDate: "2024-02-28",
    totalViews: 340000000,
  },
  {
    id: "health-ranger",
    name: "Health Ranger",
    avatarColor: "#2f855a",
    initial: "H",
    subscribers: 670000,
    verified: true,
    bannerColors: ["#051a0a", "#102a15", "#081a0d"],
    description:
      "Natural health, nutrition science, and wellness freedom.",
    joinedDate: "2024-03-15",
    totalViews: 210000000,
  },
  {
    id: "pixel-rebel",
    name: "Pixel Rebel",
    avatarColor: "#e91e63",
    initial: "P",
    subscribers: 1340000,
    verified: true,
    bannerColors: ["#1a0510", "#2a1020", "#1a0a15"],
    description:
      "Uncensored gaming content, hot takes, and no sponsor-free bias. Game reviews the way they should be.",
    joinedDate: "2024-04-01",
    totalViews: 420000000,
  },
  {
    id: "underground-sound",
    name: "Underground Sound",
    avatarColor: "#7c3aed",
    initial: "U",
    subscribers: 2100000,
    verified: true,
    bannerColors: ["#0d0515", "#1a1030", "#0d0820"],
    description:
      "Independent music, banned artists, and uncensored performances you wont hear on the radio.",
    joinedDate: "2024-01-28",
    totalViews: 680000000,
  },
  {
    id: "tech-truther",
    name: "Tech Truther",
    avatarColor: "#0ea5e9",
    initial: "T",
    subscribers: 1850000,
    verified: true,
    bannerColors: ["#05101a", "#102535", "#081a25"],
    description:
      "Tech reviews without the corporate sponsorship filter. Honest takes on devices, software, and privacy.",
    joinedDate: "2024-02-15",
    totalViews: 510000000,
  },
  {
    id: "uncensored-kitchen",
    name: "Uncensored Kitchen",
    avatarColor: "#f59e0b",
    initial: "U",
    subscribers: 920000,
    verified: true,
    bannerColors: ["#1a1205", "#2a2010", "#1a1808"],
    description:
      "Real cooking, real ingredients, no FDA-approved nonsense. Recipes they tried to take down.",
    joinedDate: "2024-03-22",
    totalViews: 280000000,
  },
  {
    id: "iron-will-fitness",
    name: "Iron Will Fitness",
    avatarColor: "#ef4444",
    initial: "I",
    subscribers: 1100000,
    verified: true,
    bannerColors: ["#1a0505", "#2a1010", "#1a0808"],
    description:
      "Fitness without the pharmaceutical agenda. Natural strength, real training, no excuses.",
    joinedDate: "2024-05-10",
    totalViews: 340000000,
  },
  {
    id: "off-grid-traveler",
    name: "Off-Grid Traveler",
    avatarColor: "#10b981",
    initial: "O",
    subscribers: 760000,
    verified: false,
    bannerColors: ["#051a10", "#102a1a", "#081a12"],
    description:
      "Travel to places the mainstream wont show you. Uncensored adventures off the beaten path.",
    joinedDate: "2024-06-05",
    totalViews: 190000000,
  },
  {
    id: "free-mind-academy",
    name: "Free Mind Academy",
    avatarColor: "#6366f1",
    initial: "F",
    subscribers: 1450000,
    verified: true,
    bannerColors: ["#0d0818", "#1a1535", "#0d0a20"],
    description:
      "Education without indoctrination. History, science, and critical thinking they removed from schools.",
    joinedDate: "2024-01-10",
    totalViews: 480000000,
  },
  {
    id: "rebel-artist-collective",
    name: "Rebel Artist Collective",
    avatarColor: "#ec4899",
    initial: "R",
    subscribers: 540000,
    verified: false,
    bannerColors: ["#1a0515", "#2a1025", "#1a0818"],
    description:
      "Art that challenges narratives. Censored paintings, banned films, and creative freedom.",
    joinedDate: "2024-07-01",
    totalViews: 130000000,
  }
];

export const videos: Video[] = [
  {
    id: "v1",
    title: "The Truth They Don't Want You to Know",
    thumbnailColors: ["#1a0505", "#2a1a10"],
    channel: channels[0],
    views: 2400000,
    uploadedAt: "2 hours ago",
    duration: "24:15",
    description:
      "In this explosive episode, we break down the latest developments that mainstream media refuses to cover.",
    likes: 89000,
    dislikes: 3200,
    category: "News & Politics",
    tags: ["news", "politics", "censorship", "truth"],
  },
  {
    id: "v2",
    title: "Why I Was Really Banned - The Full Story",
    thumbnailColors: ["#150520", "#251535"],
    channel: channels[1],
    views: 1800000,
    uploadedAt: "5 hours ago",
    duration: "18:42",
    description:
      "For the first time, I'm telling the complete story of my deplatforming. Every detail, every email.",
    likes: 72000,
    dislikes: 4100,
    category: "People & Blogs",
    tags: ["banned", "censorship", "free speech", "story"],
  },
  {
    id: "v3",
    title: "UNDERCOVER: Inside the Censorship Machine",
    thumbnailColors: ["#1a0a05", "#2a1810"],
    channel: channels[5],
    views: 5200000,
    uploadedAt: "1 day ago",
    duration: "32:08",
    description:
      "Our latest undercover investigation reveals how content moderation really works at the biggest tech companies.",
    likes: 210000,
    dislikes: 8900,
    category: "News & Politics",
    tags: ["investigation", "undercover", "censorship", "big tech"],
  },
  {
    id: "v4",
    title: "Comedy That Gets You Cancelled",
    thumbnailColors: ["#1a1205", "#2a2010"],
    channel: channels[8],
    views: 3100000,
    uploadedAt: "3 days ago",
    duration: "45:30",
    description:
      "Stand-up comedy from comedians who were told they could never perform again.",
    likes: 145000,
    dislikes: 5600,
    category: "Comedy",
    tags: ["comedy", "standup", "cancelled", "funny"],
  },
  {
    id: "v5",
    title: "The Philosophy of Free Expression",
    thumbnailColors: ["#050d1a", "#152535"],
    channel: channels[3],
    views: 890000,
    uploadedAt: "1 week ago",
    duration: "1:12:45",
    description:
      "A deep philosophical exploration of why free expression matters, from Athens to social media.",
    likes: 45000,
    dislikes: 1200,
    category: "Education",
    tags: ["philosophy", "free speech", "education", "history"],
  },
  {
    id: "v6",
    title: "LIVE: Breaking News Coverage",
    thumbnailColors: ["#1a0515", "#2a1025"],
    channel: channels[0],
    views: 780000,
    uploadedAt: "12 hours ago",
    duration: "2:15:00",
    description:
      "Live coverage of breaking events with real-time analysis and viewer call-ins.",
    likes: 34000,
    dislikes: 2100,
    category: "News & Politics",
    tags: ["live", "breaking news", "coverage"],
  },
  {
    id: "v7",
    title: "Natural Remedies Big Pharma Hates",
    thumbnailColors: ["#051a0a", "#153520"],
    channel: channels[9],
    views: 1500000,
    uploadedAt: "4 days ago",
    duration: "28:15",
    description:
      "Exploring natural health solutions backed by emerging research.",
    likes: 67000,
    dislikes: 8900,
    category: "Health & Wellness",
    tags: ["health", "natural", "wellness", "remedies"],
  },
  {
    id: "v8",
    title: "Investigative Report: Follow the Money",
    thumbnailColors: ["#1a0510", "#2a1020"],
    channel: channels[4],
    views: 920000,
    uploadedAt: "2 days ago",
    duration: "22:30",
    description:
      "Tracking financial connections between tech companies and political organizations.",
    likes: 41000,
    dislikes: 3400,
    category: "News & Politics",
    tags: ["investigation", "money", "politics", "corruption"],
  },
  {
    id: "v9",
    title: "The Great Deplatforming: A Documentary",
    thumbnailColors: ["#1a0f05", "#2a1f10"],
    channel: channels[2],
    views: 4100000,
    uploadedAt: "2 weeks ago",
    duration: "1:45:00",
    description:
      "How thousands of creators lost their voices overnight, and what they did next.",
    likes: 198000,
    dislikes: 12000,
    category: "Documentary",
    tags: ["documentary", "deplatforming", "censorship", "creators"],
  },
  {
    id: "v10",
    title: "Independent Media Is the Future",
    thumbnailColors: ["#051a0d", "#154025"],
    channel: channels[6],
    views: 650000,
    uploadedAt: "5 days ago",
    duration: "15:20",
    description:
      "Why independent media platforms are growing faster than ever.",
    likes: 32000,
    dislikes: 1800,
    category: "News & Politics",
    tags: ["media", "independent", "future", "journalism"],
  },
  {
    id: "v11",
    title: "EXPOSED: The Blacklist Nobody Talks About",
    thumbnailColors: ["#1a0508", "#2a1015"],
    channel: channels[7],
    views: 1100000,
    uploadedAt: "6 days ago",
    duration: "38:45",
    description:
      "Leaked documents reveal a coordinated effort to silence voices across platforms.",
    likes: 56000,
    dislikes: 4500,
    category: "News & Politics",
    tags: ["exposed", "blacklist", "leaked", "censorship"],
  },
  {
    id: "v12",
    title: "Roast Battle: Cancelled vs Uncancellable",
    thumbnailColors: ["#1a1505", "#2a2510"],
    channel: channels[8],
    views: 2800000,
    uploadedAt: "1 week ago",
    duration: "52:10",
    description:
      "Eight comedians, no rules, no censorship. The most savage roast battle.",
    likes: 134000,
    dislikes: 6700,
    category: "Comedy",
    tags: ["roast", "comedy", "battle", "uncensored"],
  },
  {
    id: "v13",
    title: "They BANNED This Game For Being TOO Political",
    thumbnailColors: ["#1a0510", "#2a1020"],
    channel: channels[10],
    views: 1850000,
    uploadedAt: "3 hours ago",
    duration: "22:30",
    description:
      "A deep dive into the game that was pulled from every major store. Here is what they dont want you to see.",
    likes: 89000,
    dislikes: 4500,
    category: "Gaming",
    tags: ["gaming", "banned game", "censorship", "politics"],
  },
  {
    id: "v14",
    title: "BANNED SONG: The Track Radio Stations Refuse to Play",
    thumbnailColors: ["#0d0515", "#1a1030"],
    channel: channels[11],
    views: 3200000,
    uploadedAt: "8 hours ago",
    duration: "5:42",
    description:
      "This artist was blacklisted from every streaming platform. The music speaks for itself.",
    likes: 156000,
    dislikes: 3200,
    category: "Music",
    tags: ["music", "banned song", "uncensored", "independent"],
  },
  {
    id: "v15",
    title: "I Used This Phone For 30 Days - Big Tech HATES This Review",
    thumbnailColors: ["#05101a", "#102535"],
    channel: channels[12],
    views: 1450000,
    uploadedAt: "1 day ago",
    duration: "18:15",
    description:
      "An honest phone review with no sponsor money involved. What I found will shock you.",
    likes: 72000,
    dislikes: 2100,
    category: "Technology",
    tags: ["tech", "phone review", "privacy", "big tech"],
  },
  {
    id: "v16",
    title: "The Recipe They Tried to ERASE From the Internet",
    thumbnailColors: ["#1a1205", "#2a2010"],
    channel: channels[13],
    views: 670000,
    uploadedAt: "2 days ago",
    duration: "15:30",
    description:
      "A traditional recipe that was flagged and removed for misinformation. Here is how to make it yourself.",
    likes: 34000,
    dislikes: 1800,
    category: "Cooking",
    tags: ["cooking", "recipe", "natural food", "uncensored"],
  },
  {
    id: "v17",
    title: "No Gym, No Supplements, No Excuses - 90 Day Transformation",
    thumbnailColors: ["#1a0505", "#2a1010"],
    channel: channels[14],
    views: 2100000,
    uploadedAt: "4 days ago",
    duration: "28:45",
    description:
      "Real fitness without the supplement industry garbage. Natural training that actually works.",
    likes: 98000,
    dislikes: 5600,
    category: "Fitness",
    tags: ["fitness", "natural", "no supplements", "training"],
  },
  {
    id: "v18",
    title: "I Traveled to the Country They Warned You About",
    thumbnailColors: ["#051a10", "#102a1a"],
    channel: channels[15],
    views: 890000,
    uploadedAt: "3 days ago",
    duration: "42:10",
    description:
      "What you see on the news and what is actually on the ground are two very different things.",
    likes: 56000,
    dislikes: 8900,
    category: "Travel",
    tags: ["travel", "uncensored", "off-grid", "independent"],
  },
  {
    id: "v19",
    title: "The History They Erased From Your Textbooks",
    thumbnailColors: ["#0d0818", "#1a1535"],
    channel: channels[16],
    views: 4500000,
    uploadedAt: "5 days ago",
    duration: "1:05:20",
    description:
      "A comprehensive look at historical events that were quietly removed from school curricula.",
    likes: 234000,
    dislikes: 15000,
    category: "Education",
    tags: ["education", "history", "censored", "truth"],
  },
  {
    id: "v20",
    title: "The Painting That Got an Artist DEPORTED",
    thumbnailColors: ["#1a0515", "#2a1025"],
    channel: channels[17],
    views: 430000,
    uploadedAt: "1 week ago",
    duration: "12:15",
    description:
      "When art becomes a crime. The story behind the most controversial painting of our time.",
    likes: 28000,
    dislikes: 1200,
    category: "Art",
    tags: ["art", "censored", "creative freedom", "painting"],
  },
  {
    id: "v21",
    title: "DOCUMENTARY: The Disappearing - Voices of the Silenced",
    thumbnailColors: ["#0d0515", "#1a1530"],
    channel: channels[16],
    views: 3100000,
    uploadedAt: "2 weeks ago",
    duration: "1:32:40",
    description:
      "A feature-length documentary following five individuals who lost everything for speaking out.",
    likes: 189000,
    dislikes: 9800,
    category: "Documentary",
    tags: ["documentary", "silenced", "free speech", "expose"],
  },
  {
    id: "v22",
    title: "Stand-Up So Offensive It BROKE the Venue Rules",
    thumbnailColors: ["#1a1505", "#2a2510"],
    channel: channels[8],
    views: 2700000,
    uploadedAt: "4 days ago",
    duration: "48:20",
    description:
      "Live comedy from the venue that almost shut us down. Every joke crossed the line.",
    likes: 131000,
    dislikes: 8900,
    category: "Comedy",
    tags: ["comedy", "standup", "uncensored", "offensive"],
  },
  {
    id: "v23",
    title: "EMERGENCY BROADCAST: What Just Happened Will Change Everything",
    thumbnailColors: ["#1a0508", "#2a1015"],
    channel: channels[0],
    views: 5200000,
    uploadedAt: "1 hour ago",
    duration: "35:10",
    description:
      "Breaking developments that mainstream media is ignoring. This affects every single one of you.",
    likes: 245000,
    dislikes: 18000,
    category: "News & Politics",
    tags: ["breaking", "news", "emergency", "uncensored"],
  },
  {
    id: "v24",
    title: "The Science of Censorship: How Algorithms Decide What You See",
    thumbnailColors: ["#050d1a", "#152535"],
    channel: channels[16],
    views: 1230000,
    uploadedAt: "6 days ago",
    duration: "26:50",
    description:
      "A scientific breakdown of how content moderation algorithms actually work, with real data.",
    likes: 67000,
    dislikes: 3400,
    category: "Science",
    tags: ["science", "algorithms", "censorship", "data"],
  },
  {
    id: "v25",
    title: "How to Build Your Own Server and Ditch Big Tech COMPLETELY",
    thumbnailColors: ["#05101a", "#103040"],
    channel: channels[12],
    views: 980000,
    uploadedAt: "1 week ago",
    duration: "33:15",
    description:
      "Step-by-step guide to self-hosting everything. Take back control of your data.",
    likes: 52000,
    dislikes: 1100,
    category: "How-To",
    tags: ["how-to", "self-hosting", "privacy", "tutorial"],
  },
  {
    id: "v26",
    title: "The Most Dangerous Movie Hollywood Refused to Release",
    thumbnailColors: ["#1a0f05", "#2a1f10"],
    channel: channels[17],
    views: 1600000,
    uploadedAt: "3 days ago",
    duration: "1:18:30",
    description:
      "The film that sat on a shelf for 5 years. We finally got our hands on it.",
    likes: 89000,
    dislikes: 4500,
    category: "Entertainment",
    tags: ["entertainment", "banned film", "uncensored", "exclusive"],
  },
  {
    id: "v27",
    title: "I Lived Off-Grid for 30 Days - Here is What Nobody Tells You",
    thumbnailColors: ["#051a0a", "#153520"],
    channel: channels[15],
    views: 1340000,
    uploadedAt: "5 days ago",
    duration: "24:45",
    description:
      "A real lifestyle experiment with no agenda. The unfiltered truth about off-grid living.",
    likes: 78000,
    dislikes: 2300,
    category: "Lifestyle",
    tags: ["lifestyle", "off-grid", "self-sufficient", "uncensored"],
  }
];

export const categories = [
  "All",
  "Trending",
  "Clips",
  "News & Politics",
  "Comedy",
  "Education",
  "Documentary",
  "Health & Wellness",
  "People & Blogs",
  "Live",
  "Gaming",
  "Music",
  "Technology",
  "Cooking",
  "Fitness",
  "Travel",
  "Art",
  "Science",
  "How-To",
  "Lifestyle",
  "Entertainment",
];

export function formatViews(views: number): string {
  if (views >= 1000000) return `${(views / 1000000).toFixed(1)}M views`;
  if (views >= 1000) return `${(views / 1000).toFixed(0)}K views`;
  return `${views} views`;
}

export function formatSubscribers(subs: number): string {
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

export function getComments(): Comment[] {
  return [
    {
      id: "c1",
      author: "FreedomFighter99",
      avatarColor: "#38a169",
      initial: "F",
      text: "This is exactly why we need platforms like BannedTube. The truth can't be silenced forever!",
      likes: 1240,
      timeAgo: "2 hours ago",
      replies: [
        {
          id: "c1r1",
          author: "TruthSeeker",
          avatarColor: "#3182ce",
          initial: "T",
          text: "Couldn't agree more. Sharing this everywhere.",
          likes: 89,
          timeAgo: "1 hour ago",
        },
      ],
    },
    {
      id: "c2",
      author: "MediaWatchdog",
      avatarColor: "#d69e2e",
      initial: "M",
      text: "I've been following this story for months. Great to finally see it covered in depth.",
      likes: 890,
      timeAgo: "4 hours ago",
    },
    {
      id: "c3",
      author: "SkepticalMind",
      avatarColor: "#805ad5",
      initial: "S",
      text: "Interesting perspective, though I'd love to see the primary sources cited.",
      likes: 456,
      timeAgo: "6 hours ago",
      replies: [
        {
          id: "c3r1",
          author: "ResearchNerd",
          avatarColor: "#dd6b20",
          initial: "R",
          text: "Check the pinned comment - sources are all linked there.",
          likes: 234,
          timeAgo: "5 hours ago",
        },
      ],
    },
    {
      id: "c4",
      author: "NewHereButLoving",
      avatarColor: "#e53e3e",
      initial: "N",
      text: "Just found this platform. Already better than the alternative!",
      likes: 2100,
      timeAgo: "1 day ago",
    },
    {
      id: "c5",
      author: "DigitalNomad42",
      avatarColor: "#2b6cb0",
      initial: "D",
      text: "The production quality keeps getting better. Keep it up!",
      likes: 567,
      timeAgo: "2 days ago",
    },
    {
      id: "c16",
      author: "UncensoredChef",
      avatarColor: "#f59e0b",
      initial: "U",
      text: "Finally a platform where cooks can share real recipes without some algorithm deciding what is safe to eat.",
      likes: 670,
      timeAgo: "3 hours ago",
      replies: [
        {
          id: "c16r1",
          author: "TraditionalEats",
          avatarColor: "#10b981",
          initial: "T",
          text: "My grandmother recipe got taken down on the other site for misinformation. This is where real food lives now.",
          likes: 145,
          timeAgo: "2 hours ago",
        },
      ],
    },
    {
      id: "c17",
      author: "GamerNoFilter",
      avatarColor: "#e91e63",
      initial: "G",
      text: "The gaming content here is raw and honest. No corporate sponsorships = real opinions. This is how reviews should be.",
      likes: 1890,
      timeAgo: "5 hours ago",
    },
    {
      id: "c18",
      author: "PrivacyAdvocate",
      avatarColor: "#0ea5e9",
      initial: "P",
      text: "I appreciate the tech reviews without hidden ad deals. This channel told me about privacy features the other platforms deliberately omitted.",
      likes: 940,
      timeAgo: "8 hours ago",
      replies: [
        {
          id: "c18r1",
          author: "DigitalRightsNow",
          avatarColor: "#6366f1",
          initial: "D",
          text: "Exactly. Self-hosting is the future. Corporations wont protect your data.",
          likes: 312,
          timeAgo: "6 hours ago",
        },
        {
          id: "c18r2",
          author: "SkepticSteve",
          avatarColor: "#ef4444",
          initial: "S",
          text: "Self-hosting is great but most people dont have the technical skills. We need easier solutions.",
          likes: 89,
          timeAgo: "4 hours ago",
        },
      ],
    },
    {
      id: "c19",
      author: "HistoryBuff2024",
      avatarColor: "#6366f1",
      initial: "H",
      text: "The education content on this platform is eye-opening. Stuff I was never taught in school. Keep it coming!",
      likes: 1560,
      timeAgo: "1 day ago",
      replies: [
        {
          id: "c19r1",
          author: "CriticalThinker",
          avatarColor: "#7c3aed",
          initial: "C",
          text: "Always cross-reference with primary sources. Even independent content can have bias.",
          likes: 234,
          timeAgo: "20 hours ago",
        },
      ],
    },
    {
      id: "c20",
      author: "ArtLiberator",
      avatarColor: "#ec4899",
      initial: "A",
      text: "As an artist who was deplatformed for a painting, this platform gave me my voice back. Thank you BannedTube.",
      likes: 2100,
      timeAgo: "2 days ago",
    }
  ];
}

export function getAITitleSuggestions(topic: string): AIContentSuggestion[] {
  const base = topic.toLowerCase();
  return [
    {
      id: "t1",
      type: "title",
      content: `BREAKING: ${topic} - What They're Not Telling You`,
      confidence: 0.94,
      reasoning: "High-urgency titles with revelation hooks drive 3.2x higher CTR on this platform.",
    },
    {
      id: "t2",
      type: "title",
      content: `I Investigated ${topic} for 30 Days. Here's What I Found.`,
      confidence: 0.89,
      reasoning: "Personal investigation format builds trust and averages 2.8x watch time.",
    },
    {
      id: "t3",
      type: "title",
      content: `The ${topic} They Banned Me For Talking About`,
      confidence: 0.87,
      reasoning: "Platform-specific censorship angle resonates strongly with BannedTube audience.",
    },
    {
      id: "t4",
      type: "title",
      content: `${topic}: A Deep Dive Into the Evidence`,
      confidence: 0.82,
      reasoning: "Evidence-focused framing attracts higher-quality engagement and longer sessions.",
    },
  ];
}

export function getAITrendingTopics(): AITrendingTopic[] {
  return [
    {
      id: "tr1",
      topic: "Platform Migration Wave",
      growth: 340,
      category: "Tech & Media",
      relatedKeywords: ["deplatforming", "alt-tech", "creator exodus", "free speech"],
      suggestedAngle: "Document creators' experiences moving between platforms. Interview 3-5 creators about their journey.",
    },
    {
      id: "tr2",
      topic: "AI Content Moderation",
      growth: 280,
      category: "Technology",
      relatedKeywords: ["algorithm", "shadow ban", "AI censorship", "content policy"],
      suggestedAngle: "Investigate how AI moderation systems make decisions. Use screen recordings to show real examples.",
    },
    {
      id: "tr3",
      topic: "Independent Journalism Revival",
      growth: 195,
      category: "News & Media",
      relatedKeywords: ["citizen journalism", "media trust", "grassroots", "reporting"],
      suggestedAngle: "Highlight the rise of independent newsrooms. Compare coverage quality vs legacy media.",
    },
    {
      id: "tr4",
      topic: "Digital Rights & Privacy",
      growth: 160,
      category: "Policy",
      relatedKeywords: ["data privacy", "surveillance", "encryption", "digital freedom"],
      suggestedAngle: "Practical guide to protecting online privacy as a creator. Step-by-step tutorial format.",
    },
    {
      id: "tr5",
      topic: "Creator Economy Shifts",
      growth: 145,
      category: "Business",
      relatedKeywords: ["monetization", "direct support", "membership", "sponsorship"],
      suggestedAngle: "Break down alternative monetization models that don't rely on platform ad revenue.",
    },
  ];
}

export function getCreatorInsights(): CreatorInsight[] {
  return [
    {
      id: "i1",
      metric: "Avg. Watch Time",
      value: "8:42",
      change: 12,
      trend: "up",
      suggestion: "Your longer-form content (20+ min) retains 40% better. Consider extending your next video.",
    },
    {
      id: "i2",
      metric: "Subscriber Growth",
      value: "+2.4K",
      change: 8,
      trend: "up",
      suggestion: "Tuesday/Thursday uploads drive 2x more subscriptions. Optimize your schedule.",
    },
    {
      id: "i3",
      metric: "Engagement Rate",
      value: "6.8%",
      change: -3,
      trend: "down",
      suggestion: "Add a question in your first 30 seconds to boost comments. Top creators see 15% lift.",
    },
    {
      id: "i4",
      metric: "Click-Through Rate",
      value: "11.2%",
      change: 5,
      trend: "up",
      suggestion: "Your high-contrast thumbnails perform 2.5x better. Keep using bold text overlays.",
    },
  ];
}
