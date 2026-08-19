/* Auction Baby — PWA (vanilla JS, no build step).
   Runs standalone on demo data (localStorage); the API layer is stubbed so it
   can later point at the existing Cloudflare Workers. Web monetization is
   Stripe, not Apple IAP. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const app = $("#app");
  const money = n => { if (n == null || isNaN(n)) return "$0"; return "$" + (n >= 1000 ? n.toLocaleString("en-US") : n); };
  const esc = s => (s || "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const uid = () => Math.random().toString(36).slice(2, 10);

  // ---- live backend (Cloudflare Workers) with graceful demo fallback ----
  const API = window.AB_API || {};
  const CONFIGURED = () => !!window.AB_LIVE;                       // backend URLs set
  const SIGNED_IN = () => !!(API.hasSession && API.hasSession());  // have a session token
  const APPLE_ON = () => !!(window.AB_CONFIG && window.AB_CONFIG.APPLE_SERVICE_ID);
  const hueFrom = s => { let h = 0; for (const c of (s || "")) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
  const VERIFIED_SVG = `<svg viewBox="0 0 24 24"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg>`;
  const verifiedBadge = (size) => `<span class="vbadge${size === "sm" ? " sm" : size === "lg" ? " lg" : ""}" title="Verified">${VERIFIED_SVG}</span>`;
  const masterpieceBadge = () => `<span class="mp-badge"><span class="mp-icon">&#127942;</span> Masterpiece</span>`;
  const copycatTag = () => `<span class="cc-tag">&#10024; Copycat</span>`;
  const GAVEL_PACK_ID = { 1000: "gavels_handful", 5000: "gavels_stack", 14000: "gavels_chest", 30000: "gavels_vault" };
  const PASS_ID = { "Paddle": "pass_paddle", "Reserve": "pass_reserve", "Black Card": "pass_blackcard" };

  // Map a server profile → the local lot shape (matches the Worker's publicProfile:
  // userId, name, age, location, bio, hue, startingBid, verified, photos:[{url}], prompts).
  const mapLot = p => ({
    id: p.userId || p.id || uid(), name: p.name || "—", age: p.age || 27, city: p.location || p.city || "",
    startingBid: Number(p.startingBid) || 100, bio: p.bio || "",
    prompts: (p.prompts || []).map(x => ({ q: x.question || x.q || "Prompt", a: x.answer || x.a || String(x) })),
    icebreakers: (p.prompts || []).map(x => (x && (x.answer || x.a)) || x).filter(Boolean),
    hue: (typeof p.hue === "number" ? Math.round(p.hue * 360) : hueFrom(p.userId || p.name)),
    verified: !!p.verified, masterpiece: !!p.masterpiece, copycat: !!p.copycat,
    photo: (p.photos && p.photos[0] && p.photos[0].url) || null,
    interests: p.interests || [],
    lifestyle: p.lifestyle || {},
    showcase: Number(p.showcase) || Number(p.showcaseCredit) || 480,
    marketValue: Number(p.marketValue) || Math.round((Number(p.startingBid) || 100) * 1.2 + (480 - 300) * 2),
  });
  async function syncFloor() {
    if (!CONFIGURED() || !SIGNED_IN()) return;
    try {
      const r = await API.floor(S.me.city);
      const arr = r.floor || r.users || (Array.isArray(r) ? r : []);
      if (Array.isArray(arr) && arr.length) { S.floor = arr.map(mapLot); save(); if (tab === "floor") floor(); }
    } catch (e) { /* keep demo floor */ }
  }
  async function syncIncoming() {
    if (!CONFIGURED() || !SIGNED_IN()) return;
    try {
      const r = await API.incomingBids();
      const arr = r.bids || (Array.isArray(r) ? r : []);
      S.incoming = arr.map(b => ({
        id: b.id, name: (b.man && b.man.name) || b.name || "Bidder",
        age: b.age, amount: b.amount || b.bidAmount || 0, note: b.note || "",
        hue: hueFrom(b.id || b.name),
      }));
      save(); if (tab === "floor" && S.role === "woman") incoming();
    } catch (e) { /* keep local */ }
  }
  async function syncMatches() {
    if (!CONFIGURED() || !SIGNED_IN()) return;
    try {
      const r = await API.matches();
      const arr = r.matches || (Array.isArray(r) ? r : []);
      S.matches = arr.map(m => ({
        id: m.id, lotId: m.lotId, name: (m.other && m.other.name) || m.name || "Match",
        otherId: (m.other && m.other.userId) || m.otherUserId || m.otherId || null,
        hue: hueFrom(m.id || m.name), amount: m.amount || m.bidAmount || 0,
        seen: !!m.seenByOther, unread: !!(m.unreadCount || m.unread),
        lastTs: m.updatedAt || m.lastMessageAt || 0,
        messages: (m.messages || []).map(x => ({ id: x.id, me: !!x.fromMe, text: x.text, reaction: x.reaction || null })),
      }));
      save(); if (tab === "matches") matches();
    } catch (e) { /* keep local */ }
  }

  // ---- theme helper: a deterministic gradient avatar from a hue ----
  const grad = (hue, name, photo) => {
    if (photo) return `<div class="avatar" style="padding:0"><img src="${esc(photo)}" alt="" loading="lazy" style="width:100%;height:100%;object-fit:cover;border-radius:inherit"></div>`;
    const a = `hsl(${hue} 55% 42%)`, b = `hsl(${(hue + 40) % 360} 60% 24%)`;
    const initials = (name || "?").split(" ").map(w => w[0]).slice(0, 2).join("").toUpperCase();
    return `<div class="avatar" style="background:linear-gradient(140deg,${a},${b})">${initials}</div>`;
  };
  const gradSm = (hue, name, photo) => grad(hue, name, photo).replace('class="avatar"', 'class="avatar sm"');

  // ---- demo floor (all 56 women from the iOS app with photos) ----
  const W = (name,age,city,bid,bio,prompts,hue,verified,masterpiece,copycat,photo,interests,lifestyle,showcase) => ({
    id:uid(),name,age,city,startingBid:bid,bio,prompts,icebreakers:prompts.map(p=>p.a),hue,verified,masterpiece,copycat,
    photo:"photos/"+photo+".jpg",interests:interests||[],lifestyle:lifestyle||{},showcase:showcase||480,marketValue:Math.round(bid*1.2+((showcase||480)-300)*2)
  });
  const P = (q,a) => ({q,a});
  const seedFloor = () => ([
    W("Serena Voss",28,"Upper East Side, New York",1000000,"Private art dealer. Quiet dinners, old buildings, men who don't explain their watch.",[P("The way to win me over is","Know what you want and don't apologize for it."),P("Together we could","Close a gallery and open the wine they keep behind the counter.")],306,false,true,false,"photo-serena",["Art","Wine","Travel","Design","Film"],{height:"5'9\"",drinks:"Rarely",kids:"Wants kids"},900),
    W("Rae",27,"SoHo, New York",100,"Gallery girl by day, downtown by night. I know what I want and I don't settle.",[P("The way to win me over is","Be direct, be confident, and make the reservation before you ask.")],180,true,false,false,"photo-grace",["Wine","Art","Travel"],{height:"5'6\"",drinks:"Socially"},620),
    W("Sloane",31,"Venice, Los Angeles",150,"Founder, second company. I like early mornings, good espresso, and people who follow through.",[P("Together we could","Skip the small talk and split the tasting menu."),P("Dating me is like","Working with a good cofounder — direct, loyal, occasionally intense.")],198,true,false,false,"photo-sloane",["Startups","Fitness","Food","Design"],{height:"5'7\"",drinks:"Socially",kids:"Wants kids"},650),
    W("Mara Quinn",27,"SoHo, New York",250,"Gallery curator. I spend my weekends at openings and my weeknights pretending I'll stop buying art books.",[P("The way to win me over is","Make the reservation and don't cancel it."),P("My simple pleasure","A negroni, a window seat, and leaving the party at the right time.")],331,false,false,true,"photo-mara",["Art","Film","Wine","Design"],{height:"5'5\"",drinks:"Regularly"},710),
    W("Priya Sethi",29,"Lincoln Park, Chicago",300,"ER doctor. My schedule is chaos, so when I'm off, I'm actually present.",[P("I geek out on","Medicine, obviously — but also 90s R&B. I will take over the aux."),P("Green flags I look for","Calls his mom. Tips well. Asks follow-up questions.")],29,false,false,false,"photo-priya",["Fitness","Food","Travel","Music"],{height:"5'4\"",drinks:"Socially",kids:"Wants kids"},680),
    W("Harper Wells",31,"Venice, Los Angeles",500,"Producer. I survive on espresso and deadline adrenaline. Looking for someone who can keep up on a Sunday hike.",[P("Together we could","Skip the small talk and split the tasting menu."),P("Dating me is like","Working with a good cofounder — direct, loyal, occasionally intense.")],198,false,false,true,"photo-harper",["Startups","Fitness","Food","Design"],{height:"5'8\"",drinks:"Socially"},580),
    W("Bella Rose",23,"Miami Beach",200,"Pool days, boat weekends, and a standing reservation at my favorite rooftop. Come keep up.",[P("My ideal date","Sunset drinks somewhere over the water. You handle the details.")],342,false,false,false,"photo-bella",["Travel","Nightlife","Wine"],{height:"5'7\"",drinks:"Regularly"},490),
    W("Noor Haddad",26,"Capitol Hill, Seattle",200,"Climate engineer. I'll hike in any weather and I fact-check fun facts — lovingly.",[P("Best travel story","Got weathered-in on a glacier for two days. Still the best trip of my life."),P("I'm weirdly good at","Parallel parking and reading a room.")],151,false,false,true,"photo-noor",["Fitness","Travel","Reading","Music"],{height:"5'6\"",drinks:"Rarely"},550),
    W("Valentina Cruz",28,"Williamsburg, Brooklyn",200,"Pastry chef. I work Saturdays, so impress me on a Tuesday. Bonus points if you actually like dessert.",[P("My love language","Cooking for people, then watching their face on the first bite.")],47,false,false,false,"photo-valentina",["Food","Music","Art","Dogs"],{height:"5'3\"",drinks:"Socially"},520),
    W("Crystal Lux",24,"Las Vegas",200,"Cocktail dresses over casual, always. If you can't decide where to take me, I already know how the date ends.",[P("Two truths and a lie","I've been to 30 countries, I hate champagne, and I always text back.")],281,false,false,true,"photo-crystal",["Nightlife","Travel","Design"],{height:"5'9\"",drinks:"Regularly"},460),
    W("Jade Rivera",25,"Tulum",200,"Yoga teacher splitting time between Tulum and wherever the next retreat is. Sunrise person, unapologetically.",[P("My happy place","The beach at 6am before anyone else is up.")],288,false,false,false,"photo-jade",["Fitness","Travel","Reading"],{height:"5'5\"",drinks:"Rarely"},510),
    W("Amber Skye",24,"Malibu",200,"Grew up on this coast and never left. Golden hour is a personality trait, I've accepted it.",[P("Best first date","Tacos on the beach, then see where the night goes.")],25,false,false,true,"photo-amber",["Travel","Fitness","Music"],{height:"5'6\"",drinks:"Socially"},470),
    W("Tiana Brooks",27,"Georgetown, DC",200,"Brand strategist who accidentally became a weekend DJ. I own too many blazers and not enough patience for small talk.",[P("I'm looking for","Someone who knows what they want and orders first.")],65,false,false,false,"photo-tiana",["Music","Food","Design","Startups"],{height:"5'7\"",drinks:"Socially"},530),
    W("Lucia Reyes",25,"Ibiza",200,"Summers in Europe, winters wherever the sun is. I collect wine, sunsets, and men who can keep up.",[P("My ideal date","Somewhere with a view and a bottle we'll remember. You pick the place.")],7,false,false,true,"photo-lucia",["Travel","Wine","Nightlife","Art"],{height:"5'6\"",drinks:"Regularly"},490),
    W("Elena Marsh",26,"Pacific Palisades, LA",200,"Interior designer. I notice things — the way a room is lit, where you sit, whether you hold the door.",[P("Green flags I look for","You read something this week. You have a plant that's still alive.")],223,false,false,false,"photo-elena",["Design","Art","Food","Reading"],{height:"5'5\"",drinks:"Socially"},560),
    W("Sophie Hale",28,"Nolita, New York",200,"PR director. Half my wardrobe is black, the other half is statement coats. I leave parties early and restaurants late.",[P("Together we could","Split a cab uptown and argue about where to eat next.")],50,false,false,true,"photo-sophie",["Food","Film","Design","Wine"],{height:"5'7\"",drinks:"Regularly"},540),
    W("Zara Collins",24,"Harlem, New York",200,"Freelance photographer. I shoot everything but will only eat at places I've already been twice.",[P("My love language","Showing up. On time. With coffee. Every single time.")],126,false,false,false,"photo-zara",["Art","Music","Food","Travel"],{height:"5'4\"",drinks:"Socially"},500),
    W("Anaya Mehta",27,"West Village, New York",200,"Product lead at a startup nobody's heard of yet. Weekend mornings are for the farmers market, not my phone.",[P("I geek out on","Skincare ingredients, behavioral economics, and making the perfect dal.")],209,false,false,true,"photo-anaya",["Startups","Food","Fitness","Reading"],{height:"5'5\"",drinks:"Rarely"},570),
    W("Fiona Byrne",26,"Savannah, Georgia",200,"Garden designer. I grow things for a living and ruin book spines for fun.",[P("My simple pleasure","A used bookstore, an iced coffee, and nowhere I have to be.")],14,false,false,false,"photo-fiona",["Reading","Food","Art","Dogs"],{height:"5'6\"",drinks:"Socially"},510),
    W("Camille Adler",32,"Gold Coast, Chicago",200,"Wine importer. I've been to more vineyards than restaurants but I still can't say no to a good tasting menu.",[P("Unusual skills","I can blind-taste a Burgundy from a Bordeaux. And I parallel park on the first try.")],43,false,false,true,"photo-camille",["Wine","Travel","Food","Film"],{height:"5'8\"",drinks:"Regularly"},590),
    W("Mei Lin Chen",25,"DUMBO, Brooklyn",200,"Architect. I think in floor plans and talk in references nobody gets.",[P("Dating me is like","A building with good bones — worth the renovation.")],245,false,false,false,"photo-mei",["Design","Art","Reading","Film"],{height:"5'3\"",drinks:"Socially"},530),
    W("Nikki West",29,"Newport Beach, CA",200,"Charter broker. Weekdays I sell the boat, weekends I'm on it.",[P("Best first date","Sunset sail. No agenda, no timeline, just the ocean and whatever we're drinking.")],194,false,false,true,"photo-nikki",["Travel","Fitness","Nightlife","Wine"],{height:"5'7\"",drinks:"Regularly"},500),
    W("Brooke Taylor",30,"Scottsdale, Arizona",200,"Real estate. I flip houses and friendships — both need good foundation.",[P("The way to win me over is","Pick the restaurant, pick me up, and don't check your phone once.")],36,false,false,false,"photo-brooke",["Food","Fitness","Travel","Dogs"],{height:"5'6\"",drinks:"Socially"},540),
    W("Harper Lane",26,"Byron Bay, Australia",200,"Surf instructor half the year, content creator the other half. I'll outswim you and outeat you.",[P("My ideal date","Beach, tacos, sunset. In that order.")],18,false,false,true,"photo-harper",["Fitness","Travel","Food","Music"],{height:"5'8\"",drinks:"Socially"},480),
    W("Dana Walsh",33,"Tribeca, New York",200,"Pilates studio owner. My mornings start at 5:30 and I wouldn't have it any other way.",[P("Green flags I look for","He has a morning routine that doesn't start with his phone.")],324,false,false,false,"photo-dana",["Fitness","Food","Design","Travel"],{height:"5'7\"",drinks:"Rarely"},560),
    W("Chloe Park",28,"Charleston, South Carolina",200,"Event planner. I turn empty rooms into something people remember.",[P("My simple pleasure","Sweet tea, a good porch, and a dog that greets me at the door.")],79,false,false,true,"photo-chloe",["Design","Food","Reading","Dogs"],{height:"5'5\"",drinks:"Socially"},520),
    W("Kendall Marsh",27,"Laguna Beach, CA",200,"Jewelry designer. I make things with my hands, collect sea glass, and take the long way everywhere.",[P("Together we could","Drive down the coast with no plan and stop wherever looks good.")],25,false,false,false,"photo-kendall",["Art","Travel","Design","Fitness"],{height:"5'6\"",drinks:"Socially"},510),
    W("Riley Stone",29,"Nantucket, Massachusetts",200,"Cookbook author. I test recipes until midnight and wake up craving coffee and feedback.",[P("I geek out on","Farmers markets, sourdough timers, and restaurants that don't have a website.")],58,false,false,true,"photo-riley",["Food","Reading","Travel","Wine"],{height:"5'5\"",drinks:"Regularly"},550),
    W("Lexi Monroe",25,"Palm Beach, Florida",200,"Luxury travel consultant. I book the trips everyone posts about, then take my own with no itinerary.",[P("Best travel story","Got bumped to first class in Rome, ended up at a stranger's vineyard for dinner.")],22,false,false,false,"photo-lexi",["Travel","Wine","Food","Nightlife"],{height:"5'8\"",drinks:"Regularly"},480),
    W("Paige Nolan",31,"Calabasas, CA",200,"Wellness brand founder. I built my company poolside and I'm not apologizing for it.",[P("Dating me is like","A five-star retreat — intentional, restorative, and you'll leave better than you came in.")],295,false,false,true,"photo-paige",["Fitness","Startups","Travel","Design"],{height:"5'7\"",drinks:"Rarely"},570),
    W("Sienna Clarke",27,"Santa Barbara, CA",200,"Botanical illustrator. I spend most of my time outside, most of my money on plants.",[P("My happy place","Any garden, anywhere. The wilder the better.")],137,false,false,false,"photo-sienna",["Art","Travel","Design","Reading"],{height:"5'4\"",drinks:"Socially"},500),
    W("Hayley James",30,"Savannah, Georgia",200,"Restaurant owner. Sunday brunch is my religion and Saturday night is my confessional.",[P("The way to win me over is","Sit at the bar, order something interesting, and make me laugh before the food comes.")],72,false,false,true,"photo-hayley",["Food","Wine","Music","Dogs"],{height:"5'6\"",drinks:"Regularly"},540),
    W("Maya Santos",26,"South Beach, Miami",200,"Marine biologist who somehow ends up at the beach even on days off. Science by day, salsa by night.",[P("Unusual skills","Identifying fish, dancing in heels, and leaving the party at exactly the right time.")],173,false,false,false,"photo-maya",["Fitness","Travel","Music","Food"],{height:"5'5\"",drinks:"Socially"},520),
    W("Autumn Reed",28,"Asheville, North Carolina",200,"Trail runner and part-time park ranger. Warm, colorful, and gone too fast.",[P("My ideal date","A trail at golden hour, then wherever the nearest firepit is. Bring layers.")],32,false,false,true,"photo-autumn",["Fitness","Travel","Reading","Dogs"],{height:"5'7\"",drinks:"Rarely"},530),
    W("Cassidy Blake",27,"Cabo San Lucas",200,"Yacht broker. I sell the dream and live it on weekends.",[P("Together we could","Take the boat out, anchor somewhere nobody else is, and forget what day it is.")],11,false,false,false,"photo-cassidy",["Travel","Nightlife","Wine","Fitness"],{height:"5'8\"",drinks:"Regularly"},490),
    W("Nia Jordan",29,"Arts District, Los Angeles",200,"Muralist and fitness coach. I paint walls by day and teach spin by evening.",[P("I'm looking for","Shows up when he says he will. Knows what he wants for dinner. Has hobbies that aren't screens.")],259,false,false,true,"photo-nia",["Art","Fitness","Music","Design"],{height:"5'6\"",drinks:"Socially"},550),
    W("Yuki Tanaka",26,"Santa Monica, CA",200,"Yoga instructor and breathwork facilitator. Sunrise on the pier is my temple.",[P("My love language","Presence. Put the phone away and just be here with me.")],274,false,false,false,"photo-yuki",["Fitness","Travel","Reading"],{height:"5'3\"",drinks:"Rarely"},510),
    W("Charlotte Fox",31,"Greenwich, Connecticut",200,"Antiques dealer. I know what things are worth and I don't negotiate on the ones that matter.",[P("Unusual skills","I can date a piece of furniture from across the room and pick the best bottle on any list.")],54,false,false,true,"photo-charlotte",["Art","Wine","Design","Travel"],{height:"5'7\"",drinks:"Regularly"},600),
    W("Jordan Obi",27,"Joshua Tree, CA",200,"Adventure photographer. I chase light for a living and silence for fun.",[P("Best travel story","Camped alone in the desert for a week shooting stars. Best photos I've ever taken.")],108,false,false,false,"photo-jordan",["Art","Travel","Fitness","Music"],{height:"5'8\"",drinks:"Rarely"},520),
    W("Lily Tran",25,"Kitsilano, Vancouver",200,"UX designer who walks everywhere. Cherry blossom season is my Super Bowl.",[P("I geek out on","Typography, city planning, and the way light changes between 5 and 6 PM.")],317,false,false,true,"photo-lily",["Design","Art","Food","Reading"],{height:"5'4\"",drinks:"Socially"},530),
    W("Hana Kim",24,"Queen Anne, Seattle",200,"Dance teacher and part-time barista. I know everyone's order and nobody's last name.",[P("My simple pleasure","A matcha latte, a park bench, and watching dogs I don't own play fetch.")],230,false,false,false,"photo-hana",["Music","Food","Dogs","Fitness"],{height:"5'3\"",drinks:"Socially"},480),
    W("Grace Ashford",30,"Annapolis, Maryland",200,"Sailing instructor. I grew up on the water and I still haven't found a reason to leave it.",[P("Dating me is like","A day on the bay — calm on the surface, more going on underneath than you'd expect.")],162,false,false,true,"photo-grace",["Travel","Fitness","Reading","Wine"],{height:"5'7\"",drinks:"Socially"},560),
    W("Destiny Moore",28,"Sedona, Arizona",200,"Personal trainer and hiking guide. Golden hour is my office.",[P("My ideal date","Sunrise hike, then breakfast at the place only locals know.")],338,false,false,false,"photo-destiny",["Fitness","Travel","Food"],{height:"5'6\"",drinks:"Rarely"},510),
    W("Stella Cruz",27,"Sayulita, Mexico",200,"Surf photographer. I chase golden hour the way some people chase promotions.",[P("Together we could","Catch the last wave, rinse off, and eat tacos with sandy feet.")],115,false,false,true,"photo-stella",["Art","Travel","Fitness","Music"],{height:"5'5\"",drinks:"Socially"},500),
    W("Britt Larson",25,"Mission Beach, San Diego",200,"Physical therapist who spends every lunch break at the beach.",[P("My happy place","A towel, a good playlist, and absolutely nowhere I need to be.")],4,false,false,false,"photo-britt",["Fitness","Music","Travel"],{height:"5'7\"",drinks:"Socially"},470),
    W("Nova Ray",26,"Playa del Carmen, Mexico",200,"Freediver and ocean conservationist. I hold my breath for a living and speak my mind for free.",[P("Unusual skills","Holding my breath for four minutes, finding hidden beaches, and making friends in every country.")],180,false,false,true,"photo-nova",["Travel","Fitness","Reading","Art"],{height:"5'6\"",drinks:"Rarely"},540),
    W("Tessa Flynn",28,"Maui, Hawaii",200,"Dive instructor by morning, bartender by night. I live on island time and I'm not going back.",[P("Best travel story","Moved to Maui for a month. That was three years ago.")],313,false,false,false,"photo-tessa",["Travel","Food","Music","Nightlife"],{height:"5'5\"",drinks:"Regularly"},490),
    W("Wren Bishop",26,"Montauk, New York",200,"Photographer. Sunset is my golden hour and the beach is my studio. I shoot on film and live like it.",[P("My simple pleasure","A cold drink, warm sand, and a conversation that doesn't need a phone.")],101,false,false,true,"photo-wren",["Art","Travel","Film","Music"],{height:"5'6\"",drinks:"Socially"},520),
    W("Iris Calloway",29,"Positano, Italy",200,"Ceramicist splitting time between Italy and Brooklyn. Freckles are earned, not filtered.",[P("My love language","Remember what I said last time. That's it. That's the whole thing.")],144,false,false,false,"photo-iris",["Art","Travel","Food","Design"],{height:"5'5\"",drinks:"Regularly"},550),
    W("Adriana Vega",27,"Barcelona, Spain",200,"Chef de partie at a Michelin kitchen. My days are loud and hot — I need my beach time quiet.",[P("I geek out on","Fermentation timelines, regional olive oils, and people who eat with their hands.")],187,false,false,true,"photo-adriana",["Food","Travel","Wine","Art"],{height:"5'6\"",drinks:"Regularly"},530),
    W("Paloma Diaz",25,"Tulum, Mexico",200,"Jewelry designer. Everything I make starts with something I found on the beach.",[P("Together we could","Get lost in a market, buy something we don't need, and eat street food until we can't move.")],252,false,false,false,"photo-paloma",["Art","Travel","Design","Food"],{height:"5'4\"",drinks:"Socially"},480),
    W("Suki Nakamura",26,"Venice Beach, CA",200,"Content strategist who clocks out at 5 and is on the sand by 5:15.",[P("My happy place","Golden hour at the beach, then ramen at the place with no sign.")],238,false,false,true,"photo-suki",["Food","Travel","Fitness","Design"],{height:"5'5\"",drinks:"Socially"},500),
    W("Kiana Reyes",25,"North Shore, Oahu",200,"Surf school owner. Born in the water, raised by the tide.",[P("My ideal date","Any beach, any island, as long as I can hear the waves while I eat.")],266,false,false,false,"photo-kiana",["Fitness","Travel","Food","Music"],{height:"5'7\"",drinks:"Socially"},490),
    W("Simone Hart",28,"Turks and Caicos",200,"Former pro swimmer, current water-sports instructor.",[P("Unusual skills","Swimming in open water, reading people, and making fish tacos from scratch.")],122,false,false,true,"photo-simone",["Fitness","Travel","Food"],{height:"5'9\"",drinks:"Socially"},520),
    W("Ava Sinclair",27,"Martha's Vineyard, MA",200,"Music journalist. I interview people for a living, so expect good questions and zero awkward silence.",[P("The way to win me over is","Skip the small talk — tell me the thing you never tell people on the first date.")],202,false,false,false,"photo-ava",["Music","Art","Film","Wine"],{height:"5'6\"",drinks:"Regularly"},540),
    W("Kai Williams",29,"Outer Banks, North Carolina",200,"Fitness coach and beach volleyball captain. My laugh carries, my standards are higher.",[P("I'm looking for","Show up with energy. Match mine. Don't try to dim it.")],302,false,false,true,"photo-kai",["Fitness","Travel","Food","Nightlife"],{height:"5'10\"",drinks:"Socially"},530),
  ]);

  // ---- state ----
  const KEY = "auctionbaby.web.v1";
  let S = load();
  // Migrate: ensure new fields exist on older saved states
  if (!S.ownedStatus) S.ownedStatus = [];
  if (S.pass === undefined) S.pass = null;
  function load() {
    try { return JSON.parse(localStorage.getItem(KEY)) || fresh(); }
    catch { return fresh(); }
  }
  function fresh() {
    return { registered: false, role: null,
             me: { name: "", dob: "", age: 27, city: "", bio: "", portrait: "", winMe: "", simplePleasure: "", interests: [], photo: null },
             wallet: 750, floor: [], matches: [], incoming: [], seenSplash: false, reputation: 100,
             ownedStatus: [], pass: null };
  }
  // demo suitors (men bidding on a woman) — used when no backend is configured
  const seedIncoming = () => ([
    ["Marcus Bell", 34, 500, "Dinner at the place with the good scotch. You pick the night."],
    ["Julian Reyes", 31, 1000, "I don't do small talk. Rooftop, Friday — tell me you're in."],
    ["Theo Adler", 38, 750, "Gallery opening, then a late dinner. I'll make it worth the yes."],
    ["Dominic Cross", 29, 300, "Coffee that turns into a long walk. Low pressure, high effort."],
  ].map(([name, age, amount, note]) => ({ id: uid(), name, age, amount, note, hue: hueFrom(name) })));
  const save = () => localStorage.setItem(KEY, JSON.stringify(S));
  if (!S.floor || !S.floor.length) { S.floor = seedFloor(); save(); }

  // ---- router ----
  const go = h => { location.hash = h; };
  window.addEventListener("hashchange", render);

  // ---- UI helpers ----
  let tab = "floor";
  const toast = (t) => {
    const d = document.createElement("div"); d.className = "toast"; d.textContent = t;
    document.body.appendChild(d); setTimeout(() => d.remove(), 2200);
  };

  // Pick an image, downscale to <=1024px, return { blob, dataURL } (JPEG 0.82).
  function pickPhoto(cb) {
    const inp = document.createElement("input");
    inp.type = "file"; inp.accept = "image/*";
    inp.onchange = () => {
      const file = inp.files && inp.files[0]; if (!file) return;
      const img = new Image();
      img.onload = () => {
        URL.revokeObjectURL(img.src);
        const max = 1024, scale = Math.min(1, max / Math.max(img.width, img.height));
        const w = Math.round(img.width * scale), h = Math.round(img.height * scale);
        const cv = document.createElement("canvas"); cv.width = w; cv.height = h;
        cv.getContext("2d").drawImage(img, 0, 0, w, h);
        cv.toBlob(blob => cb({ blob, dataURL: cv.toDataURL("image/jpeg", 0.82) }), "image/jpeg", 0.82);
      };
      img.src = URL.createObjectURL(file);
    };
    inp.click();
  }
  function addPhoto() {
    pickPhoto(({ blob, dataURL }) => {
      if (CONFIGURED() && SIGNED_IN()) {
        API.uploadPhoto(blob).then(d => {
          S.me.photo = (d.photo && d.photo.url) || d.url || (d.photos && d.photos[0] && d.photos[0].url) || dataURL;
          save(); you(); toast("Photo updated.");
        }).catch(e => { S.me.photo = dataURL; save(); you(); toast("Saved locally (upload: " + e.message + ")"); });
      } else { S.me.photo = dataURL; save(); you(); toast("Photo updated."); }
    });
  }
  const tabbar = () => {
    const first = S.role === "woman" ? ["floor", "▦", "Bids"] : ["floor", "▦", "Floor"];
    const unread = (S.matches || []).filter(m => m.unread).length;
    return `<div class="tabbar">
      ${[first, ["matches", "❤", "Matches"], ["store", "⚖", "Store"], ["you", "◉", "You"]]
        .map(([k, ic, l]) => `<button data-tab="${k}" class="${tab === k ? "on" : ""}"><span class="ic">${ic}${k === "matches" && unread ? `<span class="badge">${unread}</span>` : ""}</span>${l}</button>`).join("")}
    </div>`;
  };

  // ================= SCREENS =================
  function render() {
    const h = location.hash.replace(/^#\/?/, "");
    if (!S.registered) return onboarding();
    if (h.startsWith("lot/")) return lotDetail(h.split("/")[1]);
    if (h.startsWith("chat/")) return chat(h.split("/")[1]);
    if (h === "matches") { tab = "matches"; return matches(); }
    if (h === "store") { tab = "store"; return store(); }
    if (h === "paywall") { tab = "store"; return paywall(); }
    if (h.startsWith("paywall/")) { tab = "store"; return paywall(h.split("/")[1]); }
    if (h === "you") { tab = "you"; return you(); }
    tab = "floor"; return S.role === "woman" ? incoming() : floor();
  }

  const ALL_INTERESTS = ["Art","Travel","Fitness","Music","Film","Food","Startups","Reading","Wine","Dogs","Nightlife","Design"];
  let obPhoto = S.me.photo || null;
  let obInterests = [...(S.me.interests || [])];

  function ageFromDOB(dob) {
    if (!dob) return 0;
    const d = new Date(dob), now = new Date();
    let a = now.getFullYear() - d.getFullYear();
    if (now.getMonth() < d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() < d.getDate())) a--;
    return a;
  }

  function onboarding() {
    const me = S.me;
    const roleCard = (k, title, sub) =>
      `<button class="card" style="text-align:left;width:100%;margin-bottom:10px;${S.role === k ? "border-color:var(--gold)" : ""}" data-role="${k}">
         <div class="row"><div class="grow"><div style="font-family:var(--serif);font-weight:800;font-size:18px">${title}</div>
         <div class="faint">${sub}</div></div><div class="pill">${S.role === k ? "Selected" : "Pick"}</div></div></button>`;
    const interestChips = ALL_INTERESTS.map(i =>
      `<button class="chip${obInterests.includes(i) ? " on" : ""}" data-interest="${esc(i)}">${esc(i)}</button>`).join("");
    app.innerHTML = `<div class="screen">
      <div style="text-align:center;margin:18px 0 20px">
        <div class="kicker">Auction Baby</div>
        <h1 class="display" style="margin-top:8px">Bid what a<br>date is worth.</h1>
        <div class="faint" style="margin-top:10px">Find a high-value match — and set the night up right.</div>
      </div>
      <div class="kicker" style="margin:6px 0 8px">Your side of the floor</div>
      ${roleCard("man", "I'm bidding", "Browse the floor and place bids on dates.")}
      ${roleCard("woman", "I'm a lot", "Field bids; accept the one you like.")}

      <div class="kicker" style="margin:18px 0 8px">Your photo</div>
      <div class="card" style="text-align:center;padding:20px">
        <div id="ob-photo-preview" style="width:120px;height:120px;margin:0 auto 12px;border-radius:20px;overflow:hidden;border:2px dashed var(--line);display:grid;place-items:center">
          ${obPhoto ? `<img src="${esc(obPhoto)}" alt="" style="width:100%;height:100%;object-fit:cover">` : `<span class="faint" style="font-size:13px">No photo yet</span>`}
        </div>
        <button class="btn ghost" id="ob-add-photo" style="max-width:200px;margin:0 auto">${obPhoto ? "Change photo" : "Add a photo"}</button>
      </div>

      <div class="kicker" style="margin:18px 0 8px">Basics</div>
      <div class="card">
        <label class="field"><div class="lbl">Name</div><input class="txt" id="ob-name" placeholder="Your name" value="${esc(me.name)}"></label>
        <label class="field"><div class="lbl">Date of birth</div><input class="txt" id="ob-dob" type="date" value="${esc(me.dob || "")}"></label>
        <label class="field"><div class="lbl">City</div><input class="txt" id="ob-city" placeholder="Where you're based" value="${esc(me.city)}"></label>
        <label class="field"><div class="lbl">Portrait tone</div><textarea class="txt" id="ob-portrait" placeholder="About you" rows="2">${esc(me.portrait || "")}</textarea></label>
        <label class="field"><div class="lbl">Bio</div><input class="txt" id="ob-bio" placeholder="One line that makes them lean in" value="${esc(me.bio || "")}"></label>
        <label class="field"><div class="lbl">The way to win me over is</div><input class="txt" id="ob-winme" placeholder="Your answer" value="${esc(me.winMe || "")}"></label>
        <label class="field"><div class="lbl">My simple pleasure</div><input class="txt" id="ob-pleasure" placeholder="Your answer" value="${esc(me.simplePleasure || "")}"></label>
      </div>

      <div class="kicker" style="margin:18px 0 8px">Interests</div>
      <div class="card"><div style="display:flex;flex-wrap:wrap;gap:8px">${interestChips}</div></div>

      ${APPLE_ON() ? `<button class="btn ghost" id="ob-apple" style="margin-top:14px"> Sign in with Apple</button>
        <div class="faint" style="text-align:center;margin-top:6px">Optional — keeps your account across devices.</div>` : ""}
      <button class="btn" id="ob-go" style="margin-top:18px">Step onto the floor</button>
      <div class="disclosure">A bid is the budget you commit to spend on the date itself — dinner, drinks, the evening. It is never a payment to another person.</div>
    </div>`;
    app.querySelectorAll("[data-role]").forEach(b => b.onclick = () => { S.role = b.dataset.role; save(); onboarding(); });
    app.querySelectorAll("[data-interest]").forEach(b => b.onclick = () => {
      const i = b.dataset.interest;
      if (obInterests.includes(i)) obInterests = obInterests.filter(x => x !== i);
      else obInterests.push(i);
      onboarding();
    });
    $("#ob-add-photo").onclick = () => {
      pickPhoto(({ dataURL }) => { obPhoto = dataURL; onboarding(); });
    };
    const ap = $("#ob-apple");
    if (ap) ap.onclick = async () => {
      try {
        const d = await API.signInWithApple();
        const nm = d && d.user && d.user.name;
        if (nm && !$("#ob-name").value) $("#ob-name").value = nm;
        toast("Signed in with Apple.");
      } catch (e) { toast("Apple sign-in: " + e.message); }
    };
    $("#ob-go").onclick = async () => {
      const name = $("#ob-name").value.trim();
      const dob = ($("#ob-dob") || {}).value || "";
      const age = ageFromDOB(dob);
      if (!S.role) return toast("Pick a side first.");
      if (!obPhoto) return toast("Add a photo to continue.");
      if (!name) return toast("Add your name.");
      if (!dob) return toast("Add your date of birth.");
      if (age < 18) return toast("You must be 18 or older.");
      S.me = {
        name, dob, age, city: $("#ob-city").value.trim(),
        bio: ($("#ob-bio") || {}).value.trim(),
        portrait: ($("#ob-portrait") || {}).value.trim(),
        winMe: ($("#ob-winme") || {}).value.trim(),
        simplePleasure: ($("#ob-pleasure") || {}).value.trim(),
        interests: obInterests,
        photo: obPhoto,
      };
      if (CONFIGURED() && SIGNED_IN()) {
        try { await API.saveProfile({ name, location: S.me.city, role: S.role }); } catch (e) { /* non-fatal */ }
      }
      if (S.role === "woman" && !CONFIGURED() && !(S.incoming && S.incoming.length)) S.incoming = seedIncoming();
      S.registered = true; save(); go("/floor"); syncFloor(); syncMatches(); syncIncoming();
    };
  }

  const badges = (w) => `${w.verified ? verifiedBadge() : ""}${w.masterpiece ? masterpieceBadge() : ""}`;

  const showcaseTier = s => s >= 900 ? "Exceptional" : s >= 800 ? "Excellent" : s >= 700 ? "Very Good" : s >= 600 ? "Good" : s >= 500 ? "Fair" : "Needs Work";
  const showcaseStars = s => (3 + (s - 300) / 600 * 2).toFixed(1);
  const showcaseGauge = (score) => {
    const pct = Math.max(0, Math.min(1, (score - 300) / 600));
    const filled = Math.round(pct * 157);
    return `<svg viewBox="0 0 120 70" width="116" style="flex:none">
      <path d="M 10 60 A 50 50 0 0 1 110 60" fill="none" stroke="rgba(255,255,255,.1)" stroke-width="8" stroke-linecap="round"/>
      <path d="M 10 60 A 50 50 0 0 1 110 60" fill="none" stroke="var(--rose)" stroke-width="8" stroke-linecap="round" stroke-dasharray="${filled} 157"/>
      <text x="60" y="48" text-anchor="middle" fill="var(--ink)" style="font-family:var(--serif);font-weight:800;font-size:22px">${score}</text>
      <text x="60" y="64" text-anchor="middle" fill="var(--ink-faint)" style="font-family:var(--sans);font-weight:700;font-size:8px">${showcaseTier(score)}</text>
    </svg>`;
  };
  const getShowcaseFactors = (score) => {
    const adj = score - 300;
    const personality = Math.round(adj * 0.5);
    const dateRatings = Math.round(adj * 0.33);
    const consistency = adj - personality - dateRatings;
    return [
      { name: "Personality", icon: "🎉", points: personality,
        comment: personality > 200 ? "The date everyone talks about after. Fun carries this report."
          : personality > 100 ? "Above average presence. Interesting and engaged."
          : "Building a reputation on the floor." },
      { name: "Date ratings", icon: "⭐", points: dateRatings,
        comment: dateRatings > 100 ? "Consistently high marks from dates. Reliable impressions."
          : dateRatings > 50 ? "Solid ratings across the board."
          : "Early days — more dates build a clearer picture." },
      { name: "Consistency", icon: "📊", points: consistency,
        comment: consistency > 50 ? "Shows up, follows through. Rare and noticed."
          : consistency > 20 ? "Steady. No red flags in the pattern."
          : "Still establishing a track record." },
    ];
  };

  function floor() {
    const mp = S.floor.find(w => w.masterpiece);
    const hero = mp || S.floor[0];
    const rest = S.floor.filter(w => w !== hero);
    const tickers = ["Marcus B. was outbid on Nova Ray — rebid incoming", "3 bidders are watching Mara Quinn", "A Vault of Gavels was just claimed"];
    const tick = tickers[Math.floor(Date.now() / 6000) % tickers.length];
    const lotCard = (w, isHero) => `
      <button class="lot ${isHero ? "hero" : ""}${w.masterpiece ? " masterpiece" : ""}" data-lot="${w.id}" style="width:100%;padding:0;text-align:left;background:none">
        <div class="art">${grad(w.hue, w.name, w.photo)}</div>
        ${isHero ? `<div class="lotofday${w.masterpiece ? " mp" : ""}">⚖ ${w.masterpiece ? "Masterpiece — Lot of the Day" : "Lot of the day"}</div>` : ""}
        <div class="meta">
          <div class="name">${esc(w.name)} <span class="muted" style="font-size:18px">${w.age}</span>${badges(w)}</div>
          ${w.bio ? `<div class="lot-bio">${esc(w.bio)}</div>` : ""}
          ${w.prompts && w.prompts[0] ? `<div class="lot-prompt"><span class="lot-prompt-label">${esc(w.prompts[0].q)}</span> ${esc(w.prompts[0].a)}</div>` : ""}
          <div class="tags"><span class="chip">${esc(w.city)}</span><span class="chip on">${money(w.startingBid)} floor</span></div>
        </div>
      </button>`;
    app.innerHTML = `<div class="screen">
      <div class="topbar"><h1 class="display" style="font-size:30px">The Floor</h1>
        <span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      <div class="faint" style="margin:-6px 0 12px">Bid what a date is worth. She unlocks your photo when she accepts.</div>
      <div class="ticker"><span class="dot"></span><span class="live">LIVE</span><span class="grow">${esc(tick)}</span></div>
      <div class="house-rules">
        <div class="house-rules-title">House Rules</div>
        <div class="house-rules-text">AI "Copycat" profiles walk the floor unlabelled. Bid on one and you're told instantly — it costs you reputation, never money. Spot the fakes.</div>
      </div>
      <div class="floor-header">
        <span class="floor-header-label">On the floor now</span>
        <span class="floor-header-count">${S.floor.length}</span>
      </div>
      ${lotCard(hero, true)}
      ${rest.map(w => lotCard(w, false)).join("")}
    </div>${tabbar()}`;
    wire();
  }

  function lotDetail(id) {
    const w = S.floor.find(x => x.id === id); if (!w) return go("/floor");
    const stars = showcaseStars(w.showcase);
    const fullStars = Math.min(5, Math.round(parseFloat(stars)));
    const starStr = "★".repeat(fullStars) + "☆".repeat(5 - fullStars);
    const factors = getShowcaseFactors(w.showcase);
    const ls = w.lifestyle || {};
    const prompts = w.prompts || [];

    app.innerHTML = `<div class="screen" style="padding-bottom:80px">
      <div class="topbar"><button class="chip" data-back>‹ Floor</button><span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>

      <div class="lot${w.masterpiece ? " masterpiece" : ""}" style="margin-bottom:16px">
        <div class="art">${grad(w.hue, w.name, w.photo)}</div>
        ${w.masterpiece ? `<div class="lotofday mp">⚖ Masterpiece — Lot of the Day</div>` : ""}
        <div class="meta">
          <div class="name">${esc(w.name)} <span class="muted" style="font-size:18px">${w.age}</span>${badges(w)}</div>
          <div class="faint" style="margin-top:2px">${esc(w.city)}</div>
        </div>
      </div>

      ${w.bio ? `<div class="glass detail-card">
        <div class="detail-title"><span class="dt-icon">📝</span> About</div>
        <p style="margin:0;font-size:15px;line-height:1.4;color:var(--ink)">${esc(w.bio)}</p>
      </div>` : ""}

      ${prompts.map((p, i) => `<div class="glass detail-card">
        <div class="prompt-q">${esc(p.q)}</div>
        <div class="prompt-a">${esc(p.a)}</div>
        <button class="bid-mention" data-bid-prompt="${i}">
          <div class="bid-mention-label">✋ Bid &amp; mention this answer</div>
          <span class="bid-mention-sub">A regular bid — this quote just rides along so she knows what caught your eye.</span>
        </button>
      </div>`).join("")}

      ${w.interests && w.interests.length ? `<div class="glass detail-card">
        <div class="detail-title"><span class="dt-icon">✨</span> Interests</div>
        <div style="display:flex;flex-wrap:wrap;gap:8px">${w.interests.map(i => `<span class="chip rose">${esc(i)}</span>`).join("")}</div>
      </div>` : ""}

      ${ls.height || ls.drinks || ls.kids ? `<div class="glass detail-card">
        <div class="detail-title"><span class="dt-icon">👤</span> Lifestyle</div>
        <div style="display:flex;flex-wrap:wrap;gap:8px">
          ${ls.height ? `<span class="chip"><span style="margin-right:4px">📏</span>${esc(ls.height)}</span>` : ""}
          ${ls.drinks ? `<span class="chip"><span style="margin-right:4px">🍷</span>Drinks: ${esc(ls.drinks)}</span>` : ""}
          ${ls.kids ? `<span class="chip rose"><span style="margin-right:4px">👶</span>${esc(ls.kids)}</span>` : ""}
        </div>
      </div>` : ""}

      <div class="glass detail-card">
        <div class="detail-title" style="color:var(--rose)"><span class="dt-icon">🏅</span> Showcase Credit</div>
        <div class="showcase-row">
          ${showcaseGauge(w.showcase)}
          <div class="showcase-side">
            <div style="display:flex;align-items:center;gap:6px">
              <span style="color:var(--gold);font-size:13px">${starStr}</span>
              <span style="font:700 12px/1 var(--sans);color:var(--ink-soft)">${stars}</span>
            </div>
            <div style="font:700 10px/1 var(--sans);color:var(--ink-faint);text-transform:uppercase;letter-spacing:.08em">Market value</div>
            <div style="font:800 22px/1 var(--serif);color:var(--gold)">${money(w.marketValue)}</div>
          </div>
        </div>
      </div>

      <div class="glass detail-card">
        <div class="detail-title" style="color:var(--rose)"><span class="dt-icon">🔍</span> Showcase report</div>
        ${factors.map(f => `<div class="report-row">
            <span class="report-icon">${f.icon}</span>
            <span class="report-name">${f.name}</span>
            <span class="report-pts ${f.points > 0 ? "pos" : f.points < 0 ? "neg" : "zero"}">${f.points >= 0 ? "+" : ""}${f.points}</span>
          </div>
          <div class="report-comment">${f.comment}</div>`).join("")}
        <div class="report-total">
          <span class="report-total-label">Base 300 + adjustments</span>
          <span class="report-total-val">= ${w.showcase}</span>
        </div>
      </div>

      <div style="height:20px"></div>
    </div>
    <div class="sticky-bid"><button class="btn" data-bid="${w.id}">Bid · floor ${money(w.startingBid)}</button></div>`;

    app.querySelector("[data-back]").onclick = () => go("/floor");
    app.querySelector("[data-bid]").onclick = () => bidSheet(w);
    app.querySelectorAll("[data-bid-prompt]").forEach(b => {
      b.onclick = () => bidSheet(w, prompts[+b.dataset.bidPrompt]);
    });
  }

  function bidSheet(w, promptCtx) {
    let amount = Number(w.startingBid) || 100;
    const defaultNote = promptCtx ? `Re: "${promptCtx.q}" — loved your answer.` : "";
    const sheet = document.createElement("div"); sheet.className = "sheet";
    const getNote = () => { const el = sheet.querySelector("#bid-note"); return el ? el.value : defaultNote; };
    const draw = () => { const savedNote = getNote(); sheet.innerHTML = `<div class="panel">
      <div class="grab"></div>
      <div class="row" style="margin-bottom:8px">${gradSm(w.hue, w.name, w.photo)}<div class="grow"><div style="font-family:var(--serif);font-weight:800;font-size:18px">Bidding on ${esc(w.name)}</div><div class="faint">Floor ${money(w.startingBid)}${promptCtx ? " · mentioning her answer" : ""}</div></div></div>
      ${promptCtx ? `<div class="card" style="margin:8px 0 12px;padding:10px 14px"><div class="faint" style="font-size:11px;text-transform:uppercase;letter-spacing:.08em;font-weight:800">${esc(promptCtx.q)}</div><div style="font-family:var(--serif);font-weight:700;margin-top:4px;font-size:14px">${esc(promptCtx.a)}</div></div>` : ""}
      <div class="kicker" style="text-align:center;margin-top:14px">Your bid</div>
      <div class="amount">${money(amount)}</div>
      <div class="row" style="flex-wrap:wrap;justify-content:center;gap:8px;margin:12px 0">
        ${[50, 100, 1000, 10000, 100000].map(a => `<button class="chip" data-add="${a}">+${money(a)}</button>`).join("")}
        <button class="chip" data-reset>Reset</button>
      </div>
      <label class="field"><div class="lbl">Add a note</div><textarea class="txt" id="bid-note" placeholder="Why you? Make the bid count.">${esc(savedNote)}</textarea></label>
      <div class="card" style="margin:10px 0;padding:12px;border-color:rgba(230,184,0,.3);background:rgba(230,184,0,.06)">
        <div class="row" style="gap:10px"><span style="font-size:18px">✍️</span><div class="grow"><div style="font-family:var(--serif);font-weight:800;font-size:13px;color:var(--ink)">The money you'll spend on the date</div><div class="faint" style="font-size:11px;margin-top:2px">Dinner, drinks, the experience — not a payment to her. She keeps the receipts so it can be confirmed after.</div></div></div>
      </div>
      <button class="btn" id="bid-place">Place ${money(amount)} bid</button>
      <div class="disclosure">Spend your bid on the date — the meal, the drinks, the night. She keeps the receipts and confirms it after. Never wire money or send a personal deposit; the app has no way to send money to another user, by design.</div>
    </div>`; };
    draw();
    sheet.onclick = e => { if (e.target === sheet) sheet.remove(); };
    sheet.addEventListener("click", e => {
      const add = e.target.closest("[data-add]"); if (add) { amount += +add.dataset.add; draw(); }
      if (e.target.closest("[data-reset]")) { amount = Number(w.startingBid) || 100; draw(); }
      if (e.target.closest("#bid-place")) { const note = ($("#bid-note") || {}).value || ""; sheet.remove(); placeBid(w, amount, note.trim()); }
    });
    document.body.appendChild(sheet);
  }

  function placeBid(w, amount, note) {
    if (CONFIGURED() && SIGNED_IN()) {
      API.placeBid(w.id, amount, note || "")
        .then(() => { toast("Bid placed — you'll be notified if she accepts."); syncMatches(); })
        .catch(e => toast("Bid failed: " + e.message));
      return;
    }
    if (w.copycat) {
      S.reputation = (S.reputation || 100) - 5;
      save();
      return copycatReveal(w);
    }
    const isMike = (S.me.name || "").trim().toLowerCase() === "mike valasek";
    if (!isMike) return toast(`${w.name} passed. Only accepts bids from Mike Valasek.`);
    const m = { id: uid(), lotId: w.id, name: w.name, hue: w.hue, amount,
                note: note || "",
                messages: [{ me: false, text: w.icebreakers[0] || "You win — where are you taking me?" }] };
    S.matches.unshift(m); save(); celebrate(w, amount, m);
  }

  function copycatReveal(w) {
    const c = document.createElement("div"); c.className = "celebrate copycat";
    c.innerHTML = `<div>
      <div class="kicker" style="color:var(--copycat)">Busted</div>
      <div class="sold">COPYCAT!</div>
      <div style="margin:14px 0">${gradSm(w.hue, w.name)}</div>
      <div style="font-family:var(--serif);font-weight:800;font-size:20px">${esc(w.name)} is an AI profile</div>
      <div class="muted" style="margin-top:6px">No money lost — but your reputation takes a hit.</div>
      <div style="margin-top:10px;font:800 13px/1 var(--sans);color:var(--copycat)">Reputation: ${S.reputation || 95}%</div>
      <button class="btn ghost" style="margin-top:22px;max-width:240px;border-color:var(--copycat);color:var(--copycat)">Back to the floor</button>
      <div class="faint" style="margin-top:10px">Spot the fakes. Protect your rep.</div>
    </div>`;
    c.onclick = () => { c.remove(); go("/floor"); };
    document.body.appendChild(c);
  }

  function celebrate(w, amount, m) {
    const c = document.createElement("div"); c.className = "celebrate";
    c.innerHTML = `<div><div class="kicker">Sold</div><div class="sold">SOLD!</div>
      <div style="margin:14px 0">${gradSm(w.hue, w.name)}</div>
      <div style="font-family:var(--serif);font-weight:800;font-size:20px">Matched with ${esc(w.name)}</div>
      <div class="muted" style="margin-top:6px">Winning bid ${money(amount)}</div>
      <button class="btn" id="sayhi" style="margin-top:22px;max-width:240px">Say hello</button>
      <div class="faint" style="margin-top:10px">Tap anywhere to continue</div></div>`;
    c.onclick = e => { c.remove(); if (e.target.id === "sayhi") go("/chat/" + m.id); };
    document.body.appendChild(c);
  }

  // ---- woman side: incoming bids ----
  function incoming() {
    tab = "floor";
    const bids = S.incoming || [];
    app.innerHTML = `<div class="screen">
      <div class="topbar"><h1 class="display" style="font-size:30px">Your bids</h1><span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      <div class="faint" style="margin:-6px 0 14px">Men bidding for a date. Accept the one you like — his photo unlocks when you do.</div>
      ${bids.length ? bids.map(b => `
        <div class="card" style="margin-bottom:12px">
          <div class="row">${gradSm(b.hue, b.name)}<div class="grow">
            <div style="font-family:var(--serif);font-weight:800">${esc(b.name)} <span class="muted">${b.age || ""}</span></div>
            <div class="gold" style="font-weight:800;font-size:18px">${money(b.amount)}</div></div></div>
          ${b.note ? `<p class="muted" style="margin:10px 0 0">${esc(b.note)}</p>` : ""}
          <div class="row" style="gap:8px;margin-top:12px">
            <button class="btn rose" data-accept="${b.id}">Accept</button>
            <button class="btn ghost" data-decline="${b.id}" style="max-width:110px">Pass</button>
          </div>
        </div>`).join("") : `<div class="card muted">No bids yet — sit tight. The floor moves fast.</div>`}
    </div>${tabbar()}`;
    app.querySelectorAll("[data-accept]").forEach(x => x.onclick = () => acceptBid(x.dataset.accept));
    app.querySelectorAll("[data-decline]").forEach(x => x.onclick = () => declineBid(x.dataset.decline));
    wire();
  }

  function acceptBid(id) {
    const b = (S.incoming || []).find(x => x.id === id); if (!b) return;
    if (CONFIGURED() && SIGNED_IN()) {
      API.acceptBid(id)
        .then(() => { toast("Accepted — say hello."); syncIncoming(); syncMatches(); go("/matches"); })
        .catch(e => toast("Accept failed: " + e.message));
      return;
    }
    // demo: remove from incoming, make a match + open with your line
    S.incoming = (S.incoming || []).filter(x => x.id !== id);
    const m = { id: uid(), name: b.name, hue: b.hue, amount: b.amount,
                messages: [{ me: true, text: "You're in. Where are we going? 🍸" }] };
    S.matches.unshift(m); save(); celebrate(b, b.amount, m);
  }

  function declineBid(id) {
    if (CONFIGURED() && SIGNED_IN()) { API.declineBid(id).catch(() => {}); }
    S.incoming = (S.incoming || []).filter(x => x.id !== id); save(); incoming(); toast("Passed.");
  }

  function matches() {
    app.innerHTML = `<div class="screen">
      <h1 class="display" style="font-size:30px;margin-bottom:14px">Matches</h1>
      ${S.matches.length ? [...S.matches].sort((a, b) => (b.lastTs || 0) - (a.lastTs || 0)).map(m => {
        const last = m.messages[m.messages.length - 1];
        return `<button class="card row" data-chat="${m.id}" style="width:100%;text-align:left;margin-bottom:10px">
          ${gradSm(m.hue, m.name)}<div class="grow"><div style="font-family:var(--serif);font-weight:800">${esc(m.name)}</div>
          <div class="faint" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis;${m.unread ? "color:var(--ink);font-weight:600" : ""}">${esc(last ? (last.photo ? "📷 Photo" : (last.text || "Say hello")) : "Say hello")}</div></div>
          ${m.unread ? `<span class="udot"></span>` : `<span class="pill">${money(m.amount)}</span>`}</button>`;
      }).join("") : `<div class="card muted">No matches yet. Win a bid on the floor.</div>`}
    </div>${tabbar()}`;
    wire();
  }

  function chat(id) {
    const m = S.matches.find(x => x.id === id); if (!m) return go("/matches");
    if (m.unread) { m.unread = false; save(); }
    if (CONFIGURED() && SIGNED_IN()) API.markSeen(id).catch(() => {});
    let lastMe = -1;
    for (let i = m.messages.length - 1; i >= 0; i--) { const x = m.messages[i]; if (x.me && !x.sys) { lastMe = i; break; } }
    const bubbles = m.messages.map((msg, i) => {
      if (msg.sys) return `<div class="bub sys">${esc(msg.text)}</div>`;
      const rx = msg.reaction ? `<span class="rx">${msg.reaction}</span>` : "";
      const receipt = (i === lastMe) ? `<div class="receipt">${m.seen ? "Seen" : "Delivered"}</div>` : "";
      return `<div class="bub ${msg.me ? "me" : "them"}" data-mid="${i}">${esc(msg.text)}${rx}</div>${receipt}`;
    }).join("") + (m.typing ? `<div class="bub them typing">•••</div>` : "");
    app.innerHTML = `<div class="screen" style="padding-bottom:0">
      <div class="topbar"><button class="chip" data-back>‹</button>
        <div class="row">${gradSm(m.hue, m.name)}<b style="font-family:var(--serif)">${esc(m.name)}</b></div>
        <div class="row" style="gap:6px">
          ${S.role === "man" ? (m.reserved ? `<span class="chip on">✓ Reserved</span>` : `<button class="chip" id="reserve">Reserve</button>`) : ""}
          <button class="chip" id="report" title="Report & block">⚑</button>
        </div></div>
      <div class="msgs" id="msgs">${bubbles}</div></div>
      <div class="composer"><input id="ci" placeholder="Message…" autocomplete="off">
        <button class="iconbtn" id="send">↑</button></div>`;
    app.querySelector("[data-back]").onclick = () => go("/matches");
    const rz = $("#reserve"); if (rz) rz.onclick = () => reserveSheet(id);
    const rp = $("#report"); if (rp) rp.onclick = () => reportSheet(id);
    const box = $("#msgs"); box.scrollTop = box.scrollHeight;
    // reactions: double-tap → ❤️, long-press → picker
    app.querySelectorAll(".bub[data-mid]").forEach(b => {
      let t;
      b.addEventListener("dblclick", () => react(id, +b.dataset.mid, "❤️"));
      const start = () => { t = setTimeout(() => rxPicker(id, +b.dataset.mid), 420); };
      const stop = () => clearTimeout(t);
      b.addEventListener("pointerdown", start);
      b.addEventListener("pointerup", stop);
      b.addEventListener("pointerleave", stop);
    });
    const send = () => {
      const i = $("#ci"), tx = i.value.trim(); if (!tx) return;
      m.messages.push({ me: true, text: tx }); m.seen = false; m.lastTs = Date.now(); i.value = ""; save(); chat(id);
      if (CONFIGURED() && SIGNED_IN()) {
        API.sendMessage(id, tx).catch(e => toast("Send failed: " + e.message));
        return; // the real other side replies via syncMatches
      }
      m.typing = true; save(); chat(id);
      setTimeout(() => {
        const replies = ["So where are you taking me?", "Bold. I like it.", "Prove it — pick the place.", "You had me at the bid.", "Friday, then?"];
        m.typing = false; m.seen = true; m.lastTs = Date.now();
        m.messages.push({ me: false, text: replies[Math.floor(Math.random() * replies.length)] });
        save(); if (location.hash.includes("chat/" + id)) chat(id);
      }, 1100 + Math.random() * 900);
    };
    $("#send").onclick = send;
    $("#ci").addEventListener("keydown", e => { if (e.key === "Enter") send(); });
  }

  function react(id, mid, emoji) {
    const m = S.matches.find(x => x.id === id); if (!m || !m.messages[mid]) return;
    const msg = m.messages[mid];
    msg.reaction = (msg.reaction === emoji) ? null : emoji;   // toggle
    save(); chat(id);
    if (CONFIGURED() && SIGNED_IN() && msg.id) API.react(id, msg.id, msg.reaction || "").catch(() => {});
  }

  function rxPicker(id, mid) {
    const bar = document.createElement("div"); bar.className = "rxbar";
    bar.innerHTML = `<div class="row">${["❤️", "😂", "😮", "👍", "🔥"].map(e => `<button data-e="${e}">${e}</button>`).join("")}</div>`;
    bar.onclick = ev => { const b = ev.target.closest("[data-e]"); bar.remove(); if (b) react(id, mid, b.dataset.e); };
    document.body.appendChild(bar);
  }

  // ---- report & block ----
  function reportSheet(matchId) {
    const m = S.matches.find(x => x.id === matchId); if (!m) return;
    const sheet = document.createElement("div"); sheet.className = "sheet";
    sheet.innerHTML = `<div class="panel"><div class="grab"></div>
      <div class="kicker">Report &amp; block</div>
      <p class="muted" style="margin:8px 0 14px">Block ${esc(m.name)} and report to moderation. They're removed from your matches and can no longer contact you.</p>
      <div class="row" style="flex-wrap:wrap;gap:8px">${["Inappropriate", "Harassment", "Fake profile", "Spam", "Other"].map(r => `<button class="chip" data-reason="${r}">${r}</button>`).join("")}</div>
      <button class="btn ghost" data-cancel style="margin-top:14px">Cancel</button></div>`;
    sheet.onclick = e => {
      if (e.target === sheet || e.target.closest("[data-cancel]")) { sheet.remove(); return; }
      const b = e.target.closest("[data-reason]"); if (!b) return;
      const reason = b.dataset.reason; sheet.remove();
      if (CONFIGURED() && SIGNED_IN() && m.otherId) {
        API.blockUser(m.otherId, reason).catch(() => {});
        API.reportUser(m.otherId, reason, "chat").catch(() => {});
      }
      S.matches = S.matches.filter(x => x.id !== matchId); save();
      toast("Reported & blocked."); go("/matches");
    };
    document.body.appendChild(sheet);
  }

  // ---- reserve the date (bidder-only, Stripe booking fee) ----
  function markReserved(matchId) {
    const m = S.matches.find(x => x.id === matchId); if (m) { m.reserved = true; save(); }
    if (location.hash.includes("chat/" + matchId)) chat(matchId);
  }
  function reserveSheet(matchId) {
    const tiers = [1000, 1500, 2500, 5000, 10000]; // $10 / 15 / 25 / 50 / 100
    const sheet = document.createElement("div"); sheet.className = "sheet";
    sheet.innerHTML = `<div class="panel"><div class="grab"></div>
      <div class="kicker">Reserve the date</div>
      <p class="muted" style="margin:8px 0 14px">A booking fee to lock in your in-person date. It goes to Auction Baby for the reservation — never to her — and unlocks nothing in the app. You still spend your bid on the date itself; she keeps the receipts.</p>
      <div class="row" style="flex-wrap:wrap;gap:8px">${tiers.map(c => `<button class="chip" data-cents="${c}">$${c / 100}</button>`).join("")}</div>
      <div class="faint" style="margin-top:12px">Web payments via Stripe.</div></div>`;
    sheet.onclick = e => {
      if (e.target === sheet) { sheet.remove(); return; }
      const b = e.target.closest("[data-cents]"); if (!b) return;
      const cents = +b.dataset.cents; sheet.remove();
      if (CONFIGURED() && SIGNED_IN()) {
        API.reserveDate(matchId, cents)
          .then(d => { if (d.reserved || d.url === "about:blank") markReserved(matchId); }) // else it redirected to Stripe
          .catch(er => toast("Reserve: " + er.message));
      } else { markReserved(matchId); toast("Demo: date reserved."); }
    };
    document.body.appendChild(sheet);
  }

  // ── Status archetype catalog (mirrors iOS Archetype.swift exactly) ──
  const STATUS_TIERS = [
    { id: "status_goodguy",      name: "Good Guy",              price: 4.99,    blurb: "Texts back. Probably splits the bill.",                 icon: "👍", tint: "var(--success)" },
    { id: "status_inandout",     name: "In & Out Guy",          price: 9.99,    blurb: "Efficient. Knows what he wants.",                      icon: "⚡", tint: "var(--success)" },
    { id: "status_whynot",       name: "Why Not Guy",           price: 19.99,   blurb: "The shrug that launched a thousand dates.",            icon: "😄", tint: "var(--success)" },
    { id: "status_goodjob",      name: "Got a Good Job",        price: 99.99,   blurb: "Salaried, LinkedIn-verified energy.",                  icon: "💼", tint: "var(--gold)" },
    { id: "status_inheritance",  name: "Inheritance Money Guy", price: 500,     blurb: "Didn't earn it. Will absolutely spend it.",             icon: "🏛", tint: "var(--gold)" },
    { id: "status_influencer",   name: "Influencer",            price: 800,     blurb: "Will film the date. You signed nothing.",              icon: "📷", tint: "var(--rose)" },
    { id: "status_ferrari",      name: "I Drive a Ferrari",    price: 900,     blurb: "The car is leased. The flex is real.",                  icon: "🏎", tint: "var(--rose)" },
    { id: "status_trillionaire", name: "Trillionaire",         price: 1000,    blurb: "Can mint a Masterpiece. The whole floor turns.",        icon: "👑", tint: "var(--gold-soft)", prestige: true },
  ];
  const PASS_TIERS = [
    { id: "Paddle",     price: 19.99, icon: "✋", perks: ["Unlimited bids", "See if you're the top bid", "1 Boost / week"] },
    { id: "Reserve",    price: 39.99, icon: "🔓", perks: ["Everything in Paddle", "Reveal her reserve price", "Auto-rebid to stay on top", "Rewind your last bid"] },
    { id: "Black Card", price: 99.99, icon: "💳", perks: ["Everything in Reserve", "Priority placement on every lot", "Read receipts"] },
  ];
  // Benefits matrix for the paywall: (label, lowest tier index that includes it)
  const PAYWALL_BENEFITS = [
    ["Unlimited live bids", 0],
    ["See if you're the top bid", 0],
    ["1 Spotlight Boost every week", 0],
    ["Reveal her reserve price", 1],
    ["Auto-rebid to stay on top", 1],
    ["Advanced filters (verified-only, interests)", 1],
    ["Rewind your last bid", 1],
    ["Read receipts — Seen / Delivered", 2],
    ["Priority placement in every inbox", 2],
  ];
  const PAYWALL_TRIGGERS = {
    rankReveal:   { headline: "She's comparing bids.<br>See where you stand.", icon: "📊", suggested: 0 },
    bidLimit:     { headline: "Out of free bids.<br>The floor doesn't wait.", icon: "🚫", suggested: 0 },
    filters:      { headline: "Cut the noise.<br>Bid only on your type.", icon: "🎛", suggested: 1 },
    readReceipts: { headline: "She read it.<br>Know the moment she does.", icon: "✓", suggested: 2 },
    rewind:       { headline: "Bid too soon?<br>Take it back.", icon: "↩", suggested: 1 },
    general:      { headline: "Win the bid<br>you can't see.", icon: "👑", suggested: 0 },
  };

  function store() {
    const packs = [["Handful", 1000, 4.99], ["Stack", 5000, 19.99], ["Chest", 14000, 49.99], ["Vault", 30000, 99.99]];
    const isMan = S.role === "man";
    app.innerHTML = `<div class="screen">
      <div class="topbar"><h1 class="display" style="font-size:28px">Store</h1><span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      ${isMan ? `
      <div class="kicker" style="margin:8px 0">Top up Gavels</div>
      ${packs.map(([n, g, p], i) => `<div class="card row" style="margin-bottom:10px"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">${g.toLocaleString()} Gavels ${i === packs.length - 1 ? '<span class="pill">BEST VALUE</span>' : ""}</div>
        <div class="faint">${n} of Gavels</div></div><button class="chip on" data-buy="${g}" data-price="${p}">$${p}</button></div>`).join("")}
      <div class="kicker" style="margin:16px 0 8px">Spotlight Boost</div>
      <div class="card row" style="margin-bottom:10px"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">Spotlight Boost</div>
        <div class="faint">30 minutes at the very top of the floor.</div></div>
        <button class="chip rose" data-boost>$4.99</button></div>
      <div class="kicker" style="margin:16px 0 8px">Status</div>
      ${STATUS_TIERS.map(t => `<div class="card row" style="margin-bottom:10px${t.prestige ? ";border-color:rgba(230,184,0,.5);box-shadow:0 0 0 1px rgba(230,184,0,.15)" : ""}"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">${t.icon} ${t.name}${t.prestige ? ' <span class="pill">TOP TIER</span>' : ""}</div>
        <div class="faint">${t.blurb}</div></div>
        <button class="chip ${t.prestige ? 'on' : 'rose'}" data-status="${t.id}" data-price="${t.price}">${S.ownedStatus && S.ownedStatus.includes(t.id) ? 'Owned' : '$' + t.price.toLocaleString()}</button></div>`).join("")}
      <div class="faint" style="margin:8px 0">Every rating is a real purchase — the number is the whole point. Buy one and it's yours for good.</div>
      <div class="kicker" style="margin:16px 0 8px">Auction Baby Pass</div>
      ${PASS_TIERS.map(t => `<div class="card" style="margin-bottom:10px"><div class="row"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">${t.icon} ${t.name} <span class="muted">· $${t.price}/mo</span></div>
        <div class="faint">${t.perks.join(" · ")}</div></div><button class="chip rose" data-sub="${t.id}">Subscribe</button></div></div>`).join("")}
      ` : `
      <div class="kicker" style="margin:8px 0">Spotlight Boost</div>
      <div class="card row" style="margin-bottom:10px"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">Spotlight Boost</div>
        <div class="faint">30 minutes at the very top of the floor.</div></div>
        <button class="chip rose" data-boost>$4.99</button></div>
      `}
      <div class="disclosure">Payments on the web are processed by Stripe. Gavels are in-app status currency and are never a payment to another user. Passes auto-renew monthly until canceled.</div>
    </div>${tabbar()}`;
    app.querySelectorAll("[data-buy]").forEach(b => b.onclick = () => checkout("gavels", +b.dataset.buy, +b.dataset.price));
    app.querySelectorAll("[data-sub]").forEach(b => b.onclick = () => checkout("pass", b.dataset.sub));
    app.querySelectorAll("[data-boost]").forEach(b => b.onclick = () => checkout("boost"));
    app.querySelectorAll("[data-status]").forEach(b => b.onclick = () => checkout("status", b.dataset.status, +b.dataset.price));
    wire();
  }

  // ── Paywall (1:1 with iOS PaywallView) ─────────────────────────────────
  // Triggered at peak-intent moments. Shows a tier picker, benefits matrix,
  // and a single CTA — exactly like the iOS paywall.
  let paywallSelected = 0; // index into PASS_TIERS
  function paywall(trigger) {
    const t = PAYWALL_TRIGGERS[trigger] || PAYWALL_TRIGGERS.general;
    paywallSelected = t.suggested;
    const activePass = S.pass || null; // track active pass in demo mode
    function render() {
      const sel = PASS_TIERS[paywallSelected];
      const isActive = activePass === sel.id;
      app.innerHTML = `<div class="screen" style="padding-bottom:100px">
        <div style="text-align:center;padding:20px 0 8px">
          <div style="font-size:48px;margin-bottom:10px">${t.icon}</div>
          <h1 class="display" style="font-size:28px;line-height:1.15">${t.headline}</h1>
          <div class="kicker" style="margin-top:10px">Auction Baby Pass</div>
        </div>
        <div class="row" style="gap:10px;margin:16px 0">
          ${PASS_TIERS.map((tier, i) => `
            <button class="paywall-tier ${i === paywallSelected ? 'on' : ''}" data-tier="${i}">
              <div style="font-size:22px;margin-bottom:4px">${tier.icon}</div>
              <div style="font-family:var(--serif);font-weight:800;font-size:14px;color:var(--ink)">${tier.id}</div>
              <div style="font-family:var(--sans);font-weight:800;font-size:16px;color:${i === paywallSelected ? 'var(--gold)' : 'var(--ink-soft)'}">$${tier.price}</div>
              <div class="faint" style="font-size:10px">/ month</div>
            </button>`).join("")}
        </div>
        <div class="glass" style="border-radius:18px;overflow:hidden">
          ${PAYWALL_BENEFITS.map(([label, minTier], i) => {
            const included = paywallSelected >= minTier;
            return `<div class="row" style="padding:12px 16px;${i < PAYWALL_BENEFITS.length - 1 ? 'border-bottom:1px solid var(--line)' : ''}">
              <span style="font-size:16px">${included ? '✅' : '🔒'}</span>
              <div class="grow" style="font-size:13px;font-weight:600;color:${included ? 'var(--ink)' : 'var(--ink-faint)'}">${label}</div>
              ${!included ? `<span class="pill" style="font-size:10px">${PASS_TIERS[minTier].id}</span>` : ''}
            </div>`;
          }).join("")}
        </div>
        <div style="margin-top:16px">
          ${isActive
            ? `<div style="text-align:center;padding:15px;border-radius:16px;background:rgba(92,201,138,.14);color:var(--success);font-weight:800;font-size:15px">✓ ${sel.id} is active</div>`
            : `<button class="btn ${sel.id === 'Black Card' ? '' : 'rose'}" style="width:100%;font-size:16px" data-cta>
                ${sel.id === 'Black Card' ? '👑' : '✨'} Continue with ${sel.id}
              </button>
              ${S.role === 'woman' ? '' : `<button class="btn ghost" style="margin-top:10px;width:100%" data-back>Maybe later</button>`}`
          }
        </div>
        <div class="disclosure" style="margin-top:16px">
          Auto-renews monthly until canceled at least 24h before the period ends. Web payments processed by Stripe.
          ${window.AB_CONFIG && window.AB_CONFIG.CONSUMABLES_URL ? '' : ' (Demo mode — no charge. Configure Stripe for live.)'}
        </div>
      </div>${tabbar()}`;
      app.querySelectorAll("[data-tier]").forEach(b => b.onclick = () => {
        paywallSelected = +b.dataset.tier;
        render();
      });
      const cta = app.querySelector("[data-cta]");
      if (cta) cta.onclick = () => checkout("pass", PASS_TIERS[paywallSelected].id);
      const back = app.querySelector("[data-back]");
      if (back) back.onclick = () => go("/store");
      wire();
    }
    render();
  }

  function checkout(kind, a, price) {
    // LIVE: Gavel packs via Stripe Checkout (consumables Worker).
    if (kind === "gavels" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      const packId = GAVEL_PACK_ID[a] || String(a);
      API.me()
        .then(u => API.buyGavels(packId, u.id || u.userId))   // → redirects to Stripe
        .catch(e => toast("Checkout: " + e.message));
      return;
    }
    // LIVE: Recurring Pass via Stripe Billing.
    if (kind === "pass" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      const passId = PASS_ID[a] || a;
      API.me().then(u => API.subscribe(passId, u.id || u.userId)).catch(e => toast("Subscribe: " + e.message));
      return;
    }
    // LIVE: Spotlight Boost via Stripe Checkout (one-time).
    if (kind === "boost" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      API.me().then(u => API.buyBoost(u.id || u.userId)).catch(e => toast("Boost: " + e.message));
      return;
    }
    // LIVE: Status Archetype via Stripe Checkout (one-time, owned forever).
    if (kind === "status" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      const statusId = a;
      API.me().then(u => API.buyStatus(statusId, u.id || u.userId)).catch(e => toast("Status: " + e.message));
      return;
    }
    // DEMO fallback (no charge).
    if (kind === "gavels") { S.wallet += a; save(); toast(`Demo: +${a.toLocaleString()} Gavels (configure Stripe for live).`); store(); }
    else if (kind === "boost") { toast("Demo: Boost active for 30 min (configure Stripe for live)."); }
    else if (kind === "status") {
      S.ownedStatus = S.ownedStatus || [];
      if (!S.ownedStatus.includes(a)) S.ownedStatus.push(a);
      save(); toast(`Demo: Status unlocked (configure Stripe for live).`); store();
    }
    else if (kind === "pass") { S.pass = a; save(); toast(`Demo: ${a} Pass active (configure Stripe for live).`); store(); }
    else toast(`Demo: ${a} active (configure Stripe for live).`);
  }

  function you() {
    const me = S.me;
    const interests = (me.interests || []).map(i => `<span class="chip on" style="pointer-events:none">${esc(i)}</span>`).join("");
    const ownedBadges = (S.ownedStatus || []).map(id => {
      const t = STATUS_TIERS.find(s => s.id === id);
      return t ? `<span class="pill" style="margin:2px">${t.icon} ${t.name}</span>` : "";
    }).join("");
    app.innerHTML = `<div class="screen">
      <div class="card" style="text-align:center;padding:24px">
        <div style="width:96px;margin:0 auto 12px">${grad(210, me.name || "You", me.photo)}</div>
        <div style="font-family:var(--serif);font-weight:800;font-size:22px">${esc(me.name || "You")} <span class="muted">${me.age}</span></div>
        <div class="faint">${esc(me.city || "")} · ${S.role === "man" ? "Bidder" : "Lot"}</div>
        <div class="pill" style="margin-top:12px">⚖ ${S.wallet.toLocaleString()} Gavels</div>
        ${typeof S.reputation === "number" ? `<div class="faint" style="margin-top:8px">Reputation: ${S.reputation}%</div>` : ""}
        ${S.pass ? `<div class="pill" style="margin-top:6px;background:rgba(224,96,122,.14);color:var(--rose)">✓ ${S.pass} Pass</div>` : ""}
        ${ownedBadges ? `<div style="margin-top:10px">${ownedBadges}</div>` : ""}
      </div>
      ${me.bio ? `<div class="card" style="margin-top:12px"><div class="kicker">Bio</div><div class="muted" style="margin-top:6px">${esc(me.bio)}</div></div>` : ""}
      ${me.portrait ? `<div class="card" style="margin-top:10px"><div class="kicker">Portrait</div><div class="muted" style="margin-top:6px">${esc(me.portrait)}</div></div>` : ""}
      ${me.winMe ? `<div class="card" style="margin-top:10px"><div class="faint">The way to win me over is</div><div style="font-family:var(--serif);font-weight:700;margin-top:4px">${esc(me.winMe)}</div></div>` : ""}
      ${me.simplePleasure ? `<div class="card" style="margin-top:10px"><div class="faint">My simple pleasure</div><div style="font-family:var(--serif);font-weight:700;margin-top:4px">${esc(me.simplePleasure)}</div></div>` : ""}
      ${interests ? `<div class="card" style="margin-top:10px"><div class="kicker" style="margin-bottom:8px">Interests</div><div style="display:flex;flex-wrap:wrap;gap:8px">${interests}</div></div>` : ""}
      <button class="btn ghost" id="addphoto" style="margin-top:14px">${me.photo ? "Change photo" : "Add a photo"}</button>
      <button class="btn ghost" data-tab="store" style="margin-top:10px">Open the Store</button>
      ${S.role === "man" && !S.pass ? `<button class="btn" style="margin-top:10px" data-go="paywall">Get an Auction Baby Pass</button>` : ""}
      ${(CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.VAPID_PUBLIC_KEY) ? `<button class="btn ghost" id="notif" style="margin-top:10px">Enable notifications</button>` : ""}
      ${SIGNED_IN() ? `<button class="btn ghost" id="signout" style="margin-top:10px">Sign out</button>` : ""}
      <button class="btn ghost" id="reset" style="margin-top:10px;color:var(--danger)">Reset account</button>
      ${SIGNED_IN() ? `<button class="btn ghost" id="delacct" style="margin-top:10px;color:var(--danger)">Delete account permanently</button>` : ""}
      <div class="disclosure">Auction Baby — web. A bid is a promise to spend on the date, never a payment to another person.</div>
    </div>${tabbar()}`;
    $("#addphoto").onclick = addPhoto;
    const notif = $("#notif"); if (notif) notif.onclick = () => API.enableWebPush().then(() => toast("Notifications on.")).catch(e => toast("Notifications: " + e.message));
    const so = $("#signout"); if (so) so.onclick = () => { API.signOutLocal(); S.registered = false; save(); toast("Signed out."); go("/"); onboarding(); };
    const da = $("#delacct"); if (da) da.onclick = async () => {
      if (!confirm("Permanently delete your account? This can't be undone.")) return;
      try { await API.deleteAccount(); } catch (e) { /* proceed with local wipe */ }
      API.signOutLocal(); S = fresh(); S.floor = seedFloor(); obPhoto = null; obInterests = []; save(); toast("Account deleted."); go("/"); onboarding();
    };
    $("#reset").onclick = () => { if (confirm("Reset everything?")) { S = fresh(); S.floor = seedFloor(); obPhoto = null; obInterests = []; save(); go("/"); onboarding(); } };
    wire();
  }

  // ---- shared wiring for lists/tabs ----
  function wire() {
    app.querySelectorAll("[data-lot]").forEach(b => b.onclick = () => go("/lot/" + b.dataset.lot));
    app.querySelectorAll("[data-chat]").forEach(b => b.onclick = () => go("/chat/" + b.dataset.chat));
    app.querySelectorAll("[data-go]").forEach(b => b.onclick = () => go("/" + b.dataset.go));
    document.querySelectorAll("[data-tab]").forEach(b => b.onclick = () => go("/" + b.dataset.tab));
  }

  // ---- boot ----
  if (!location.hash) go(S.registered ? "/floor" : "/");
  render();
  if (location.hash.includes("paid=1")) toast("Payment complete — Gavels added.");
  // demo woman returning with no bids left → reseed so the screen isn't empty
  if (S.registered && S.role === "woman" && !CONFIGURED() && !(S.incoming && S.incoming.length)) { S.incoming = seedIncoming(); save(); }
  if (S.registered && CONFIGURED() && SIGNED_IN()) { syncFloor(); syncMatches(); syncIncoming(); }
})();
