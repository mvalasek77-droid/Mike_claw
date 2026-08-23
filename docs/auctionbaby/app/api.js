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
  // shop() calls don't need auth — checkout/status endpoints are public in the
  // Worker (they only create Stripe sessions, no balance mutation). Balance and
  // consume endpoints still require the shared secret (iOS-only).
  const shop = (p, o) => call(C.CONSUMABLES_URL, p, { auth: false, ...o });

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
    // Dev-only: create/login with a synthetic user (no Apple Sign-In needed).
    async devLogin(name) {
      const data = await auth("/auth/dev-login", {
        method: "POST", auth: false,
        body: { name },
      });
      if (data.sessionToken) setToken(data.sessionToken);
      return data; // { userId, sessionToken, isNew, user }
    },
    me: () => auth("/me"),
    // Upload a profile photo to the auth Worker → R2 (or data URL fallback).
    async uploadPhoto(blob) {
      const ct = (blob && blob.type) ? blob.type : "image/jpeg";
      const res = await fetch((C.AUTH_URL || "").replace(/\/$/, "") + "/me/photos", {
        method: "POST",
        headers: { "Content-Type": ct, Authorization: "Bearer " + token() },
        body: blob,
      });
      const t = await res.text();
      const d = t ? JSON.parse(t) : {};
      if (!res.ok) throw new Error(d.error || ("HTTP " + res.status));
      return d; // { photo: { id, url }, ... } (shape may vary)
    },
    myProfile: () => auth("/me/profile"),
    async saveProfile(p) { return auth("/me/profile", { method: "PUT", body: p }); },
    async setDob(dob) { return auth("/me/dob", { method: "POST", body: { dateOfBirth: dob } }); },
    deleteAccount: () => auth("/me", { method: "DELETE" }),

    // ── floor ──
    floor: (role, location) => {
      const params = ["role=" + encodeURIComponent(role || "woman")];
      if (location) params.push("location=" + encodeURIComponent(location));
      return auth("/users/floor?" + params.join("&"));
    },

    // ── bids / matches / messages (matching Worker) ──
    placeBid: (lotId, amount, note, opts) => match("/bids", { method: "POST", body: { lotId, amount, note, ...opts } }),
    outgoingBids: () => match("/bids/outgoing"),
    incomingBids: () => match("/bids/incoming"),
    acceptBid: (id) => match(`/bids/${id}/accept`, { method: "POST" }),
    declineBid: (id) => match(`/bids/${id}/decline`, { method: "POST" }),
    matches: () => match("/matches"),
    matchDetail: (id) => match(`/matches/${id}`),
    sendMessage: (id, text, photo) => match(`/matches/${id}/messages`, { method: "POST", body: photo ? { text: text || "", photo } : { text } }),
    markSeen: (id) => match(`/matches/${id}/mark-seen`, { method: "POST" }),

    // ── safety ──
    blockUser: (userId, reason) => auth("/me/blocks", { method: "POST", body: { userId, reason } }),
    reportUser: (userId, reason, context) => auth("/me/reports", { method: "POST", body: { userId, reason, context } }),
    react: (matchId, messageId, emoji) => match(`/matches/${matchId}/messages/${messageId}/react`, { method: "POST", body: { emoji } }),

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

    // ── reserve the date (Stripe booking fee via consumables Worker) ──
    reserveInfo: () => shop("/reserve/info", { auth: false }),
    reserveStatus: (matchId) => shop("/reserve/status?matchId=" + encodeURIComponent(matchId)),
    async reserveDate(matchId, amountCents) {
      const data = await shop("/reserve/checkout", {
        method: "POST",
        body: { matchId, amountCents,
                successUrl: C.CHECKOUT_SUCCESS_URL || location.href,
                cancelUrl: C.CHECKOUT_CANCEL_URL || location.href },
      });
      if (data.url && data.url !== "about:blank") location.href = data.url;
      return data;
    },

    // ── Web Push (VAPID) ──
    // Subscribe the browser and register the subscription with the auth Worker.
    async enableWebPush() {
      if (!C.VAPID_PUBLIC_KEY) throw new Error("Web Push not configured");
      if (!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error("Push unsupported");
      const perm = await Notification.requestPermission();
      if (perm !== "granted") throw new Error("Permission denied");
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64ToUint8(C.VAPID_PUBLIC_KEY),
      });
      await auth("/devices/register-web", { method: "POST", body: { subscription: sub.toJSON() } });
      return true;
    },

    // Recurring Auction Baby Pass via Stripe Billing → redirect to Checkout.
    async subscribe(passId, userId) {
      const data = await shop("/subscribe", {
        method: "POST",
        body: { passId, userId,
                successUrl: C.CHECKOUT_SUCCESS_URL || location.href,
                cancelUrl: C.CHECKOUT_CANCEL_URL || location.href },
      });
      if (data.url) location.href = data.url;
      return data;
    },
    subscriptionStatus: (userId) => shop("/subscription?userId=" + encodeURIComponent(userId)),

    // ── Spotlight Boost (one-time Stripe Checkout) ──
    async buyBoost(userId) {
      const data = await shop("/boost/checkout", {
        method: "POST",
        body: { userId,
                successUrl: C.CHECKOUT_SUCCESS_URL || location.href,
                cancelUrl: C.CHECKOUT_CANCEL_URL || location.href },
      });
      if (data.url) location.href = data.url;
      return data;
    },
    boostStatus: (userId) => shop("/boost/status?userId=" + encodeURIComponent(userId)),

    // ── Status Archetypes (one-time Stripe Checkout, owned forever) ──
    async buyStatus(statusId, userId) {
      const data = await shop("/status/checkout", {
        method: "POST",
        body: { statusId, userId,
                successUrl: C.CHECKOUT_SUCCESS_URL || location.href,
                cancelUrl: C.CHECKOUT_CANCEL_URL || location.href },
      });
      if (data.url) location.href = data.url;
      return data;
    },
    statusOwned: (userId) => shop("/status/owned?userId=" + encodeURIComponent(userId)),

    // ── Verification (face match + liveness via auth Worker) ──
    verifyStart: () => auth("/verify/start", { method: "POST", body: {} }),
    verifySubmit: (selfieScore, livenessPassed, faceMatchScore) =>
      auth("/verify/submit", { method: "POST", body: { selfieScore, livenessPassed, faceMatchScore } }),

    // ── Bug reports ──
    submitBug: (description, steps, severity, device) => auth("/me/bugs", { method: "POST", body: { description, steps, severity, device } }),

    // ── Admin (auth Worker — requires is_admin session) ──
    adminStats: () => auth("/admin/stats"),
    adminUsers: () => auth("/admin/users"),
    adminUnverify: (id) => auth(`/admin/users/${id}/unverify`, { method: "POST" }),
    adminSuspend: (id, days) => auth(`/admin/users/${id}/suspend`, { method: "POST", body: { days } }),
    adminUnsuspend: (id) => auth(`/admin/users/${id}/unsuspend`, { method: "POST" }),
    adminDelete: (id) => auth(`/admin/users/${id}`, { method: "DELETE" }),
    adminReports: (status) => auth("/admin/reports" + (status ? "?status=" + encodeURIComponent(status) : "")),
    adminResolve: (id, disposition, note) => auth(`/admin/reports/${id}/resolve`, { method: "POST", body: { disposition, note } }),
    adminBugs: (status) => auth("/admin/bugs" + (status ? "?status=" + encodeURIComponent(status) : "")),
    adminCloseBug: (id) => auth(`/admin/bugs/${id}/close`, { method: "POST" }),
    adminAudit: () => auth("/admin/audit"),
  };

  function urlB64ToUint8(base64) {
    const pad = "=".repeat((4 - (base64.length % 4)) % 4);
    const b64 = (base64 + pad).replace(/-/g, "+").replace(/_/g, "/");
    const raw = atob(b64);
    return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
  }

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
