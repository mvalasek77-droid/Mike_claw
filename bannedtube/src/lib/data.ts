export interface Video {
  id: string;
  title: string;
  thumbnail: string;
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
  avatar: string;
  subscribers: number;
  verified: boolean;
  banner?: string;
  description?: string;
  joinedDate?: string;
  totalViews?: number;
}

export interface Comment {
  id: string;
  author: string;
  avatar: string;
  text: string;
  likes: number;
  timeAgo: string;
  replies?: Comment[];
}

const COLORS = [
  "#e53e3e", "#dd6b20", "#d69e2e", "#38a169", "#3182ce",
  "#805ad5", "#d53f8c", "#2b6cb0", "#c05621", "#2f855a",
  "#6b46c1", "#b83280", "#c53030", "#2c7a7b", "#744210",
];

function generateAvatar(name: string): string {
  const initial = name.charAt(0).toUpperCase();
  const color = COLORS[name.length % COLORS.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><rect width="80" height="80" rx="40" fill="${color}"/><text x="40" y="40" text-anchor="middle" dominant-baseline="central" fill="white" font-size="36" font-family="Arial,sans-serif" font-weight="bold">${initial}</text></svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

function generateThumbnail(title: string, hue: number): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360">
    <defs>
      <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:hsl(${hue},70%,15%)"/>
        <stop offset="100%" style="stop-color:hsl(${(hue + 40) % 360},60%,25%)"/>
      </linearGradient>
    </defs>
    <rect width="640" height="360" fill="url(#bg)"/>
    <rect x="0" y="300" width="640" height="60" fill="rgba(0,0,0,0.5)"/>
    <text x="320" y="180" text-anchor="middle" dominant-baseline="central" fill="white" font-size="28" font-family="Arial,sans-serif" font-weight="bold" opacity="0.9">${title.length > 35 ? title.slice(0, 35) + "..." : title}</text>
    <polygon points="290,140 290,220 340,180" fill="rgba(255,255,255,0.3)"/>
  </svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

function generateBanner(name: string, hue: number): string {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="200">
    <defs>
      <linearGradient id="bannerbg" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:hsl(${hue},60%,12%)"/>
        <stop offset="50%" style="stop-color:hsl(${(hue + 30) % 360},50%,18%)"/>
        <stop offset="100%" style="stop-color:hsl(${(hue + 60) % 360},40%,10%)"/>
      </linearGradient>
    </defs>
    <rect width="1200" height="200" fill="url(#bannerbg)"/>
    <text x="600" y="100" text-anchor="middle" dominant-baseline="central" fill="rgba(255,255,255,0.1)" font-size="80" font-family="Arial,sans-serif" font-weight="bold">${name}</text>
  </svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

export const channels: Channel[] = [
  {
    id: "infowars",
    name: "Alex Jones",
    avatar: generateAvatar("Alex Jones"),
    subscribers: 2400000,
    verified: true,
    banner: generateBanner("Alex Jones", 0),
    description: "Uncensored commentary and breaking news coverage. Banned from mainstream platforms for speaking truth to power.",
    joinedDate: "2024-01-15",
    totalViews: 890000000,
  },
  {
    id: "milo",
    name: "Milo Yiannopoulos",
    avatar: generateAvatar("Milo"),
    subscribers: 1800000,
    verified: true,
    banner: generateBanner("Milo", 280),
    description: "Cultural commentary, provocative takes, and fearless journalism.",
    joinedDate: "2024-02-10",
    totalViews: 450000000,
  },
  {
    id: "gavin",
    name: "Gavin McInnes",
    avatar: generateAvatar("Gavin"),
    subscribers: 1200000,
    verified: true,
    banner: generateBanner("Gavin McInnes", 30),
    description: "Comedy, commentary, and culture. No apologies.",
    joinedDate: "2024-03-05",
    totalViews: 320000000,
  },
  {
    id: "stefan",
    name: "Stefan Molyneux",
    avatar: generateAvatar("Stefan"),
    subscribers: 950000,
    verified: true,
    banner: generateBanner("Stefan Molyneux", 210),
    description: "Philosophy, reason, and evidence-based discussions.",
    joinedDate: "2024-01-20",
    totalViews: 280000000,
  },
  {
    id: "laura",
    name: "Laura Loomer",
    avatar: generateAvatar("Laura"),
    subscribers: 780000,
    verified: true,
    banner: generateBanner("Laura Loomer", 340),
    description: "Investigative journalism and political commentary.",
    joinedDate: "2024-04-12",
    totalViews: 190000000,
  },
  {
    id: "project-veritas",
    name: "Project Veritas",
    avatar: generateAvatar("Veritas"),
    subscribers: 3100000,
    verified: true,
    banner: generateBanner("Project Veritas", 15),
    description: "Undercover investigations exposing corruption.",
    joinedDate: "2024-01-01",
    totalViews: 1200000000,
  },
  {
    id: "press-for-truth",
    name: "Press For Truth",
    avatar: generateAvatar("Press"),
    subscribers: 520000,
    verified: true,
    banner: generateBanner("Press For Truth", 120),
    description: "Independent media and investigative reporting.",
    joinedDate: "2024-05-20",
    totalViews: 150000000,
  },
  {
    id: "redpill78",
    name: "RedPill78",
    avatar: generateAvatar("RedPill"),
    subscribers: 440000,
    verified: false,
    banner: generateBanner("RedPill78", 350),
    description: "News analysis and deep dives into current events.",
    joinedDate: "2024-06-01",
    totalViews: 95000000,
  },
  {
    id: "banned-comedy",
    name: "Cancelled Comics",
    avatar: generateAvatar("Comics"),
    subscribers: 890000,
    verified: true,
    banner: generateBanner("Cancelled Comics", 45),
    description: "Stand-up comedy too hot for mainstream platforms.",
    joinedDate: "2024-02-28",
    totalViews: 340000000,
  },
  {
    id: "health-ranger",
    name: "Health Ranger",
    avatar: generateAvatar("Health"),
    subscribers: 670000,
    verified: true,
    banner: generateBanner("Health Ranger", 90),
    description: "Natural health, nutrition science, and wellness freedom.",
    joinedDate: "2024-03-15",
    totalViews: 210000000,
  },
];

export const videos: Video[] = [
  {
    id: "v1",
    title: "The Truth They Don't Want You to Know",
    thumbnail: generateThumbnail("The Truth They Don't Want You to Know", 0),
    channel: channels[0],
    views: 2400000,
    uploadedAt: "2 hours ago",
    duration: "24:15",
    description: "In this explosive episode, we break down the latest developments that mainstream media refuses to cover. From government overreach to corporate censorship, nothing is off limits.",
    likes: 89000,
    dislikes: 3200,
    category: "News & Politics",
    tags: ["news", "politics", "censorship", "truth"],
  },
  {
    id: "v2",
    title: "Why I Was Really Banned - The Full Story",
    thumbnail: generateThumbnail("Why I Was Really Banned", 280),
    channel: channels[1],
    views: 1800000,
    uploadedAt: "5 hours ago",
    duration: "18:42",
    description: "For the first time, I'm telling the complete story of my deplatforming. Every detail, every email, every backroom deal.",
    likes: 72000,
    dislikes: 4100,
    category: "People & Blogs",
    tags: ["banned", "censorship", "free speech", "story"],
  },
  {
    id: "v3",
    title: "UNDERCOVER: Inside the Censorship Machine",
    thumbnail: generateThumbnail("UNDERCOVER: Censorship Machine", 15),
    channel: channels[5],
    views: 5200000,
    uploadedAt: "1 day ago",
    duration: "32:08",
    description: "Our latest undercover investigation reveals how content moderation really works at the biggest tech companies.",
    likes: 210000,
    dislikes: 8900,
    category: "News & Politics",
    tags: ["investigation", "undercover", "censorship", "big tech"],
  },
  {
    id: "v4",
    title: "Comedy That Gets You Cancelled",
    thumbnail: generateThumbnail("Comedy That Gets You Cancelled", 45),
    channel: channels[8],
    views: 3100000,
    uploadedAt: "3 days ago",
    duration: "45:30",
    description: "A full hour of stand-up comedy from comedians who were told they could never perform again. Turns out, they're funnier than ever.",
    likes: 145000,
    dislikes: 5600,
    category: "Comedy",
    tags: ["comedy", "standup", "cancelled", "funny"],
  },
  {
    id: "v5",
    title: "The Philosophy of Free Expression",
    thumbnail: generateThumbnail("Philosophy of Free Expression", 210),
    channel: channels[3],
    views: 890000,
    uploadedAt: "1 week ago",
    duration: "1:12:45",
    description: "A deep philosophical exploration of why free expression matters, tracing the idea from ancient Athens to modern social media.",
    likes: 45000,
    dislikes: 1200,
    category: "Education",
    tags: ["philosophy", "free speech", "education", "history"],
  },
  {
    id: "v6",
    title: "LIVE: Breaking News Coverage",
    thumbnail: generateThumbnail("LIVE: Breaking News", 350),
    channel: channels[0],
    views: 780000,
    uploadedAt: "12 hours ago",
    duration: "2:15:00",
    description: "Live coverage of breaking events with real-time analysis and viewer call-ins.",
    likes: 34000,
    dislikes: 2100,
    category: "News & Politics",
    tags: ["live", "breaking news", "coverage"],
  },
  {
    id: "v7",
    title: "Natural Remedies Big Pharma Hates",
    thumbnail: generateThumbnail("Natural Remedies", 90),
    channel: channels[9],
    views: 1500000,
    uploadedAt: "4 days ago",
    duration: "28:15",
    description: "Exploring natural health solutions backed by emerging research that challenge the pharmaceutical industry narrative.",
    likes: 67000,
    dislikes: 8900,
    category: "Health & Wellness",
    tags: ["health", "natural", "wellness", "remedies"],
  },
  {
    id: "v8",
    title: "Investigative Report: Follow the Money",
    thumbnail: generateThumbnail("Follow the Money", 340),
    channel: channels[4],
    views: 920000,
    uploadedAt: "2 days ago",
    duration: "22:30",
    description: "An in-depth investigation tracking financial connections between tech companies and political organizations.",
    likes: 41000,
    dislikes: 3400,
    category: "News & Politics",
    tags: ["investigation", "money", "politics", "corruption"],
  },
  {
    id: "v9",
    title: "The Great Deplatforming: A Documentary",
    thumbnail: generateThumbnail("The Great Deplatforming", 30),
    channel: channels[2],
    views: 4100000,
    uploadedAt: "2 weeks ago",
    duration: "1:45:00",
    description: "A comprehensive documentary exploring how thousands of creators lost their voices overnight, and what they did next.",
    likes: 198000,
    dislikes: 12000,
    category: "Documentary",
    tags: ["documentary", "deplatforming", "censorship", "creators"],
  },
  {
    id: "v10",
    title: "Independent Media Is the Future",
    thumbnail: generateThumbnail("Independent Media Is the Future", 120),
    channel: channels[6],
    views: 650000,
    uploadedAt: "5 days ago",
    duration: "15:20",
    description: "Why independent media platforms are growing faster than ever, and what it means for the future of information.",
    likes: 32000,
    dislikes: 1800,
    category: "News & Politics",
    tags: ["media", "independent", "future", "journalism"],
  },
  {
    id: "v11",
    title: "EXPOSED: The Blacklist Nobody Talks About",
    thumbnail: generateThumbnail("EXPOSED: The Blacklist", 350),
    channel: channels[7],
    views: 1100000,
    uploadedAt: "6 days ago",
    duration: "38:45",
    description: "Leaked documents reveal a coordinated effort to silence voices across multiple platforms simultaneously.",
    likes: 56000,
    dislikes: 4500,
    category: "News & Politics",
    tags: ["exposed", "blacklist", "leaked", "censorship"],
  },
  {
    id: "v12",
    title: "Roast Battle: Cancelled vs Uncancellable",
    thumbnail: generateThumbnail("Roast Battle", 45),
    channel: channels[8],
    views: 2800000,
    uploadedAt: "1 week ago",
    duration: "52:10",
    description: "The most savage roast battle you'll ever see. Eight comedians, no rules, no censorship.",
    likes: 134000,
    dislikes: 6700,
    category: "Comedy",
    tags: ["roast", "comedy", "battle", "uncensored"],
  },
  {
    id: "v13",
    title: "How to Build Your Own Platform",
    thumbnail: generateThumbnail("Build Your Own Platform", 210),
    channel: channels[3],
    views: 430000,
    uploadedAt: "3 weeks ago",
    duration: "55:00",
    description: "A practical guide to creating your own media presence outside the Big Tech ecosystem.",
    likes: 28000,
    dislikes: 900,
    category: "Education",
    tags: ["tutorial", "platform", "tech", "independence"],
  },
  {
    id: "v14",
    title: "The Supplements They Tried to Ban",
    thumbnail: generateThumbnail("Supplements They Tried to Ban", 90),
    channel: channels[9],
    views: 980000,
    uploadedAt: "10 days ago",
    duration: "19:45",
    description: "A look at nutritional supplements that faced regulatory pressure and the science behind them.",
    likes: 44000,
    dislikes: 5600,
    category: "Health & Wellness",
    tags: ["supplements", "health", "banned", "science"],
  },
  {
    id: "v15",
    title: "Debate: Is Free Speech Absolute?",
    thumbnail: generateThumbnail("Is Free Speech Absolute?", 280),
    channel: channels[1],
    views: 1600000,
    uploadedAt: "2 weeks ago",
    duration: "1:05:30",
    description: "A heated but respectful debate between four prominent thinkers on the limits, or lack thereof, of free expression.",
    likes: 78000,
    dislikes: 3200,
    category: "Education",
    tags: ["debate", "free speech", "philosophy", "discussion"],
  },
  {
    id: "v16",
    title: "Undercover at the Content Moderation Center",
    thumbnail: generateThumbnail("Content Moderation Center", 15),
    channel: channels[5],
    views: 6800000,
    uploadedAt: "1 month ago",
    duration: "41:20",
    description: "Hidden cameras capture what really happens inside a major social media company's content moderation facility.",
    likes: 310000,
    dislikes: 15000,
    category: "News & Politics",
    tags: ["undercover", "moderation", "investigation", "big tech"],
  },
];

export const categories = [
  "All",
  "Trending",
  "News & Politics",
  "Comedy",
  "Education",
  "Documentary",
  "Health & Wellness",
  "People & Blogs",
  "Live",
  "Recently Uploaded",
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
  if (category === "Recently Uploaded") return [...videos].slice(0, 8);
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
      avatar: generateAvatar("Freedom"),
      text: "This is exactly why we need platforms like BannedTube. The truth can't be silenced forever!",
      likes: 1240,
      timeAgo: "2 hours ago",
      replies: [
        {
          id: "c1r1",
          author: "TruthSeeker",
          avatar: generateAvatar("Truth"),
          text: "Couldn't agree more. Sharing this everywhere.",
          likes: 89,
          timeAgo: "1 hour ago",
        },
      ],
    },
    {
      id: "c2",
      author: "MediaWatchdog",
      avatar: generateAvatar("Media"),
      text: "I've been following this story for months. Great to finally see it covered in depth.",
      likes: 890,
      timeAgo: "4 hours ago",
    },
    {
      id: "c3",
      author: "SkepticalMind",
      avatar: generateAvatar("Skeptical"),
      text: "Interesting perspective, though I'd love to see the primary sources cited.",
      likes: 456,
      timeAgo: "6 hours ago",
      replies: [
        {
          id: "c3r1",
          author: "ResearchNerd",
          avatar: generateAvatar("Research"),
          text: "Check the pinned comment - sources are all linked there.",
          likes: 234,
          timeAgo: "5 hours ago",
        },
        {
          id: "c3r2",
          author: "FactChecker",
          avatar: generateAvatar("Fact"),
          text: "I verified several of the claims. They check out.",
          likes: 178,
          timeAgo: "4 hours ago",
        },
      ],
    },
    {
      id: "c4",
      author: "NewHereButLoving",
      avatar: generateAvatar("NewHere"),
      text: "Just found this platform. Already better than the alternative. No algorithms burying content!",
      likes: 2100,
      timeAgo: "1 day ago",
    },
    {
      id: "c5",
      author: "DigitalNomad42",
      avatar: generateAvatar("Digital"),
      text: "The production quality on these videos keeps getting better. Keep it up! 🔥",
      likes: 567,
      timeAgo: "2 days ago",
    },
  ];
}
