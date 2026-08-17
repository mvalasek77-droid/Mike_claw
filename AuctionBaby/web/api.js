/* Auction Baby web — API client for the existing Cloudflare Workers.
   Session token lives in localStorage. Every method throws on non-2xx so the
   caller can fall back to demo mode. */
(() => {
  "use strict";
  const C = window.AB_CONFIG || {};
  const TKEY = "auctionbaby.web.session";
  const token = () => localStorage.getItem(TKEY) || "";
  const setToken = t => t ? localStorage.setItem(TKEY, t) : localStorage.removeItem(TKEY);

  async function call(base, path, { method = "GET", body, auth = true } = {}) {
    if (!base) throw new Error("backend not configured");
    const headers = { "Content-Type": "application/json" };
    if (auth && token()) headers.Authorization = "Bearer " + token();
    const res = await fetch(base.replace(/\/$/, "") + path, {
      method, headers, body: body != null ? JSON.stringify(body) : undefined,
    });
    const text = await res.text();
    const data = text ? JSON.parse(text) : {};
    if (!res.ok) throw new Error(data.error || ("HTTP " + res.status));
    return data;
  }
  const auth = (p, o) => call(C.AUTH_URL, p, o);
  const match = (p, o) => call(C.MATCHING_URL, p, o);
  const shop = (p, o) => call(C.CONSUMABLES_URL, p, o);

  window.AB_API = {
    // ── session ──
    hasSession: () => !!token(),
    signOutLocal: () => setToken(""),

    // ── auth: Sign in with Apple for the Web ──
    // Loads Apple's JS SDK, runs the popup, exchanges the id_token for a
    // Worker session token. Requires APPLE_SERVICE_ID + APPLE_REDIRECT_URI and
    // WEB_CLIENT_ID set on the auth Worker.
    async signInWithApple() {
      if (!C.APPLE_SERVICE_ID) throw new Error("Apple Sign-in not configured");
      await loadAppleJS();
      window.AppleID.auth.init({
        clientId: C.APPLE_SERVICE_ID, scope: "name email",
        redirectURI: C.APPLE_REDIRECT_URI, usePopup: true,
      });
      const r = await window.AppleID.auth.signIn(); // { authorization:{id_token,...}, user? }
      const identityToken = r.authorization && r.authorization.id_token;
      const fullName = r.user && r.user.name
        ? [r.user.name.firstName, r.user.name.lastName].filter(Boolean).join(" ") : null;
      const data = await auth("/auth/apple", {
        method: "POST", auth: false,
        body: { identityToken, fullName },
      });
      if (data.token) setToken(data.token);
      return data; // { token, user }
    },
    me: () => auth("/me"),
    async saveProfile(p) { return auth("/me/profile", { method: "PUT", body: p }); },
    async setDob(dob) { return auth("/me/dob", { method: "POST", body: { dob } }); },
    deleteAccount: () => auth("/me", { method: "DELETE" }),

    // ── floor ──
    floor: (location) => auth("/users/floor" + (location ? "?location=" + encodeURIComponent(location) : "")),

    // ── bids / matches / messages (matching Worker) ──
    placeBid: (lotId, amount, note) => match("/bids", { method: "POST", body: { lotId, amount, note } }),
    outgoingBids: () => match("/bids/outgoing"),
    incomingBids: () => match("/bids/incoming"),
    acceptBid: (id) => match(`/bids/${id}/accept`, { method: "POST" }),
    declineBid: (id) => match(`/bids/${id}/decline`, { method: "POST" }),
    matches: () => match("/matches"),
    matchDetail: (id) => match(`/matches/${id}`),
    sendMessage: (id, text) => match(`/matches/${id}/messages`, { method: "POST", body: { text } }),
    markSeen: (id) => match(`/matches/${id}/mark-seen`, { method: "POST" }),

    // ── payments (Stripe via consumables Worker) ──
    // Redirects the browser to Stripe Checkout for a Gavel pack.
    async buyGavels(packId, userId) {
      const data = await shop("/checkout", {
        method: "POST",
        body: { packId, userId,
                successUrl: C.CHECKOUT_SUCCESS_URL || location.href,
                cancelUrl: C.CHECKOUT_CANCEL_URL || location.href },
      });
      if (data.url) location.href = data.url;
      return data;
    },
    balance: () => shop("/balance"),
    catalog: () => shop("/catalog"),
  };

  function loadAppleJS() {
    return new Promise((resolve, reject) => {
      if (window.AppleID) return resolve();
      const s = document.createElement("script");
      s.src = "https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js";
      s.onload = resolve; s.onerror = () => reject(new Error("Apple JS failed to load"));
      document.head.appendChild(s);
    });
  }
})();
