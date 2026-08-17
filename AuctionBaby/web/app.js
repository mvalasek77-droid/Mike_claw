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

  // ---- theme helper: a deterministic gradient avatar from a hue ----
  const grad = (hue, name) => {
    const a = `hsl(${hue} 55% 42%)`, b = `hsl(${(hue + 40) % 360} 60% 24%)`;
    const initials = (name || "?").split(" ").map(w => w[0]).slice(0, 2).join("").toUpperCase();
    return `<div class="avatar" style="background:linear-gradient(140deg,${a},${b})">${initials}</div>`;
  };
  const gradSm = (hue, name) => grad(hue, name).replace('class="avatar"', 'class="avatar sm"');

  // ---- demo floor (fictional; gradient avatars, no real photos) ----
  const seedFloor = () => ([
    ["Serena Voss", 28, "Upper East Side, New York", 300, "Private art dealer. Quiet dinners, old buildings, men who don't explain their watch.", ["Know what you want and don't apologize for it.", "Close a gallery, open the good wine."], 285, false],
    ["Mara Quinn", 27, "SoHo, New York", 250, "Gallery curator. Openings on weekends, art books I swear I'll stop buying.", ["Make the reservation and don't cancel it."], 320, false],
    ["Priya Sethi", 29, "Lincoln Park, Chicago", 300, "ER doctor. My schedule is chaos, so when I'm off, I'm present.", ["Calls his mom. Tips well. Asks follow-up questions."], 40, false],
    ["Sloane Carter", 31, "Venice, Los Angeles", 500, "Founder, second company. Early mornings, good espresso, people who follow through.", ["Skip the small talk and split the tasting menu."], 200, false],
    ["Noor Haddad", 26, "Capitol Hill, Seattle", 200, "Climate engineer. I'll hike in any weather and I fact-check fun facts, lovingly.", ["Best trip of my life started with getting weathered in."], 150, false],
    ["Valentina Cruz", 28, "Williamsburg, Brooklyn", 260, "Pastry chef. I work Saturdays, so impress me on a Tuesday.", ["Cooking for people, then watching the first bite."], 15, false],
    ["Jade Rivera", 25, "Tulum", 220, "Yoga teacher between Tulum and the next retreat. Sunrise person, unapologetically.", ["Meet me where the day starts."], 95, false],
    ["Amber Skye", 24, "Miami Beach", 240, "Boat weekends and a standing rooftop reservation. Come keep up.", ["Sunset drinks over the water. You handle the details."], 350, false],
  ].map(([name, age, city, bid, bio, ice, hue, verified]) => ({
    id: uid(), name, age, city, startingBid: bid, bio, icebreakers: ice, hue, verified
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
             wallet: 750, floor: [], matches: [], seenSplash: false };
  }
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
  const tabbar = () => `
    <div class="tabbar">
      ${[["floor", "▦", "Floor"], ["matches", "❤", "Matches"], ["store", "⚖", "Store"], ["you", "◉", "You"]]
        .map(([k, ic, l]) => `<button data-tab="${k}" class="${tab === k ? "on" : ""}"><span class="ic">${ic}</span>${l}</button>`).join("")}
    </div>`;

  // ================= SCREENS =================
  function render() {
    const h = location.hash.replace(/^#\/?/, "");
    if (!S.registered) return onboarding();
    if (h.startsWith("lot/")) return lotDetail(h.split("/")[1]);
    if (h.startsWith("chat/")) return chat(h.split("/")[1]);
    if (h === "matches") { tab = "matches"; return matches(); }
    if (h === "store") { tab = "store"; return store(); }
    if (h === "you") { tab = "you"; return you(); }
    tab = "floor"; return floor();
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
      <button class="btn" id="ob-go" style="margin-top:16px">Step onto the floor</button>
      <div class="disclosure">A bid is the budget you commit to spend on the date itself — dinner, drinks, the evening. It is never a payment to another person.</div>
    </div>`;
    app.querySelectorAll("[data-role]").forEach(b => b.onclick = () => { S.role = b.dataset.role; save(); onboarding(); });
    $("#ob-go").onclick = () => {
      const name = $("#ob-name").value.trim(), age = +$("#ob-age").value || 0;
      if (!S.role) return toast("Pick a side first.");
      if (!name) return toast("Add your name.");
      if (age < 18) return toast("You must be 18 or older.");
      S.me = { name, age, city: $("#ob-city").value.trim() };
      S.registered = true; save(); go("/floor");
    };
  }

  function floor() {
    const [hero, ...rest] = S.floor;
    const tickers = ["Marcus B. was outbid on Nova Ray — rebid incoming", "3 bidders are watching Mara Quinn", "A Vault of Gavels was just claimed"];
    const tick = tickers[Math.floor(Date.now() / 6000) % tickers.length];
    const lotCard = (w, isHero) => `
      <button class="lot ${isHero ? "hero" : ""}" data-lot="${w.id}" style="width:100%;padding:0;text-align:left;background:none">
        <div class="art">${grad(w.hue, w.name)}</div>
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
      <div class="lot" style="margin-bottom:16px"><div class="art">${grad(w.hue, w.name)}</div>
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
      if (e.target.closest("#bid-place")) { sheet.remove(); placeBid(w, amount); }
    });
    document.body.appendChild(sheet);
  }

  function placeBid(w, amount) {
    // simulated: she accepts → match + opener
    const accepted = true;
    if (!accepted) return toast(`${w.name} passed. Bid stronger next time.`);
    const m = { id: uid(), lotId: w.id, name: w.name, hue: w.hue, amount,
                messages: [{ me: false, text: w.icebreakers[0] || "You win — where are you taking me?" }] };
    S.matches.unshift(m); save();
    celebrate(w, amount, m);
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

  function matches() {
    app.innerHTML = `<div class="screen">
      <h1 class="display" style="font-size:30px;margin-bottom:14px">Matches</h1>
      ${S.matches.length ? S.matches.map(m => {
        const last = m.messages[m.messages.length - 1];
        return `<button class="card row" data-chat="${m.id}" style="width:100%;text-align:left;margin-bottom:10px">
          ${gradSm(m.hue, m.name)}<div class="grow"><div style="font-family:var(--serif);font-weight:800">${esc(m.name)}</div>
          <div class="faint" style="white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${esc(last ? last.text : "Say hello")}</div></div>
          <span class="pill">${money(m.amount)}</span></button>`;
      }).join("") : `<div class="card muted">No matches yet. Win a bid on the floor.</div>`}
    </div>${tabbar()}`;
    wire();
  }

  function chat(id) {
    const m = S.matches.find(x => x.id === id); if (!m) return go("/matches");
    const bubbles = m.messages.map(msg =>
      `<div class="bub ${msg.sys ? "sys" : msg.me ? "me" : "them"}">${esc(msg.text)}</div>`).join("");
    app.innerHTML = `<div class="screen" style="padding-bottom:0">
      <div class="topbar"><button class="chip" data-back>‹</button>
        <div class="row">${gradSm(m.hue, m.name)}<b style="font-family:var(--serif)">${esc(m.name)}</b></div><span></span></div>
      <div class="msgs" id="msgs">${bubbles}</div></div>
      <div class="composer"><input id="ci" placeholder="Message…" autocomplete="off">
        <button class="iconbtn" id="send">↑</button></div>`;
    app.querySelector("[data-back]").onclick = () => go("/matches");
    const scroll = () => { const e = $("#msgs"); e.scrollTop = e.scrollHeight; };
    scroll();
    const send = () => {
      const i = $("#ci"), t = i.value.trim(); if (!t) return;
      m.messages.push({ me: true, text: t }); i.value = ""; save(); chat(id);
      setTimeout(() => {
        const replies = ["So where are you taking me?", "Bold. I like it.", "Prove it — pick the place.", "You had me at the bid.", "Friday, then?"];
        m.messages.push({ me: false, text: replies[Math.floor(Math.random() * replies.length)] });
        save(); if (location.hash.includes("chat/" + id)) chat(id);
      }, 900 + Math.random() * 900);
    };
    $("#send").onclick = send;
    $("#ci").addEventListener("keydown", e => { if (e.key === "Enter") send(); });
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
    // Placeholder for Stripe Checkout (the consumables Worker already speaks Stripe).
    if (kind === "gavels") { S.wallet += a; save(); toast(`Demo: +${a.toLocaleString()} Gavels (wire Stripe for live).`); store(); }
    else toast(`Demo: ${a} Pass active (wire Stripe for live).`);
  }

  function you() {
    app.innerHTML = `<div class="screen">
      <div class="card" style="text-align:center;padding:24px">
        <div style="width:96px;margin:0 auto 12px">${grad(210, S.me.name || "You")}</div>
        <div style="font-family:var(--serif);font-weight:800;font-size:22px">${esc(S.me.name || "You")} <span class="muted">${S.me.age}</span></div>
        <div class="faint">${esc(S.me.city || "")} · ${S.role === "man" ? "Bidder" : "Lot"}</div>
        <div class="pill" style="margin-top:12px">⚖ ${S.wallet.toLocaleString()} Gavels</div>
      </div>
      <button class="btn ghost" data-tab="store" style="margin-top:14px">Open the Store</button>
      <button class="btn ghost" id="reset" style="margin-top:10px;color:var(--danger)">Reset account</button>
      <div class="disclosure">Auction Baby — web. A bid is a promise to spend on the date, never a payment to another person.</div>
    </div>${tabbar()}`;
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
})();
