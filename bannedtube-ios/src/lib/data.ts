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
    id: "maxout",
    name: "MaxOut",
    avatarColor: "#ff6b35",
    initial: "M",
    subscribers: 8500000,
    verified: true,
    bannerColors: ["#1a0a05", "#2a1a10", "#1a0f05"],
    description:
      "Extreme challenges, massive giveaways, and stunts nobody else will try. Banned for allegedly staging philanthropy.",
    joinedDate: "2024-01-10",
    totalViews: 2800000000,
  },
  {
    id: "kidventure",
    name: "KidVenture",
    avatarColor: "#34d399",
    initial: "K",
    subscribers: 6200000,
    verified: true,
    bannerColors: ["#051a0d", "#102a1a", "#081a12"],
    description:
      "Family-friendly adventures, DIY builds, and outdoor fun. Removed under overzealous COPPA enforcement.",
    joinedDate: "2024-02-05",
    totalViews: 1900000000,
  },
  {
    id: "gameover",
    name: "GameOver",
    avatarColor: "#7c3aed",
    initial: "G",
    subscribers: 5800000,
    verified: true,
    bannerColors: ["#0d0518", "#1a1035", "#0d0820"],
    description:
      "Gaming commentary, meme reviews, and hot takes. Banned for edgy humor during livestreams.",
    joinedDate: "2024-01-20",
    totalViews: 1500000000,
  },
  {
    id: "sketchkings",
    name: "SketchKings",
    avatarColor: "#f59e0b",
    initial: "S",
    subscribers: 5100000,
    verified: true,
    bannerColors: ["#1a1205", "#2a2010", "#1a1808"],
    description:
      "Comedy shorts and scripted sketches. Flagged for inappropriate humor one too many times.",
    joinedDate: "2024-03-12",
    totalViews: 1300000000,
  },
  {
    id: "buildlab",
    name: "BuildLab",
    avatarColor: "#0ea5e9",
    initial: "B",
    subscribers: 4200000,
    verified: true,
    bannerColors: ["#05101a", "#102535", "#081a25"],
    description:
      "Engineering builds, science experiments, and impossible contraptions. Removed for dangerous DIY content.",
    joinedDate: "2024-02-15",
    totalViews: 980000000,
  },
  {
    id: "zerogravity",
    name: "ZeroGravity",
    avatarColor: "#10b981",
    initial: "Z",
    subscribers: 3800000,
    verified: true,
    bannerColors: ["#051a10", "#102a20", "#081a15"],
    description:
      "Impossible trick shots, physical comedy, and viral challenges. Banned for unsafe stunts.",
    joinedDate: "2024-04-01",
    totalViews: 890000000,
  },
  {
    id: "quiet-genius",
    name: "Quiet Genius",
    avatarColor: "#ec4899",
    initial: "Q",
    subscribers: 3200000,
    verified: true,
    bannerColors: ["#1a0515", "#2a1025", "#1a0818"],
    description:
      "Non-verbal physical comedy and visual gags that transcend language. Flagged for misleading content.",
    joinedDate: "2024-05-10",
    totalViews: 750000000,
  },
  {
    id: "nolimits",
    name: "NoLimits",
    avatarColor: "#ef4444",
    initial: "N",
    subscribers: 2900000,
    verified: true,
    bannerColors: ["#1a0505", "#2a1010", "#1a0808"],
    description:
      "Urban exploration, abandoned places, and 24-hour challenges in haunted locations. Too extreme for the mainstream.",
    joinedDate: "2024-03-22",
    totalViews: 620000000,
  },
  {
    id: "technaked",
    name: "TechNaked",
    avatarColor: "#3b82f6",
    initial: "T",
    subscribers: 2500000,
    verified: true,
    bannerColors: ["#050d1a", "#152535", "#0a1a28"],
    description:
      "Brutally honest tech reviews with zero sponsor money. Banned for exposing device privacy flaws.",
    joinedDate: "2024-01-28",
    totalViews: 540000000,
  },
  {
    id: "waveform",
    name: "WaveForm",
    avatarColor: "#6366f1",
    initial: "W",
    subscribers: 2200000,
    verified: true,
    bannerColors: ["#0d0818", "#1a1535", "#0d0a20"],
    description:
      "Independent music, live sessions, and artists blacklisted from streaming platforms.",
    joinedDate: "2024-02-28",
    totalViews: 460000000,
  },
  {
    id: "mindvault",
    name: "MindVault",
    avatarColor: "#8b5cf6",
    initial: "M",
    subscribers: 2000000,
    verified: true,
    bannerColors: ["#0d0520", "#1a1030", "#0d0815"],
    description:
      "Deep dives into history, science, and ideas that challenge conventional thinking.",
    joinedDate: "2024-01-15",
    totalViews: 420000000,
  },
  {
    id: "rawlaugh",
    name: "RawLaugh",
    avatarColor: "#84cc16",
    initial: "R",
    subscribers: 1900000,
    verified: true,
    bannerColors: ["#0d1a05", "#1a2a10", "#101a08"],
    description:
      "Unfiltered stand-up comedy and roast battles. The jokes they said were too far.",
    joinedDate: "2024-04-15",
    totalViews: 380000000,
  },
  {
    id: "ironwill",
    name: "IronWill",
    avatarColor: "#dc2626",
    initial: "I",
    subscribers: 1600000,
    verified: true,
    bannerColors: ["#1a0505", "#2a0a0a", "#1a0808"],
    description:
      "Natural fitness, body transformations, and training with no supplement sponsors.",
    joinedDate: "2024-05-20",
    totalViews: 290000000,
  },
  {
    id: "hottake",
    name: "HotTake",
    avatarColor: "#ea580c",
    initial: "H",
    subscribers: 1400000,
    verified: true,
    bannerColors: ["#1a0a05", "#2a1510", "#1a0f08"],
    description:
      "Unpopular opinions, debates, and commentary on things everyone is thinking but nobody will say.",
    joinedDate: "2024-06-01",
    totalViews: 250000000,
  },
  {
    id: "rawkitchen",
    name: "RawKitchen",
    avatarColor: "#d97706",
    initial: "R",
    subscribers: 1200000,
    verified: true,
    bannerColors: ["#1a1205", "#2a2010", "#1a1505"],
    description:
      "Real cooking with real ingredients. Food challenges and recipes the algorithm buried.",
    joinedDate: "2024-03-05",
    totalViews: 210000000,
  },
  {
    id: "streetmic",
    name: "StreetMic",
    avatarColor: "#64748b",
    initial: "S",
    subscribers: 980000,
    verified: false,
    bannerColors: ["#0d1015", "#1a2025", "#101520"],
    description:
      "Independent street journalism and interviews with people the mainstream ignores.",
    joinedDate: "2024-07-10",
    totalViews: 160000000,
  },
  {
    id: "offmap",
    name: "OffMap",
    avatarColor: "#14b8a6",
    initial: "O",
    subscribers: 870000,
    verified: false,
    bannerColors: ["#051a15", "#102a22", "#081a18"],
    description:
      "Travel to places the guidebooks skip. Unfiltered adventures in forgotten corners of the world.",
    joinedDate: "2024-06-15",
    totalViews: 140000000,
  },
  {
    id: "canvas-riot",
    name: "Canvas Riot",
    avatarColor: "#d946ef",
    initial: "C",
    subscribers: 650000,
    verified: false,
    bannerColors: ["#1a0520", "#2a1035", "#1a0825"],
    description:
      "Art that pushes boundaries. Paintings, installations, and creative projects too provocative for galleries.",
    joinedDate: "2024-08-01",
    totalViews: 95000000,
  },
];

export const videos: Video[] = [
  {
    id: "v1",
    title: "$1,000,000 Hide and Seek - Last One Found Wins It All",
    thumbnailColors: ["#1a0a05", "#2a1a10"],
    channel: channels[0],
    views: 45000000,
    uploadedAt: "2 hours ago",
    duration: "28:42",
    description:
      "We hid $1,000,000 across an entire city. 100 contestants, one winner. This is the most insane challenge we have ever done.",
    likes: 2100000,
    dislikes: 45000,
    category: "Entertainment",
    tags: ["challenge", "money", "hide and seek", "competition"],
  },
  {
    id: "v2",
    title: "I Built 100 Homes and Gave Them All Away",
    thumbnailColors: ["#0a1a0d", "#152a1a"],
    channel: channels[0],
    views: 38000000,
    uploadedAt: "5 days ago",
    duration: "22:15",
    description:
      "We partnered with local builders to construct 100 homes for families who lost everything. This video got us banned.",
    likes: 1800000,
    dislikes: 32000,
    category: "People & Blogs",
    tags: ["philanthropy", "homes", "giveaway", "charity"],
  },
  {
    id: "v3",
    title: "Last to Leave the Deserted Island Wins $500,000",
    thumbnailColors: ["#051a15", "#102a22"],
    channel: channels[0],
    views: 52000000,
    uploadedAt: "1 week ago",
    duration: "34:08",
    description:
      "We dropped 10 people on a deserted island with nothing. Last person standing walks away with half a million dollars.",
    likes: 2400000,
    dislikes: 67000,
    category: "Entertainment",
    tags: ["survival", "island", "challenge", "competition"],
  },
  {
    id: "v4",
    title: "Building the Ultimate Backyard Water Park for 1,000 Kids!",
    thumbnailColors: ["#051a0d", "#102a1a"],
    channel: channels[1],
    views: 35000000,
    uploadedAt: "3 days ago",
    duration: "18:30",
    description:
      "We turned our entire backyard into the most epic water park ever and invited 1,000 kids from the neighborhood!",
    likes: 1500000,
    dislikes: 12000,
    category: "Entertainment",
    tags: ["kids", "water park", "family", "fun"],
  },
  {
    id: "v5",
    title: "I Played the WORST Rated Game on Steam for 24 Hours",
    thumbnailColors: ["#0d0518", "#1a1035"],
    channel: channels[2],
    views: 12000000,
    uploadedAt: "8 hours ago",
    duration: "32:45",
    description:
      "This game has a 2% positive rating. I played it for a full day and honestly... it broke me.",
    likes: 580000,
    dislikes: 18000,
    category: "Gaming",
    tags: ["gaming", "worst game", "steam", "challenge"],
  },
  {
    id: "v6",
    title: "Reacting to My First Ever Gaming Video (Pure Cringe)",
    thumbnailColors: ["#150520", "#251535"],
    channel: channels[2],
    views: 8500000,
    uploadedAt: "1 day ago",
    duration: "15:20",
    description:
      "I found my very first gaming video from 2016. I was 14. This is painful.",
    likes: 420000,
    dislikes: 8900,
    category: "Gaming",
    tags: ["reaction", "cringe", "throwback", "gaming"],
  },
  {
    id: "v7",
    title: "LIVE: 24-Hour Gaming Marathon for Charity",
    thumbnailColors: ["#0d0515", "#1a1030"],
    channel: channels[2],
    views: 3200000,
    uploadedAt: "12 hours ago",
    duration: "2:15:00",
    description:
      "Playing every game you vote for in chat for 24 hours straight. All donations go to charity.",
    likes: 156000,
    dislikes: 4500,
    category: "Gaming",
    tags: ["live", "gaming", "charity", "marathon"],
  },
  {
    id: "v8",
    title: "When Your Mom Finds Your Search History",
    thumbnailColors: ["#1a1205", "#2a2010"],
    channel: channels[3],
    views: 15000000,
    uploadedAt: "1 day ago",
    duration: "8:45",
    description:
      "We have all been there. A comedy sketch about the most universal fear known to humankind.",
    likes: 890000,
    dislikes: 15000,
    category: "Comedy",
    tags: ["comedy", "sketch", "mom", "relatable"],
  },
  {
    id: "v9",
    title: "Types of Students on the Last Day of School",
    thumbnailColors: ["#1a1505", "#2a2510"],
    channel: channels[3],
    views: 22000000,
    uploadedAt: "4 days ago",
    duration: "12:10",
    description:
      "Every school has them: the crier, the destroyer, the one who already checked out in March.",
    likes: 1100000,
    dislikes: 23000,
    category: "Comedy",
    tags: ["comedy", "school", "students", "sketch"],
  },
  {
    id: "v10",
    title: "I Built a Working Iron Man Suit That Actually Flies",
    thumbnailColors: ["#05101a", "#102535"],
    channel: channels[4],
    views: 28000000,
    uploadedAt: "3 days ago",
    duration: "24:30",
    description:
      "6 months, $35,000, and 400 hours of engineering. It actually flies. Sort of.",
    likes: 1300000,
    dislikes: 28000,
    category: "Science",
    tags: ["engineering", "iron man", "build", "flying"],
  },
  {
    id: "v11",
    title: "World's Largest Domino Chain Reaction (3 Million Pieces)",
    thumbnailColors: ["#0a101a", "#152535"],
    channel: channels[4],
    views: 19000000,
    uploadedAt: "1 week ago",
    duration: "18:55",
    description:
      "It took 2 months to set up. One sneeze could ruin everything. The most satisfying 15 seconds of your life.",
    likes: 920000,
    dislikes: 12000,
    category: "Science",
    tags: ["dominos", "chain reaction", "world record", "satisfying"],
  },
  {
    id: "v12",
    title: "Impossible Trick Shots That Shouldn't Work",
    thumbnailColors: ["#051a10", "#102a20"],
    channel: channels[5],
    views: 18000000,
    uploadedAt: "2 days ago",
    duration: "14:20",
    description:
      "We spent 6 months filming these. Every single trick shot is real. No CGI, no editing tricks.",
    likes: 890000,
    dislikes: 15000,
    category: "Entertainment",
    tags: ["trick shots", "impossible", "sports", "viral"],
  },
  {
    id: "v13",
    title: "We Explored an Abandoned Theme Park at 3 AM",
    thumbnailColors: ["#1a0505", "#2a1010"],
    channel: channels[7],
    views: 9500000,
    uploadedAt: "4 days ago",
    duration: "38:45",
    description:
      "This theme park closed in 2003 and nobody has been inside since. Until now. What we found was not what we expected.",
    likes: 460000,
    dislikes: 18000,
    category: "Entertainment",
    tags: ["abandoned", "exploration", "theme park", "night"],
  },
  {
    id: "v14",
    title: "24 Hours in the World's Most Haunted Hotel",
    thumbnailColors: ["#1a0508", "#2a1015"],
    channel: channels[7],
    views: 14000000,
    uploadedAt: "1 week ago",
    duration: "42:30",
    description:
      "Room 217. The one every ghost hunter talks about. We booked it for a full night with cameras rolling.",
    likes: 680000,
    dislikes: 34000,
    category: "Entertainment",
    tags: ["haunted", "hotel", "24 hours", "paranormal"],
  },
  {
    id: "v15",
    title: "When You Try to Fix Things Yourself (Silent Comedy)",
    thumbnailColors: ["#1a0515", "#2a1025"],
    channel: channels[6],
    views: 25000000,
    uploadedAt: "6 hours ago",
    duration: "6:12",
    description:
      "No words needed. Just a person, a leaky faucet, and an increasingly bad series of decisions.",
    likes: 1200000,
    dislikes: 18000,
    category: "Comedy",
    tags: ["silent comedy", "physical comedy", "diy fail", "viral"],
  },
  {
    id: "v16",
    title: "This Song Got Me Removed From Every Streaming Platform",
    thumbnailColors: ["#0d0818", "#1a1535"],
    channel: channels[9],
    views: 8000000,
    uploadedAt: "2 days ago",
    duration: "4:35",
    description:
      "They said it violated community guidelines. 50 million streams, then gone overnight. Here it is, uncut.",
    likes: 420000,
    dislikes: 8900,
    category: "Music",
    tags: ["music", "original song", "independent", "banned"],
  },
  {
    id: "v17",
    title: "Street Performer Blows Away Entire Crowd - LIVE Session",
    thumbnailColors: ["#0d0520", "#1a1030"],
    channel: channels[9],
    views: 5500000,
    uploadedAt: "5 days ago",
    duration: "8:42",
    description:
      "We found this guy playing guitar in a subway station. Within 10 minutes, 200 people stopped to watch.",
    likes: 340000,
    dislikes: 3200,
    category: "Music",
    tags: ["street performer", "live music", "talent", "guitar"],
  },
  {
    id: "v18",
    title: "I Used a $50 Phone for 30 Days - Honest Review",
    thumbnailColors: ["#050d1a", "#152535"],
    channel: channels[8],
    views: 13000000,
    uploadedAt: "1 day ago",
    duration: "18:15",
    description:
      "No sponsor money. No affiliate links. Just a $50 phone and 30 days of real use. The results surprised me.",
    likes: 720000,
    dislikes: 21000,
    category: "Technology",
    tags: ["tech", "phone review", "budget", "honest"],
  },
  {
    id: "v19",
    title: "Your Smart Home Is Spying on You - Here's the Proof",
    thumbnailColors: ["#05101a", "#103040"],
    channel: channels[8],
    views: 8000000,
    uploadedAt: "6 days ago",
    duration: "26:50",
    description:
      "I intercepted the network traffic from 15 smart home devices. What they send back to their servers will disturb you.",
    likes: 520000,
    dislikes: 11000,
    category: "Technology",
    tags: ["privacy", "smart home", "surveillance", "tech"],
  },
  {
    id: "v20",
    title: "The Ancient Civilization That Shouldn't Exist",
    thumbnailColors: ["#0d0520", "#1a1030"],
    channel: channels[10],
    views: 16000000,
    uploadedAt: "3 days ago",
    duration: "1:05:20",
    description:
      "Archaeological evidence that rewrites the timeline. A deep dive into discoveries that mainstream academia struggles to explain.",
    likes: 890000,
    dislikes: 45000,
    category: "Education",
    tags: ["history", "archaeology", "civilization", "mystery"],
  },
  {
    id: "v21",
    title: "The Psychology of Why We Believe Lies",
    thumbnailColors: ["#0d0818", "#1a1535"],
    channel: channels[10],
    views: 12000000,
    uploadedAt: "1 week ago",
    duration: "32:40",
    description:
      "A deep dive into cognitive biases, propaganda techniques, and why our brains are wired to be fooled.",
    likes: 670000,
    dislikes: 18000,
    category: "Education",
    tags: ["psychology", "cognitive bias", "propaganda", "science"],
  },
  {
    id: "v22",
    title: "Stand-Up Comedy: Things You Can't Say Anymore",
    thumbnailColors: ["#0d1a05", "#1a2a10"],
    channel: channels[11],
    views: 10000000,
    uploadedAt: "4 days ago",
    duration: "48:20",
    description:
      "Six comedians, one stage, zero filter. The comedy special that got pulled from two platforms.",
    likes: 560000,
    dislikes: 34000,
    category: "Comedy",
    tags: ["standup", "comedy", "special", "uncensored"],
  },
  {
    id: "v23",
    title: "Roast Battle: Comedians Go Way Too Far",
    thumbnailColors: ["#1a1505", "#2a2510"],
    channel: channels[11],
    views: 14000000,
    uploadedAt: "1 week ago",
    duration: "52:10",
    description:
      "Eight comedians, no rules, no off-limits topics. The most savage roast battle ever filmed.",
    likes: 780000,
    dislikes: 45000,
    category: "Comedy",
    tags: ["roast", "comedy", "battle", "funny"],
  },
  {
    id: "v24",
    title: "30-Day Body Transformation - No Gym, No Supplements",
    thumbnailColors: ["#1a0505", "#2a0a0a"],
    channel: channels[12],
    views: 11000000,
    uploadedAt: "3 days ago",
    duration: "28:45",
    description:
      "Just bodyweight exercises, real food, and discipline. No $200 protein powder required.",
    likes: 620000,
    dislikes: 23000,
    category: "Fitness",
    tags: ["fitness", "transformation", "bodyweight", "natural"],
  },
  {
    id: "v25",
    title: "The $1 vs $1,000 Steak - Can You Taste the Difference?",
    thumbnailColors: ["#1a1205", "#2a2010"],
    channel: channels[14],
    views: 7500000,
    uploadedAt: "2 days ago",
    duration: "15:30",
    description:
      "We blindfolded 50 people and gave them both steaks. The results destroyed everything food snobs believe.",
    likes: 390000,
    dislikes: 12000,
    category: "Cooking",
    tags: ["cooking", "food", "challenge", "taste test"],
  },
  {
    id: "v26",
    title: "I Traveled to the Country Nobody Visits",
    thumbnailColors: ["#051a15", "#102a22"],
    channel: channels[16],
    views: 6000000,
    uploadedAt: "5 days ago",
    duration: "42:10",
    description:
      "Last year, fewer than 500 tourists visited this country. I was one of them. What I found was incredible.",
    likes: 340000,
    dislikes: 8900,
    category: "Travel",
    tags: ["travel", "rare country", "adventure", "solo travel"],
  },
  {
    id: "v27",
    title: "Living With a Remote Tribe for 7 Days",
    thumbnailColors: ["#051a0a", "#153520"],
    channel: channels[16],
    views: 9000000,
    uploadedAt: "2 weeks ago",
    duration: "58:30",
    description:
      "No phone, no electricity, no common language. Just me and a tribe that has never seen a camera before.",
    likes: 520000,
    dislikes: 15000,
    category: "Travel",
    tags: ["travel", "tribe", "remote", "documentary"],
  },
  {
    id: "v28",
    title: "Unpopular Opinions That Will Make You Angry",
    thumbnailColors: ["#1a0a05", "#2a1510"],
    channel: channels[13],
    views: 7000000,
    uploadedAt: "1 day ago",
    duration: "22:15",
    description:
      "I asked my audience for their most controversial takes. Then I ranked them from mild to absolutely unhinged.",
    likes: 380000,
    dislikes: 89000,
    category: "People & Blogs",
    tags: ["opinions", "controversial", "debate", "commentary"],
  },
  {
    id: "v29",
    title: "I Let Strangers Paint on a $10,000 Canvas",
    thumbnailColors: ["#1a0520", "#2a1035"],
    channel: channels[17],
    views: 4000000,
    uploadedAt: "6 days ago",
    duration: "16:45",
    description:
      "100 random people. One blank canvas. Each person got 60 seconds. The final result is hanging in a gallery.",
    likes: 280000,
    dislikes: 5600,
    category: "Art",
    tags: ["art", "experiment", "canvas", "strangers"],
  },
  {
    id: "v30",
    title: "We Interviewed the People They Told Us Not to Interview",
    thumbnailColors: ["#0d1015", "#1a2025"],
    channel: channels[15],
    views: 5000000,
    uploadedAt: "4 days ago",
    duration: "35:10",
    description:
      "Street journalism at its rawest. We went where the cameras are not supposed to go.",
    likes: 290000,
    dislikes: 18000,
    category: "News & Politics",
    tags: ["journalism", "interview", "street", "independent"],
  },
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
      author: "ChallengeAddict",
      avatarColor: "#ff6b35",
      initial: "C",
      text: "Bro the production quality on this is insane. This is better than anything on mainstream platforms right now.",
      likes: 4200,
      timeAgo: "2 hours ago",
      replies: [
        {
          id: "c1r1",
          author: "MaxFan2025",
          avatarColor: "#3182ce",
          initial: "M",
          text: "For real though. The fact this got taken down from the other site is criminal.",
          likes: 890,
          timeAgo: "1 hour ago",
        },
      ],
    },
    {
      id: "c2",
      author: "GamerGurl99",
      avatarColor: "#7c3aed",
      initial: "G",
      text: "I have been watching GameOver since they had 10K subs. So glad they found a home here after the ban.",
      likes: 1890,
      timeAgo: "4 hours ago",
    },
    {
      id: "c3",
      author: "ScienceNerd42",
      avatarColor: "#0ea5e9",
      initial: "S",
      text: "The engineering on that build is actually incredible. I am a mechanical engineer and the tolerances are legit.",
      likes: 2340,
      timeAgo: "6 hours ago",
      replies: [
        {
          id: "c3r1",
          author: "BuildLabFan",
          avatarColor: "#10b981",
          initial: "B",
          text: "Right? Most YouTube builders fake half of it. This channel actually shows the failures too.",
          likes: 456,
          timeAgo: "5 hours ago",
        },
      ],
    },
    {
      id: "c4",
      author: "NewToBannedTube",
      avatarColor: "#e53e3e",
      initial: "N",
      text: "Just downloaded this app yesterday. The content is so much better than I expected. No ads every 30 seconds!",
      likes: 3100,
      timeAgo: "1 day ago",
    },
    {
      id: "c5",
      author: "ComedyFanatic",
      avatarColor: "#f59e0b",
      initial: "C",
      text: "The sketch about the search history had me DYING. Shared it with everyone I know.",
      likes: 1560,
      timeAgo: "2 days ago",
    },
    {
      id: "c6",
      author: "FoodieForever",
      avatarColor: "#d97706",
      initial: "F",
      text: "That steak challenge was wild. My mind is blown that the $1 steak won the blind taste test.",
      likes: 890,
      timeAgo: "3 hours ago",
      replies: [
        {
          id: "c6r1",
          author: "ChefMike",
          avatarColor: "#14b8a6",
          initial: "C",
          text: "Seasoning and technique matter more than the cut. This video proved what every chef already knows.",
          likes: 234,
          timeAgo: "2 hours ago",
        },
      ],
    },
    {
      id: "c7",
      author: "TrickShotKing",
      avatarColor: "#10b981",
      initial: "T",
      text: "That basketball shot from the helicopter was absolutely insane. How many attempts did that take??",
      likes: 2100,
      timeAgo: "5 hours ago",
    },
    {
      id: "c8",
      author: "PrivacyMatters",
      avatarColor: "#3b82f6",
      initial: "P",
      text: "The smart home spying video genuinely scared me. I unplugged my Alexa after watching. Everyone needs to see this.",
      likes: 1450,
      timeAgo: "8 hours ago",
      replies: [
        {
          id: "c8r1",
          author: "TechSkeptic",
          avatarColor: "#6366f1",
          initial: "T",
          text: "Same. The network traffic data was damning. No wonder this got taken down.",
          likes: 567,
          timeAgo: "6 hours ago",
        },
        {
          id: "c8r2",
          author: "DevOpsDaily",
          avatarColor: "#84cc16",
          initial: "D",
          text: "You can set up a Pi-hole to block most of those tracking requests. DM me if you want help.",
          likes: 189,
          timeAgo: "4 hours ago",
        },
      ],
    },
    {
      id: "c9",
      author: "HistoryBuff2025",
      avatarColor: "#8b5cf6",
      initial: "H",
      text: "The MindVault deep dives are genuinely the best educational content on any platform. Learned more here than in 4 years of college.",
      likes: 2800,
      timeAgo: "1 day ago",
      replies: [
        {
          id: "c9r1",
          author: "ProfessorJ",
          avatarColor: "#ec4899",
          initial: "P",
          text: "As an actual history professor, I can confirm the research here is solid. Well-sourced content.",
          likes: 670,
          timeAgo: "20 hours ago",
        },
      ],
    },
    {
      id: "c10",
      author: "FitnessFreak",
      avatarColor: "#dc2626",
      initial: "F",
      text: "That 30-day transformation was real. No fake lighting, no dehydration tricks. Just actual work. Respect.",
      likes: 1890,
      timeAgo: "2 days ago",
    },
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
