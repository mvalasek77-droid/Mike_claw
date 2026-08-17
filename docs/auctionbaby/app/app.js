/* Auction Baby — PWA (vanilla JS, no build step).
   Runs standalone on demo data (localStorage); the API layer is stubbed so it
   can later point at the existing Cloudflare Workers. Web monetization is
   Stripe, not Apple IAP. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const app = $("#app");
  const money = n => "$" + (n >= 1000 ? n.toLocaleString("en-US") : n);
  const esc = s => (s || "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const uid = () => Math.random().toString(36).slice(2, 10);

  // ---- live backend (Cloudflare Workers) with graceful demo fallback ----
  const API = window.AB_API || {};
  const CONFIGURED = () => !!window.AB_LIVE;                       // backend URLs set
  const SIGNED_IN = () => !!(API.hasSession && API.hasSession());  // have a session token
  const APPLE_ON = () => !!(window.AB_CONFIG && window.AB_CONFIG.APPLE_SERVICE_ID);
  const hueFrom = s => { let h = 0; for (const c of (s || "")) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
  const GAVEL_PACK_ID = { 1000: "gavels_handful", 5000: "gavels_stack", 14000: "gavels_chest", 30000: "gavels_vault" };
  const PASS_ID = { "Paddle": "pass_paddle", "Reserve": "pass_reserve", "Black Card": "pass_blackcard" };

  // Map a server profile → the local lot shape (matches the Worker's publicProfile:
  // userId, name, age, location, bio, hue, startingBid, verified, photos:[{url}], prompts).
  const mapLot = p => ({
    id: p.userId || p.id, name: p.name || "—", age: p.age || 27, city: p.location || p.city || "",
    startingBid: p.startingBid || 100, bio: p.bio || "",
    icebreakers: (p.prompts || []).map(x => (x && x.answer) || x).filter(Boolean),
    hue: (typeof p.hue === "number" ? Math.round(p.hue * 360) : hueFrom(p.userId || p.name)),
    verified: !!p.verified,
    photo: (p.photos && p.photos[0] && p.photos[0].url) || null,
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

  // ---- demo floor (all 54 women from the iOS app with photos) ----
  const seedFloor = () => ([
    ["Serena Voss",28,"Upper East Side, New York",1000000,"Private art dealer. Quiet dinners, old buildings, men who don't explain their watch.",["Know what you want and don't apologize for it.","Close a gallery and open the wine they keep behind the counter."],306,false,"photo-serena"],
    ["Rae",27,"SoHo, New York",100,"Gallery girl by day, downtown by night. I know what I want and I don't settle.",["Be direct, be confident, and make the reservation before you ask."],180,true,"photo-grace"],
    ["Sloane",31,"Venice, Los Angeles",150,"Founder, second company. I like early mornings, good espresso, and people who follow through.",["Skip the small talk and split the tasting menu.","Working with a good cofounder — direct, loyal, occasionally intense."],198,true,"photo-sloane"],
    ["Mara Quinn",27,"SoHo, New York",250,"Gallery curator. I spend my weekends at openings and my weeknights pretending I'll stop buying art books.",["Make the reservation and don't cancel it.","A negroni, a window seat, and leaving the party at the right time."],331,false,"photo-mara"],
    ["Priya Sethi",29,"Lincoln Park, Chicago",300,"ER doctor. My schedule is chaos, so when I'm off, I'm actually present.",["Medicine, obviously — but also 90s R&B. I will take over the aux.","Calls his mom. Tips well. Asks follow-up questions."],29,false,"photo-priya"],
    ["Harper Wells",31,"Venice, Los Angeles",500,"Producer. I survive on espresso and deadline adrenaline. Looking for someone who can keep up on a Sunday hike.",["Skip the small talk and split the tasting menu.","Working with a good cofounder — direct, loyal, occasionally intense."],198,false,"photo-harper"],
    ["Bella Rose",23,"Miami Beach",200,"Pool days, boat weekends, and a standing reservation at my favorite rooftop. Come keep up.",["Sunset drinks somewhere over the water. You handle the details."],342,false,"photo-bella"],
    ["Noor Haddad",26,"Capitol Hill, Seattle",200,"Climate engineer. I'll hike in any weather and I fact-check fun facts — lovingly.",["Got weathered-in on a glacier for two days. Still the best trip of my life.","Parallel parking and reading a room."],151,false,"photo-noor"],
    ["Valentina Cruz",28,"Williamsburg, Brooklyn",200,"Pastry chef. I work Saturdays, so impress me on a Tuesday. Bonus points if you actually like dessert.",["Cooking for people, then watching their face on the first bite."],47,false,"photo-valentina"],
    ["Crystal Lux",24,"Las Vegas",200,"Cocktail dresses over casual, always. If you can't decide where to take me, I already know how the date ends.",["I've been to 30 countries, I hate champagne, and I always text back."],281,false,"photo-crystal"],
    ["Jade Rivera",25,"Tulum",200,"Yoga teacher splitting time between Tulum and wherever the next retreat is. Sunrise person, unapologetically.",["The beach at 6am before anyone else is up."],288,false,"photo-jade"],
    ["Amber Skye",24,"Malibu",200,"Grew up on this coast and never left. Golden hour is a personality trait, I've accepted it.",["Tacos on the beach, then see where the night goes."],25,false,"photo-amber"],
    ["Tiana Brooks",27,"Georgetown, DC",200,"Brand strategist who accidentally became a weekend DJ. I own too many blazers and not enough patience for small talk.",["Someone who knows what they want and orders first."],65,false,"photo-tiana"],
    ["Lucia Reyes",25,"Ibiza",200,"Summers in Europe, winters wherever the sun is. I collect wine, sunsets, and men who can keep up.",["Somewhere with a view and a bottle we'll remember. You pick the place."],7,false,"photo-lucia"],
    ["Elena Marsh",26,"Pacific Palisades, LA",200,"Interior designer. I notice things — the way a room is lit, where you sit, whether you hold the door.",["You read something this week. You have a plant that's still alive."],223,false,"photo-elena"],
    ["Sophie Hale",28,"Nolita, New York",200,"PR director. Half my wardrobe is black, the other half is statement coats. I leave parties early and restaurants late.",["Split a cab uptown and argue about where to eat next."],50,false,"photo-sophie"],
    ["Zara Collins",24,"Harlem, New York",200,"Freelance photographer. I shoot everything but will only eat at places I've already been twice.",["Showing up. On time. With coffee. Every single time."],126,false,"photo-zara"],
    ["Anaya Mehta",27,"West Village, New York",200,"Product lead at a startup nobody's heard of yet. Weekend mornings are for the farmers market, not my phone.",["Skincare ingredients, behavioral economics, and making the perfect dal."],209,false,"photo-anaya"],
    ["Fiona Byrne",26,"Savannah, Georgia",200,"Garden designer. I grow things for a living and ruin book spines for fun.",["A used bookstore, an iced coffee, and nowhere I have to be."],14,false,"photo-fiona"],
    ["Camille Adler",32,"Gold Coast, Chicago",200,"Wine importer. I've been to more vineyards than restaurants but I still can't say no to a good tasting menu.",["I can blind-taste a Burgundy from a Bordeaux. And I parallel park on the first try."],43,false,"photo-camille"],
    ["Mei Lin Chen",25,"DUMBO, Brooklyn",200,"Architect. I think in floor plans and talk in references nobody gets.",["A building with good bones — worth the renovation."],245,false,"photo-mei"],
    ["Nikki West",29,"Newport Beach, CA",200,"Charter broker. Weekdays I sell the boat, weekends I'm on it.",["Sunset sail. No agenda, no timeline, just the ocean and whatever we're drinking."],194,false,"photo-nikki"],
    ["Brooke Taylor",30,"Scottsdale, Arizona",200,"Real estate. I flip houses and friendships — both need good foundation.",["Pick the restaurant, pick me up, and don't check your phone once."],36,false,"photo-brooke"],
    ["Harper Lane",26,"Byron Bay, Australia",200,"Surf instructor half the year, content creator the other half. I'll outswim you and outeat you.",["Beach, tacos, sunset. In that order."],18,false,"photo-harper"],
    ["Dana Walsh",33,"Tribeca, New York",200,"Pilates studio owner. My mornings start at 5:30 and I wouldn't have it any other way.",["He has a morning routine that doesn't start with his phone."],324,false,"photo-dana"],
    ["Chloe Park",28,"Charleston, South Carolina",200,"Event planner. I turn empty rooms into something people remember.",["Sweet tea, a good porch, and a dog that greets me at the door."],79,false,"photo-chloe"],
    ["Kendall Marsh",27,"Laguna Beach, CA",200,"Jewelry designer. I make things with my hands, collect sea glass, and take the long way everywhere.",["Drive down the coast with no plan and stop wherever looks good."],25,false,"photo-kendall"],
    ["Riley Stone",29,"Nantucket, Massachusetts",200,"Cookbook author. I test recipes until midnight and wake up craving coffee and feedback.",["Farmers markets, sourdough timers, and restaurants that don't have a website."],58,false,"photo-riley"],
    ["Lexi Monroe",25,"Palm Beach, Florida",200,"Luxury travel consultant. I book the trips everyone posts about, then take my own with no itinerary.",["Got bumped to first class in Rome, ended up at a stranger's vineyard for dinner."],22,false,"photo-lexi"],
    ["Paige Nolan",31,"Calabasas, CA",200,"Wellness brand founder. I built my company poolside and I'm not apologizing for it.",["A five-star retreat — intentional, restorative, and you'll leave better than you came in."],295,false,"photo-paige"],
    ["Sienna Clarke",27,"Santa Barbara, CA",200,"Botanical illustrator. I spend most of my time outside, most of my money on plants.",["Any garden, anywhere. The wilder the better."],137,false,"photo-sienna"],
    ["Hayley James",30,"Savannah, Georgia",200,"Restaurant owner. Sunday brunch is my religion and Saturday night is my confessional.",["Sit at the bar, order something interesting, and make me laugh before the food comes."],72,false,"photo-hayley"],
    ["Maya Santos",26,"South Beach, Miami",200,"Marine biologist who somehow ends up at the beach even on days off. Science by day, salsa by night.",["Identifying fish, dancing in heels, and leaving the party at exactly the right time."],173,false,"photo-maya"],
    ["Autumn Reed",28,"Asheville, North Carolina",200,"Trail runner and part-time park ranger. Warm, colorful, and gone too fast.",["A trail at golden hour, then wherever the nearest firepit is. Bring layers."],32,false,"photo-autumn"],
    ["Cassidy Blake",27,"Cabo San Lucas",200,"Yacht broker. I sell the dream and live it on weekends.",["Take the boat out, anchor somewhere nobody else is, and forget what day it is."],11,false,"photo-cassidy"],
    ["Nia Jordan",29,"Arts District, Los Angeles",200,"Muralist and fitness coach. I paint walls by day and teach spin by evening.",["Shows up when he says he will. Knows what he wants for dinner. Has hobbies that aren't screens."],259,false,"photo-nia"],
    ["Yuki Tanaka",26,"Santa Monica, CA",200,"Yoga instructor and breathwork facilitator. Sunrise on the pier is my temple.",["Presence. Put the phone away and just be here with me."],274,false,"photo-yuki"],
    ["Charlotte Fox",31,"Greenwich, Connecticut",200,"Antiques dealer. I know what things are worth and I don't negotiate on the ones that matter.",["I can date a piece of furniture from across the room and pick the best bottle on any list."],54,false,"photo-charlotte"],
    ["Jordan Obi",27,"Joshua Tree, CA",200,"Adventure photographer. I chase light for a living and silence for fun.",["Camped alone in the desert for a week shooting stars. Best photos I've ever taken."],108,false,"photo-jordan"],
    ["Lily Tran",25,"Kitsilano, Vancouver",200,"UX designer who walks everywhere. Cherry blossom season is my Super Bowl.",["Typography, city planning, and the way light changes between 5 and 6 PM."],317,false,"photo-lily"],
    ["Hana Kim",24,"Queen Anne, Seattle",200,"Dance teacher and part-time barista. I know everyone's order and nobody's last name.",["A matcha latte, a park bench, and watching dogs I don't own play fetch."],230,false,"photo-hana"],
    ["Grace Ashford",30,"Annapolis, Maryland",200,"Sailing instructor. I grew up on the water and I still haven't found a reason to leave it.",["A day on the bay — calm on the surface, more going on underneath than you'd expect."],162,false,"photo-grace"],
    ["Destiny Moore",28,"Sedona, Arizona",200,"Personal trainer and hiking guide. Golden hour is my office.",["Sunrise hike, then breakfast at the place only locals know."],338,false,"photo-destiny"],
    ["Stella Cruz",27,"Sayulita, Mexico",200,"Surf photographer. I chase golden hour the way some people chase promotions.",["Catch the last wave, rinse off, and eat tacos with sandy feet."],115,false,"photo-stella"],
    ["Britt Larson",25,"Mission Beach, San Diego",200,"Physical therapist who spends every lunch break at the beach.",["A towel, a good playlist, and absolutely nowhere I need to be."],4,false,"photo-britt"],
    ["Nova Ray",26,"Playa del Carmen, Mexico",200,"Freediver and ocean conservationist. I hold my breath for a living and speak my mind for free.",["Holding my breath for four minutes, finding hidden beaches, and making friends in every country."],180,false,"photo-nova"],
    ["Tessa Flynn",28,"Maui, Hawaii",200,"Dive instructor by morning, bartender by night. I live on island time and I'm not going back.",["Moved to Maui for a month. That was three years ago."],313,false,"photo-tessa"],
    ["Wren Bishop",26,"Montauk, New York",200,"Photographer. Sunset is my golden hour and the beach is my studio. I shoot on film and live like it.",["A cold drink, warm sand, and a conversation that doesn't need a phone."],101,false,"photo-wren"],
    ["Iris Calloway",29,"Positano, Italy",200,"Ceramicist splitting time between Italy and Brooklyn. Freckles are earned, not filtered.",["Remember what I said last time. That's it. That's the whole thing."],144,false,"photo-iris"],
    ["Adriana Vega",27,"Barcelona, Spain",200,"Chef de partie at a Michelin kitchen. My days are loud and hot — I need my beach time quiet.",["Fermentation timelines, regional olive oils, and people who eat with their hands."],187,false,"photo-adriana"],
    ["Paloma Diaz",25,"Tulum, Mexico",200,"Jewelry designer. Everything I make starts with something I found on the beach.",["Get lost in a market, buy something we don't need, and eat street food until we can't move."],252,false,"photo-paloma"],
    ["Suki Nakamura",26,"Venice Beach, CA",200,"Content strategist who clocks out at 5 and is on the sand by 5:15.",["Golden hour at the beach, then ramen at the place with no sign."],238,false,"photo-suki"],
    ["Kiana Reyes",25,"North Shore, Oahu",200,"Surf school owner. Born in the water, raised by the tide.",["Any beach, any island, as long as I can hear the waves while I eat."],266,false,"photo-kiana"],
    ["Simone Hart",28,"Turks and Caicos",200,"Former pro swimmer, current water-sports instructor.",["Swimming in open water, reading people, and making fish tacos from scratch."],122,false,"photo-simone"],
    ["Ava Sinclair",27,"Martha's Vineyard, MA",200,"Music journalist. I interview people for a living, so expect good questions and zero awkward silence.",["Skip the small talk — tell me the thing you never tell people on the first date."],202,false,"photo-ava"],
    ["Kai Williams",29,"Outer Banks, North Carolina",200,"Fitness coach and beach volleyball captain. My laugh carries, my standards are higher.",["Show up with energy. Match mine. Don't try to dim it."],302,false,"photo-kai"],
  ].map(([name, age, city, bid, bio, ice, hue, verified, photo]) => ({
    id: uid(), name, age, city, startingBid: bid, bio, icebreakers: ice, hue, verified, photo: "photos/" + photo + ".jpg"
  })));

  // ---- state ----
  const KEY = "auctionbaby.web.v1";
  let S = load();
  function load() {
    try { return JSON.parse(localStorage.getItem(KEY)) || fresh(); }
    catch { return fresh(); }
  }
  function fresh() {
    return { registered: false, role: null, me: { name: "", age: 27, city: "" },
             wallet: 750, floor: [], matches: [], incoming: [], seenSplash: false };
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
    if (h === "you") { tab = "you"; return you(); }
    tab = "floor"; return S.role === "woman" ? incoming() : floor();
  }

  function onboarding() {
    const roleCard = (k, title, sub) =>
      `<button class="card" style="text-align:left;width:100%;margin-bottom:10px;${S.role === k ? "border-color:var(--gold)" : ""}" data-role="${k}">
         <div class="row"><div class="grow"><div style="font-family:var(--serif);font-weight:800;font-size:18px">${title}</div>
         <div class="faint">${sub}</div></div><div class="pill">${S.role === k ? "Selected" : "Pick"}</div></div></button>`;
    app.innerHTML = `<div class="screen">
      <div style="text-align:center;margin:18px 0 20px">
        <div class="kicker">Auction Baby</div>
        <h1 class="display" style="margin-top:8px">Bid what a<br>date is worth.</h1>
        <div class="faint" style="margin-top:10px">Find a high-value match — and set the night up right.</div>
      </div>
      <div class="kicker" style="margin:6px 0 8px">Your side of the floor</div>
      ${roleCard("man", "I'm bidding", "Browse the floor and place bids on dates.")}
      ${roleCard("woman", "I'm a lot", "Field bids; accept the one you like.")}
      <div class="card" style="margin-top:12px">
        <label class="field"><div class="lbl">Name</div><input class="txt" id="ob-name" placeholder="Your name" value="${esc(S.me.name)}"></label>
        <label class="field"><div class="lbl">Age</div><input class="txt" id="ob-age" type="number" min="18" value="${S.me.age}"></label>
        <label class="field"><div class="lbl">City</div><input class="txt" id="ob-city" placeholder="Where you're based" value="${esc(S.me.city)}"></label>
      </div>
      ${APPLE_ON() ? `<button class="btn ghost" id="ob-apple" style="margin-top:12px"> Sign in with Apple</button>
        <div class="faint" style="text-align:center;margin-top:6px">Optional — keeps your account across devices.</div>` : ""}
      <button class="btn" id="ob-go" style="margin-top:16px">Step onto the floor</button>
      <div class="disclosure">A bid is the budget you commit to spend on the date itself — dinner, drinks, the evening. It is never a payment to another person.</div>
    </div>`;
    app.querySelectorAll("[data-role]").forEach(b => b.onclick = () => { S.role = b.dataset.role; save(); onboarding(); });
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
      const name = $("#ob-name").value.trim(), age = +$("#ob-age").value || 0;
      if (!S.role) return toast("Pick a side first.");
      if (!name) return toast("Add your name.");
      if (age < 18) return toast("You must be 18 or older.");
      S.me = { name, age, city: $("#ob-city").value.trim() };
      if (CONFIGURED() && SIGNED_IN()) {
        try { await API.saveProfile({ name, location: S.me.city, role: S.role }); } catch (e) { /* non-fatal */ }
      }
      if (S.role === "woman" && !CONFIGURED() && !(S.incoming && S.incoming.length)) S.incoming = seedIncoming();
      S.registered = true; save(); go("/floor"); syncFloor(); syncMatches(); syncIncoming();
    };
  }

  function floor() {
    const [hero, ...rest] = S.floor;
    const tickers = ["Marcus B. was outbid on Nova Ray — rebid incoming", "3 bidders are watching Mara Quinn", "A Vault of Gavels was just claimed"];
    const tick = tickers[Math.floor(Date.now() / 6000) % tickers.length];
    const lotCard = (w, isHero) => `
      <button class="lot ${isHero ? "hero" : ""}" data-lot="${w.id}" style="width:100%;padding:0;text-align:left;background:none">
        <div class="art">${grad(w.hue, w.name, w.photo)}</div>
        ${isHero ? `<div class="lotofday">⚖ Lot of the day</div>` : ""}
        <div class="meta">
          <div class="name">${esc(w.name)} <span class="muted" style="font-size:18px">${w.age}</span> ${w.verified ? "✔" : ""}</div>
          <div class="tags"><span class="chip">${esc(w.city)}</span><span class="chip on">${money(w.startingBid)} floor</span></div>
        </div>
      </button>`;
    app.innerHTML = `<div class="screen">
      <div class="topbar"><h1 class="display" style="font-size:30px">The Floor</h1>
        <span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      <div class="faint" style="margin:-6px 0 12px">Bid what a date is worth. She unlocks your photo when she accepts.</div>
      <div class="ticker"><span class="dot"></span><span class="live">LIVE</span><span class="grow">${esc(tick)}</span></div>
      ${lotCard(hero, true)}
      ${rest.map(w => lotCard(w, false)).join("")}
    </div>${tabbar()}`;
    wire();
  }

  function lotDetail(id) {
    const w = S.floor.find(x => x.id === id); if (!w) return go("/floor");
    app.innerHTML = `<div class="screen">
      <div class="topbar"><button class="chip" data-back>‹ Floor</button><span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      <div class="lot" style="margin-bottom:16px"><div class="art">${grad(w.hue, w.name, w.photo)}</div>
        <div class="meta"><div class="name">${esc(w.name)} <span class="muted" style="font-size:18px">${w.age}</span> ${w.verified ? "✔" : ""}</div>
        <div class="tags"><span class="chip">${esc(w.city)}</span><span class="chip on">${money(w.startingBid)} floor</span></div></div></div>
      <div class="card"><div class="kicker">About</div><p class="muted" style="margin:8px 0 0">${esc(w.bio)}</p></div>
      ${w.icebreakers.map(q => `<div class="card" style="margin-top:10px"><div class="faint">Prompt</div><div style="font-family:var(--serif);font-weight:700;margin-top:4px">${esc(q)}</div></div>`).join("")}
      <button class="btn" data-bid="${w.id}" style="margin-top:18px">Place a bid</button>
    </div>`;
    app.querySelector("[data-back]").onclick = () => go("/floor");
    app.querySelector("[data-bid]").onclick = () => bidSheet(w);
  }

  function bidSheet(w) {
    let amount = w.startingBid;
    const sheet = document.createElement("div"); sheet.className = "sheet";
    const draw = () => sheet.innerHTML = `<div class="panel">
      <div class="grab"></div>
      <div class="row" style="margin-bottom:8px">${gradSm(w.hue, w.name)}<div class="grow"><div style="font-family:var(--serif);font-weight:800;font-size:18px">Bidding on ${esc(w.name)}</div><div class="faint">Floor ${money(w.startingBid)}</div></div></div>
      <div class="kicker" style="text-align:center;margin-top:14px">Your bid</div>
      <div class="amount">${money(amount)}</div>
      <div class="row" style="flex-wrap:wrap;justify-content:center;gap:8px;margin:12px 0">
        ${[50, 100, 1000, 10000].map(a => `<button class="chip" data-add="${a}">+${money(a)}</button>`).join("")}
        <button class="chip" data-reset>Reset</button>
      </div>
      <label class="field"><div class="lbl">Add a note</div><textarea class="txt" id="bid-note" placeholder="Why you? Make the bid count."></textarea></label>
      <button class="btn" id="bid-place">Place ${money(amount)} bid</button>
      <div class="disclosure">This is the budget you'll spend on the date — the meal, the drinks, the night. She keeps the receipts. The app never transfers money between users.</div>
    </div>`;
    draw();
    sheet.onclick = e => { if (e.target === sheet) sheet.remove(); };
    sheet.addEventListener("click", e => {
      const add = e.target.closest("[data-add]"); if (add) { amount += +add.dataset.add; draw(); }
      if (e.target.closest("[data-reset]")) { amount = w.startingBid; draw(); }
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
    // demo: she accepts → match + opener
    const accepted = true;
    if (!accepted) return toast(`${w.name} passed. Bid stronger next time.`);
    const m = { id: uid(), lotId: w.id, name: w.name, hue: w.hue, amount,
                note: note || "",
                messages: [{ me: false, text: w.icebreakers[0] || "You win — where are you taking me?" }] };
    S.matches.unshift(m); save(); celebrate(w, amount, m);
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

  function store() {
    const packs = [["Handful", 1000, 4.99], ["Stack", 5000, 19.99], ["Chest", 14000, 49.99], ["Vault", 30000, 99.99]];
    const passes = [["Paddle", 19.99, "Unlimited bids · see if you're top bid · 1 Boost/week"],
                    ["Reserve", 39.99, "+ reveal reserve · auto-rebid · filters · rewind"],
                    ["Black Card", 99.99, "+ priority placement · read receipts"]];
    app.innerHTML = `<div class="screen">
      <div class="topbar"><h1 class="display" style="font-size:28px">Store</h1><span class="pill">⚖ ${S.wallet.toLocaleString()}</span></div>
      <div class="kicker" style="margin:8px 0">Top up Gavels</div>
      ${packs.map(([n, g, p], i) => `<div class="card row" style="margin-bottom:10px"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">${g.toLocaleString()} Gavels ${i === packs.length - 1 ? '<span class="pill">BEST VALUE</span>' : ""}</div>
        <div class="faint">${n} of Gavels</div></div><button class="chip on" data-buy="${g}" data-price="${p}">$${p}</button></div>`).join("")}
      <div class="kicker" style="margin:16px 0 8px">Auction Baby Pass</div>
      ${passes.map(([n, p, b]) => `<div class="card" style="margin-bottom:10px"><div class="row"><div class="grow">
        <div style="font-family:var(--serif);font-weight:800">${n} <span class="muted">· $${p}/mo</span></div>
        <div class="faint">${b}</div></div><button class="chip rose" data-sub="${n}">Subscribe</button></div></div>`).join("")}
      <div class="disclosure">Payments on the web are processed by Stripe. Gavels are in-app status currency and are never a payment to another user.</div>
    </div>${tabbar()}`;
    app.querySelectorAll("[data-buy]").forEach(b => b.onclick = () => checkout("gavels", +b.dataset.buy, +b.dataset.price));
    app.querySelectorAll("[data-sub]").forEach(b => b.onclick = () => checkout("pass", b.dataset.sub));
    wire();
  }

  function checkout(kind, a, price) {
    // LIVE: redirect to Stripe Checkout via the consumables Worker.
    if (kind === "gavels" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      const packId = GAVEL_PACK_ID[a] || String(a);
      API.me()
        .then(u => API.buyGavels(packId, u.id || u.userId))   // → redirects to Stripe
        .catch(e => toast("Checkout: " + e.message));
      return;
    }
    // LIVE: recurring Pass via Stripe Billing.
    if (kind === "pass" && CONFIGURED() && SIGNED_IN() && window.AB_CONFIG.CONSUMABLES_URL) {
      const passId = PASS_ID[a] || a;
      API.me().then(u => API.subscribe(passId, u.id || u.userId)).catch(e => toast("Subscribe: " + e.message));
      return;
    }
    // DEMO fallback (no charge).
    if (kind === "gavels") { S.wallet += a; save(); toast(`Demo: +${a.toLocaleString()} Gavels (configure Stripe for live).`); store(); }
    else toast(`Demo: ${a} Pass active (configure Stripe for live).`);
  }

  function you() {
    app.innerHTML = `<div class="screen">
      <div class="card" style="text-align:center;padding:24px">
        <div style="width:96px;margin:0 auto 12px">${grad(210, S.me.name || "You", S.me.photo)}</div>
        <div style="font-family:var(--serif);font-weight:800;font-size:22px">${esc(S.me.name || "You")} <span class="muted">${S.me.age}</span></div>
        <div class="faint">${esc(S.me.city || "")} · ${S.role === "man" ? "Bidder" : "Lot"}</div>
        <div class="pill" style="margin-top:12px">⚖ ${S.wallet.toLocaleString()} Gavels</div>
      </div>
      <button class="btn ghost" id="addphoto" style="margin-top:14px">${S.me.photo ? "Change photo" : "Add a photo"}</button>
      <button class="btn ghost" data-tab="store" style="margin-top:10px">Open the Store</button>
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
      API.signOutLocal(); S = fresh(); S.floor = seedFloor(); save(); toast("Account deleted."); go("/"); onboarding();
    };
    $("#reset").onclick = () => { if (confirm("Reset everything?")) { S = fresh(); S.floor = seedFloor(); save(); go("/"); onboarding(); } };
    wire();
  }

  // ---- shared wiring for lists/tabs ----
  function wire() {
    app.querySelectorAll("[data-lot]").forEach(b => b.onclick = () => go("/lot/" + b.dataset.lot));
    app.querySelectorAll("[data-chat]").forEach(b => b.onclick = () => go("/chat/" + b.dataset.chat));
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
