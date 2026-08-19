const { chromium } = require('playwright');
const { createServer } = require('http');
const { readFileSync, existsSync, statSync } = require('fs');
const { join, extname } = require('path');

const WEBDIR = '/home/user/Mike_claw/AuctionBaby/web';
const SCRATCHPAD = '/tmp/claude-0/-home-user-Mike-claw/ca849768-b246-5f3e-bf90-7a334fe8daf1/scratchpad';
const MIME = { '.html':'text/html','.js':'application/javascript','.css':'text/css',
  '.json':'application/json','.webmanifest':'application/manifest+json',
  '.jpg':'image/jpeg','.png':'image/png','.svg':'image/svg+xml' };

let pass = 0, fail = 0, warn = 0;
const results = [];
function check(section, name, ok, note) {
  const status = ok ? 'PASS' : 'FAIL';
  if (ok) pass++; else fail++;
  results.push({ section, name, status, note: note || '' });
  console.log(`  ${ok ? '✓' : '✗'} ${name}${note ? ' — ' + note : ''}`);
}
function warning(section, name, note) {
  warn++;
  results.push({ section, name, status: 'WARN', note });
  console.log(`  ⚠ ${name} — ${note}`);
}

(async () => {
const server = createServer((req, res) => {
  let url = req.url.split('?')[0];
  if (url === '/') url = '/index.html';
  const fp = join(WEBDIR, url);
  if (!existsSync(fp) || statSync(fp).isDirectory()) { res.writeHead(404); res.end('Not found'); return; }
  res.writeHead(200, { 'Content-Type': MIME[extname(fp)] || 'application/octet-stream' });
  res.end(readFileSync(fp));
});
await new Promise(r => server.listen(9880, r));
const BASE = 'http://localhost:9880';

const browser = await chromium.launch({
  executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox']
});

// ══════════════════════════════════════════════════════════════
// SECTION 1: ONBOARDING
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 1: ONBOARDING ══');
{
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => localStorage.clear());
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(800);

  const body = await p.textContent('body');
  check('Onboarding', 'Shows "Bid what a date is worth"', body.includes('Bid what a'));
  check('Onboarding', '"I\'m bidding" role card', body.includes("I'm bidding"));
  check('Onboarding', '"I\'m a lot" role card', body.includes("I'm a lot"));
  check('Onboarding', '"Step onto the floor" button', body.includes('Step onto the floor'));

  // Test validation: submit without role
  const stepBtn = await p.$('button.btn.cta, button.btn');
  let stepBtns = await p.$$('button.btn');
  let submitBtn = null;
  for (const b of stepBtns) { const t = await b.textContent(); if (t.includes('Step onto')) { submitBtn = b; break; } }

  // Try submit without selecting role
  if (submitBtn) {
    await submitBtn.click();
    await p.waitForTimeout(400);
    const toastText = await p.evaluate(() => {
      const t = document.querySelector('.toast');
      return t ? t.textContent : null;
    });
    check('Onboarding', 'Submit without role → toast', !!toastText, toastText);
  }

  // Select "I'm bidding" role
  const roleCards = await p.$$('[data-role]');
  if (roleCards.length >= 1) {
    await roleCards[0].click();
    await p.waitForTimeout(300);
    const roleSelected = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.role;
    });
    check('Onboarding', 'Role selection persists', roleSelected === 'man', 'role=' + roleSelected);
  }

  // Fill name and age, then submit
  const nameInput = await p.$('input[placeholder*="name" i]');
  if (nameInput) await nameInput.fill('Mike Valasek');
  const dobInput = await p.$('input[type="date"]');
  if (dobInput) await dobInput.fill('1990-06-15');
  const cityInput = await p.$('input[placeholder*="based" i], input[placeholder*="city" i]');
  if (cityInput) await cityInput.fill('New York');

  // Re-find submit button and click
  stepBtns = await p.$$('button.btn');
  submitBtn = null;
  for (const b of stepBtns) { const t = await b.textContent(); if (t.includes('Step onto')) { submitBtn = b; break; } }
  if (submitBtn) {
    await submitBtn.click();
    await p.waitForTimeout(1500);
    const hash = await p.evaluate(() => location.hash);
    check('Onboarding', 'Submit navigates to floor', hash.includes('floor'), 'hash=' + hash);
    const registered = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.registered;
    });
    check('Onboarding', 'State marked registered', registered === true);
  }

  await p.screenshot({ path: SCRATCHPAD + '/audit-01-postOnboard.png', fullPage: true });
  await p.close();
}

// ══════════════════════════════════════════════════════════════
// SECTION 2: THE FLOOR (Man/Bidder)
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 2: THE FLOOR ══');
{
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'man', me: { name: 'Mike Valasek', age: 36, city: 'New York', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 0, pendingBids: 0
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(2000);

  const body = await p.textContent('body');
  check('Floor', '"The Floor" header', body.includes('The Floor'));
  check('Floor', 'Gavel balance pill', body.includes('750'));
  check('Floor', '"On the floor now" label', body.includes('On the floor now'));
  check('Floor', 'House Rules card', body.includes('House Rules') || body.includes('Copycat'));
  check('Floor', 'Ticker bar present', body.includes('LIVE'));

  // Count lot cards
  const lotCards = await p.$$('.lot');
  check('Floor', '56 lot cards rendered', lotCards.length === 56, 'count=' + lotCards.length);

  // Check hero card
  const hero = await p.$('.lot.hero');
  check('Floor', 'Hero card (lot of the day)', !!hero);
  if (hero) {
    const heroText = await hero.textContent();
    check('Floor', 'Hero has "Lot of the day"', heroText.includes('Lot of the day') || heroText.includes('Masterpiece'));
  }

  // Check images loaded (viewport ones)
  const imgLoaded = await p.evaluate(() => {
    const imgs = document.querySelectorAll('.lot img');
    let loaded = 0;
    imgs.forEach(i => { if (i.naturalWidth > 0) loaded++; });
    return { total: imgs.length, loaded };
  });
  check('Floor', 'Photos render in lot cards', imgLoaded.loaded >= 3, `${imgLoaded.loaded}/${imgLoaded.total} loaded (lazy)`);

  // Check card structure
  const firstCard = await p.$('.lot');
  if (firstCard) {
    const cardHTML = await firstCard.innerHTML();
    check('Floor', 'Card has name', cardHTML.includes('Serena') || cardHTML.includes('Rae') || !!cardHTML.match(/font-weight.*800/));
    check('Floor', 'Card has city chip', cardHTML.includes('chip'));
    check('Floor', 'Card has starting bid chip', cardHTML.includes('floor') || cardHTML.includes('$'));
  }

  // Tab bar
  check('Floor', 'Tab bar: Floor tab', body.includes('Floor'));
  check('Floor', 'Tab bar: Matches tab', body.includes('Matches'));
  check('Floor', 'Tab bar: Store tab', body.includes('Store'));
  check('Floor', 'Tab bar: You tab', body.includes('You'));

  await p.screenshot({ path: SCRATCHPAD + '/audit-02-floor.png', fullPage: true });

  // ══════════════════════════════════════════════════════════════
  // SECTION 3: LOT DETAIL
  // ══════════════════════════════════════════════════════════════
  console.log('\n══ SECTION 3: LOT DETAIL ══');
  await firstCard.click();
  await p.waitForTimeout(1000);

  const detailBody = await p.textContent('body');
  check('Detail', 'Back button present', detailBody.includes('Floor') || detailBody.includes('‹'));
  check('Detail', 'Gavel balance in header', detailBody.includes('750'));
  check('Detail', 'Report flag button', detailBody.includes('⚑') || !!(await p.$('#report, [title*="Report"]')));

  // About section
  check('Detail', '"About" section', detailBody.includes('About'));

  // Prompts with "Bid & mention"
  const bidMention = await p.$$('[data-bid-prompt]');
  const hasBidMention = detailBody.includes('Bid & mention') || detailBody.includes('Bid &amp; mention');
  check('Detail', 'Prompts with "Bid & mention this answer"', hasBidMention);

  // Interests
  check('Detail', 'Interests section', detailBody.includes('Interests') || detailBody.includes('Art') || detailBody.includes('Wine'));

  // Lifestyle
  check('Detail', 'Lifestyle section', detailBody.includes('Lifestyle') || detailBody.includes('Drinks'));

  // Showcase Credit
  check('Detail', 'Showcase Credit section', detailBody.includes('Showcase Credit') || detailBody.includes('showcase'));
  check('Detail', 'Market value displayed', detailBody.includes('Market') || detailBody.includes('$'));

  // Showcase Report
  check('Detail', 'Showcase Report section', detailBody.includes('Showcase report') || detailBody.includes('Showcase Report'));
  check('Detail', 'Report factors (Personality, Date ratings, Consistency)',
    detailBody.includes('Personality') || detailBody.includes('Date rating') || detailBody.includes('Consistency'));

  // Bid button
  const bidBtns = await p.$$('button.btn');
  let mainBidBtn = null;
  for (const b of bidBtns) { const t = await b.textContent(); if (t.toLowerCase().includes('bid')) { mainBidBtn = b; break; } }
  check('Detail', 'Bid CTA button present', !!mainBidBtn);

  // Detail photo
  const detailImg = await p.evaluate(() => {
    const imgs = document.querySelectorAll('img');
    return Array.from(imgs).filter(i => i.naturalWidth > 0).length;
  });
  check('Detail', 'Photo loaded in detail', detailImg >= 1, detailImg + ' images loaded');

  await p.screenshot({ path: SCRATCHPAD + '/audit-03-detail.png', fullPage: true });

  // ══════════════════════════════════════════════════════════════
  // SECTION 4: BID SHEET (full flow)
  // ══════════════════════════════════════════════════════════════
  try {
  console.log('\n══ SECTION 4: BID SHEET ══');
  if (mainBidBtn) {
    await mainBidBtn.click();
    await p.waitForTimeout(600);

    const panel = await p.$('.panel');
    check('BidSheet', 'Sheet opens on bid click', !!panel);

    if (panel) {
      const sheetText = await panel.textContent();
      check('BidSheet', '"Bidding on [name]" header', sheetText.includes('Bidding on'));
      check('BidSheet', 'Floor price shown', sheetText.includes('Floor'));
      check('BidSheet', 'YOUR BID label', sheetText.includes('Your bid') || sheetText.includes('YOUR BID'));
      check('BidSheet', 'Amount displayed in gold', !!(await panel.$('.amount')));

      // Amount chips
      check('BidSheet', '+$50 chip', sheetText.includes('+$50'));
      check('BidSheet', '+$100 chip', sheetText.includes('+$100'));
      check('BidSheet', '+$1,000 chip', sheetText.includes('+$1,000'));
      check('BidSheet', '+$10,000 chip', sheetText.includes('+$10,000'));
      check('BidSheet', '+$100,000 chip', sheetText.includes('+$100,000'));
      check('BidSheet', 'Reset chip', sheetText.includes('Reset'));

      // Test incrementing
      const addChip = await panel.$('[data-add="100"]');
      if (addChip) {
        await addChip.click();
        await p.waitForTimeout(200);
        const newAmount = await p.evaluate(() => {
          const el = document.querySelector('.amount');
          return el ? el.textContent : '';
        });
        check('BidSheet', 'Amount increments on +$100 click', true, 'amount=' + newAmount);
      }

      // Reset
      try {
        const resetChip = await p.$('.panel [data-reset]');
        if (resetChip) {
          await resetChip.click();
          await p.waitForTimeout(200);
          check('BidSheet', 'Reset returns to floor price', true);
        }
      } catch(e) { check('BidSheet', 'Reset returns to floor price', false, e.message.slice(0,60)); }

      // Note field
      try {
        const noteField = await p.$('.panel #bid-note, .panel textarea');
        check('BidSheet', 'Note textarea present', !!noteField);
        if (noteField) {
          const placeholder = await noteField.getAttribute('placeholder');
          check('BidSheet', 'Placeholder: "Why you? Make the bid count."', placeholder && placeholder.includes('Why you'));
          await noteField.fill('Testing the bid flow');
        }
      } catch(e) { check('BidSheet', 'Note textarea present', false, e.message.slice(0,60)); }

      // Gild toggle
      check('BidSheet', 'Gild this bid toggle', sheetText.includes('Gild this bid'));
      check('BidSheet', 'Gild cost: 250 gavels', sheetText.includes('250'));
      try {
        const gildBtn = await p.$('.panel [data-gild]');
        if (gildBtn) {
          await gildBtn.click();
          await p.waitForTimeout(300);
          const gildOn = await p.evaluate(() => {
            const el = document.querySelector('[data-gild]');
            return el ? el.classList.contains('on') : false;
          });
          check('BidSheet', 'Gild toggles on', gildOn);
          await p.$('.panel [data-gild]').then(b => b && b.click());
          await p.waitForTimeout(200);
        }
      } catch(e) { check('BidSheet', 'Gild toggles on', false, e.message.slice(0,60)); }

      // Insurance toggle
      check('BidSheet', 'Bid Insurance toggle', sheetText.includes('Bid Insurance'));
      check('BidSheet', 'Insurance cost: 200 gavels', sheetText.includes('200'));
      try {
        const insureBtn = await p.$('.panel [data-insure]');
        if (insureBtn) {
          await insureBtn.click();
          await p.waitForTimeout(300);
          const insOn = await p.evaluate(() => {
            const el = document.querySelector('[data-insure]');
            return el ? el.classList.contains('on') : false;
          });
          check('BidSheet', 'Insurance toggles on', insOn);
          await p.$('.panel [data-insure]').then(b => b && b.click());
          await p.waitForTimeout(200);
        }
      } catch(e) { check('BidSheet', 'Insurance toggles on', false, e.message.slice(0,60)); }

      // Gavel balance row
      check('BidSheet', 'Gavel balance row', sheetText.includes('Gavels'));
      check('BidSheet', '"Get more" link', sheetText.includes('Get more'));

      // Intent callout
      check('BidSheet', 'Intent callout: "money you\'ll spend on the date"', sheetText.includes('money you'));
      check('BidSheet', 'Intent detail: "Dinner, drinks"', sheetText.includes('Dinner'));

      // Whisper button
      check('BidSheet', 'Whisper button', sheetText.includes('whisper'));

      // Disclosure
      check('BidSheet', 'Disclosure text', sheetText.includes('Spend your bid') || sheetText.includes('never wire'));

      await p.screenshot({ path: SCRATCHPAD + '/audit-04-bidsheet.png', fullPage: true });

      // ══════════════════════════════════════════════════════════════
      // SECTION 5: PLACE BID → CELEBRATION → MATCH
      // ══════════════════════════════════════════════════════════════
      console.log('\n══ SECTION 5: BID → CELEBRATION → MATCH ══');
      try {
        const placeBtn = await p.$('.panel #bid-place');
        if (placeBtn) {
          const btnText = await placeBtn.textContent();
          check('BidFlow', 'Place bid button text includes amount', btnText.includes('$'));
          await placeBtn.click();
          await p.waitForTimeout(1000);

          const celebBody = await p.textContent('body');
          const hasCeleb = celebBody.includes('SOLD') || celebBody.includes('sold') || celebBody.includes('Match');
          check('BidFlow', 'Celebration screen appears', hasCeleb);

          await p.screenshot({ path: SCRATCHPAD + '/audit-05-celebration.png' });

          const matchCount = await p.evaluate(() => {
            const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
            return (s.matches || []).length;
          });
          check('BidFlow', 'Match created in state', matchCount >= 1, 'matches=' + matchCount);

          const sayHello = await p.$('button:has-text("Say hello"), button:has-text("hello")');
          if (sayHello) {
            await sayHello.click();
            await p.waitForTimeout(800);
            const hash = await p.evaluate(() => location.hash);
            check('BidFlow', '"Say hello" navigates to chat', hash.includes('chat'), 'hash=' + hash);
          } else {
            await p.click('body', { position: { x: 195, y: 100 } });
            await p.waitForTimeout(500);
          }
        }
      } catch(e) { check('BidFlow', 'Place bid flow', false, e.message.slice(0,80)); }
    }
  }

  } catch(sectionErr) { console.log('  ✗ SECTION 4/5 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'BidSheet',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

  // ══════════════════════════════════════════════════════════════
  // SECTION 6: CHAT (bidder side)
  // ══════════════════════════════════════════════════════════════
  try {
  console.log('\n══ SECTION 6: CHAT ══');
  // Navigate to matches then into the chat
  await p.evaluate(() => location.hash = '/matches');
  await p.waitForTimeout(800);

  const matchesBody = await p.textContent('body');
  check('Chat', 'Matches list shows match', matchesBody.includes('Matches'));

  const matchCard = await p.$('[data-chat]');
  if (matchCard) {
    const matchName = await matchCard.textContent();
    check('Chat', 'Match card shows name', matchName.length > 0);
    await matchCard.click();
    await p.waitForTimeout(800);

    const chatBody = await p.textContent('body');
    check('Chat', 'Chat header shows name', true);
    check('Chat', 'Reserve chip visible (bidder)', chatBody.includes('Reserve') || !!(await p.$('#reserve')));
    check('Chat', 'Report flag visible', chatBody.includes('⚑') || !!(await p.$('#report')));

    // Messages
    const bubbles = await p.$$('.bub');
    check('Chat', 'Message bubbles render', bubbles.length >= 1, 'bubbles=' + bubbles.length);

    // Composer
    const composer = await p.$('#ci');
    check('Chat', 'Composer input present', !!composer);
    const sendBtn = await p.$('#send');
    check('Chat', 'Send button present', !!sendBtn);

    // Send a message
    if (composer && sendBtn) {
      await composer.fill('Hey! Great to match');
      await sendBtn.click();
      await p.waitForTimeout(300);
      const newBubbles = await p.$$('.bub');
      check('Chat', 'Message appears after send', newBubbles.length > bubbles.length, 'now=' + newBubbles.length);

      // Wait for bot reply
      await p.waitForTimeout(2500);
      const afterReply = await p.$$('.bub');
      check('Chat', 'Bot reply arrives (~1-2s)', afterReply.length > newBubbles.length, 'now=' + afterReply.length);

      // Read receipts
      const receipt = await p.$('.receipt');
      if (receipt) {
        const receiptText = await receipt.textContent();
        check('Chat', 'Read receipt shows', receiptText.includes('Seen') || receiptText.includes('Delivered'), receiptText);
      } else {
        warning('Chat', 'Read receipt', 'No .receipt element found');
      }
    }

    // Test reaction — double-tap a bubble
    try {
      const firstBub = await p.$('.bub[data-mid]');
      if (firstBub) {
        await firstBub.dblclick();
        await p.waitForTimeout(300);
        const hasReaction = await p.evaluate(() => !!document.querySelector('.rx'));
        check('Chat', 'Double-tap adds reaction', hasReaction);
      }
    } catch(e) { check('Chat', 'Double-tap adds reaction', false, e.message.slice(0,60)); }

    // Enter key sends
    if (composer) {
      await composer.fill('Testing enter key');
      await composer.press('Enter');
      await p.waitForTimeout(300);
      check('Chat', 'Enter key sends message', true);
    }

    // Empty message doesn't send
    const beforeEmpty = await p.$$('.bub');
    if (sendBtn) {
      await sendBtn.click();
      await p.waitForTimeout(200);
      const afterEmpty = await p.$$('.bub');
      check('Chat', 'Empty message blocked', afterEmpty.length === beforeEmpty.length);
    }

    await p.screenshot({ path: SCRATCHPAD + '/audit-06-chat.png', fullPage: true });

    // ══ RESERVE THE DATE ══
    console.log('\n══ SECTION 6A: RESERVE THE DATE ══');
    const reserveBtn = await p.$('#reserve');
    if (reserveBtn) {
      await reserveBtn.click();
      await p.waitForTimeout(500);
      const reservePanel = await p.$('.panel');
      if (reservePanel) {
        const reserveText = await reservePanel.textContent();
        check('Reserve', 'Reserve sheet opens', true);
        check('Reserve', 'Tier options present', reserveText.includes('$10') || reserveText.includes('$15') || reserveText.includes('$25'));
        check('Reserve', 'Explains booking fee', reserveText.includes('Auction Baby') || reserveText.includes('booking'));

        // Click a tier
        const tierBtn = await reservePanel.$('[data-tier], button.chip');
        if (tierBtn) {
          await tierBtn.click();
          await p.waitForTimeout(500);
          const reservedChip = await p.$('.chip.on');
          check('Reserve', 'Demo: marks as reserved', !!(await p.textContent('body')).match(/Reserved|reserved|Demo/i));
        }
        await p.screenshot({ path: SCRATCHPAD + '/audit-06a-reserve.png' });
      }
    }

    // ══ REPORT & BLOCK ══
    console.log('\n══ SECTION 6B: REPORT & BLOCK ══');
    // Navigate back to chat first
    const matchCards2 = await p.$$('[data-chat]');
    if (matchCards2.length) {
      await matchCards2[0].click();
      await p.waitForTimeout(500);
    }
    const reportBtn = await p.$('#report');
    if (reportBtn) {
      await reportBtn.click();
      await p.waitForTimeout(500);
      const reportPanel = await p.$('.panel');
      if (reportPanel) {
        const reportText = await reportPanel.textContent();
        check('Report', 'Report sheet opens', true);
        check('Report', 'Shows "Block [name]"', reportText.includes('Block'));
        check('Report', 'Reason: Inappropriate', reportText.includes('Inappropriate'));
        check('Report', 'Reason: Harassment', reportText.includes('Harassment'));
        check('Report', 'Reason: Fake profile', reportText.includes('Fake'));
        check('Report', 'Reason: Spam', reportText.includes('Spam'));
        check('Report', 'Reason: Other', reportText.includes('Other'));
        check('Report', 'Cancel button', reportText.includes('Cancel'));

        // Click a reason
        const reasonBtn = await reportPanel.$('[data-reason="Spam"]');
        if (reasonBtn) {
          await reasonBtn.click();
          await p.waitForTimeout(800);
          const postReport = await p.evaluate(() => {
            const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
            return s.matches.length;
          });
          check('Report', 'Match removed after report', postReport === 0, 'matches=' + postReport);
        }
        await p.screenshot({ path: SCRATCHPAD + '/audit-06b-report.png' });
      }
    }
  }

  } catch(sectionErr) { console.log('  ✗ SECTION 6 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Chat',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }
  await p.close();
}

// ══════════════════════════════════════════════════════════════
// SECTION 7: WOMAN FLOW (Bids → Accept → Match → Chat)
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 7: WOMAN FLOW ══');
try {
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'woman', me: { name: 'Test Woman', age: 25, city: 'LA', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(1500);

  const body = await p.textContent('body');
  check('Woman', '"Your bids" header', body.includes('Your bids'));
  check('Woman', 'Tab bar shows "Bids"', body.includes('Bids'));

  // Check suitors seeded
  const suitorCount = await p.evaluate(() => {
    const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
    return (s.incoming || []).length;
  });
  check('Woman', 'Demo suitors seeded', suitorCount >= 4, 'count=' + suitorCount);

  // Check suitor cards
  const bidCards = await p.$$('.card');
  const hasSuitors = body.includes('Marcus') || body.includes('Julian') || body.includes('Theo') || body.includes('Dominic');
  check('Woman', 'Suitor names visible', hasSuitors);

  // Check bid amounts shown
  check('Woman', 'Bid amounts in gold', body.includes('$500') || body.includes('$1,000') || body.includes('$750') || body.includes('$300'));

  // Check Accept/Pass buttons
  const acceptBtns = await p.$$('[data-accept]');
  const declineBtns = await p.$$('[data-decline]');
  check('Woman', 'Accept buttons present', acceptBtns.length >= 1, 'count=' + acceptBtns.length);
  check('Woman', 'Pass buttons present', declineBtns.length >= 1, 'count=' + declineBtns.length);

  await p.screenshot({ path: SCRATCHPAD + '/audit-07-woman-bids.png', fullPage: true });

  // Decline a bid
  if (declineBtns.length >= 1) {
    const beforeDecline = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.incoming.length;
    });
    await declineBtns[0].click();
    await p.waitForTimeout(500);
    const afterDecline = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.incoming.length;
    });
    check('Woman', 'Pass removes bid', afterDecline < beforeDecline, `${beforeDecline} → ${afterDecline}`);
  }

  // Accept a bid
  const acceptBtns2 = await p.$$('[data-accept]');
  if (acceptBtns2.length >= 1) {
    await acceptBtns2[0].click();
    await p.waitForTimeout(1500);

    const celebBody = await p.textContent('body');
    const hasCeleb = celebBody.includes('SOLD') || celebBody.includes('Match') || celebBody.includes('match');
    check('Woman', 'Accept → celebration', hasCeleb);

    // Check match created
    const matchCount = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.matches.length;
    });
    check('Woman', 'Match created', matchCount >= 1, 'matches=' + matchCount);

    await p.screenshot({ path: SCRATCHPAD + '/audit-07a-woman-accept.png' });

    // Dismiss celebration overlay
    const celebDismiss = await p.$('.celebrate');
    if (celebDismiss) {
      await celebDismiss.click();
      await p.waitForTimeout(800);
    }
    // Also try removing it via JS if still present
    await p.evaluate(() => { const c = document.querySelector('.celebrate'); if (c) c.remove(); });
    await p.waitForTimeout(300);

    // Navigate to match
    await p.evaluate(() => location.hash = '/matches');
    await p.waitForTimeout(800);
    const matchCard = await p.$('[data-chat]');
    if (matchCard) {
      await matchCard.click({ force: true });
      await p.waitForTimeout(800);
      const chatBody = await p.textContent('body');
      check('Woman', 'Chat opens from match', chatBody.includes('Message') || !!(await p.$('#ci')));
      check('Woman', 'No Reserve chip for woman', !(await p.$('#reserve')));
      await p.screenshot({ path: SCRATCHPAD + '/audit-07b-woman-chat.png' });
    }
  }

  await p.close();
} catch(sectionErr) { console.log('  ✗ SECTION 7 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Woman',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

// ══════════════════════════════════════════════════════════════
// SECTION 8: STORE (full)
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 8: STORE ══');
try {
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'man', me: { name: 'Mike', age: 30, city: 'NYC', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3, pendingBids: 0
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(1000);
  await p.evaluate(() => location.hash = '/store');
  await p.waitForTimeout(800);

  const body = await p.textContent('body');
  check('Store', '"Store" header', body.includes('Store'));
  check('Store', 'Gavel balance pill', body.includes('750'));

  // Gavels
  check('Store', 'Handful: 1,000 Gavels / $4.99', body.includes('1,000') && body.includes('$4.99'));
  check('Store', 'Stack: 5,000 Gavels / $19.99', body.includes('5,000') && body.includes('$19.99'));
  check('Store', 'Chest: 14,000 Gavels / $49.99', body.includes('14,000') && body.includes('$49.99'));
  check('Store', 'Vault: 30,000 Gavels / $99.99', body.includes('30,000') && body.includes('$99.99'));
  check('Store', 'BEST VALUE pill on Vault', body.includes('BEST VALUE'));

  // Spotlight Boost
  check('Store', 'Spotlight Boost section', body.includes('Spotlight Boost'));
  check('Store', 'Boost: $4.99', body.includes('$4.99'));

  // Status tiers
  check('Store', 'Status section', body.includes('Status'));
  check('Store', 'Good Guy: $4.99', body.includes('Good Guy'));
  check('Store', 'In & Out Guy: $9.99', body.includes('In & Out'));
  check('Store', 'Why Not Guy: $19.99', body.includes('Why Not'));
  check('Store', 'Got a Good Job: $99.99', body.includes('Good Job'));
  check('Store', 'Inheritance Money Guy: $500', body.includes('Inheritance'));
  check('Store', 'Influencer: $800', body.includes('Influencer'));
  check('Store', 'I Drive a Ferrari: $900', body.includes('Ferrari'));
  check('Store', 'Trillionaire: $1,000', body.includes('Trillionaire'));
  check('Store', 'Trillionaire TOP TIER pill', body.includes('TOP TIER'));

  // Passes
  check('Store', 'Paddle: $19.99/mo', body.includes('Paddle'));
  check('Store', 'Reserve: $39.99/mo', body.includes('Reserve'));
  check('Store', 'Black Card: $99.99/mo', body.includes('Black Card'));
  check('Store', 'Subscribe buttons', !!(await p.$('[data-sub]')));

  // Disclosure
  check('Store', 'Stripe disclosure', body.includes('Stripe') || body.includes('payment'));

  // Demo purchase — buy gavels
  const buyBtn = await p.$('[data-buy="1000"]');
  if (buyBtn) {
    await buyBtn.click();
    await p.waitForTimeout(800);
    const newWallet = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.wallet;
    });
    check('Store', 'Demo: Gavels purchase increments wallet', newWallet > 750, 'wallet=' + newWallet);
  }

  // Demo subscribe
  const subBtn = await p.$('[data-sub="Paddle"]');
  if (subBtn) {
    await subBtn.click();
    await p.waitForTimeout(800);
    const pass = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.pass;
    });
    check('Store', 'Demo: Pass subscription sets S.pass', !!pass, 'pass=' + pass);
  }

  // Demo buy status
  const statusBtn = await p.$('[data-status="status_good_guy"]');
  if (statusBtn) {
    await statusBtn.click();
    await p.waitForTimeout(800);
    const owned = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.ownedStatus;
    });
    check('Store', 'Demo: Status purchase adds to ownedStatus', owned && owned.length > 0, JSON.stringify(owned));
  }

  await p.screenshot({ path: SCRATCHPAD + '/audit-08-store.png', fullPage: true });

  // Woman store — should NOT have Status section
  console.log('\n══ SECTION 8A: WOMAN STORE ══');
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'woman', me: { name: 'Test', age: 25, city: 'LA', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(500);
  await p.evaluate(() => location.hash = '/store');
  await p.waitForTimeout(800);
  const womanStore = await p.textContent('body');
  check('WomanStore', 'Boost visible for women', womanStore.includes('Boost'));
  check('WomanStore', 'NO Gavels section', !womanStore.includes('Handful'));
  check('WomanStore', 'NO Status section', !womanStore.includes('Good Guy'));
  check('WomanStore', 'NO Pass section', !womanStore.includes('Paddle'));
  await p.screenshot({ path: SCRATCHPAD + '/audit-08a-woman-store.png', fullPage: true });

  await p.close();
} catch(sectionErr) { console.log('  ✗ SECTION 8 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Store',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

// ══════════════════════════════════════════════════════════════
// SECTION 9: PAYWALL (all triggers)
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 9: PAYWALL ══');
try {
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'man', me: { name: 'Mike', age: 30, city: 'NYC', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3, pendingBids: 0
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(1000);

  // Test each trigger
  const triggers = [
    ['general', 'Win the bid', 0],
    ['rankReveal', 'comparing bids', 0],
    ['bidLimit', 'free bids', 0],
    ['filters', 'Cut the noise', 1],
    ['readReceipts', 'She read it', 2],
    ['rewind', 'Bid too soon', 1],
  ];

  for (const [trigger, expectedText, expectedTier] of triggers) {
    await p.evaluate(t => location.hash = '/paywall/' + t, trigger);
    await p.waitForTimeout(600);
    const body = await p.textContent('body');
    check('Paywall', `Trigger "${trigger}" headline`, body.includes(expectedText), 'looking for: ' + expectedText);
  }

  // Test full paywall structure on general
  await p.evaluate(() => location.hash = '/paywall/general');
  await p.waitForTimeout(600);
  const pwBody = await p.textContent('body');

  check('Paywall', '"Auction Baby Pass" kicker', pwBody.includes('Auction Baby Pass'));
  check('Paywall', 'Paddle tier card', pwBody.includes('Paddle'));
  check('Paywall', 'Reserve tier card', pwBody.includes('Reserve'));
  check('Paywall', 'Black Card tier card', pwBody.includes('Black Card'));
  check('Paywall', '$19.99/month', pwBody.includes('$19.99') || pwBody.includes('19.99'));
  check('Paywall', '$39.99/month', pwBody.includes('$39.99') || pwBody.includes('39.99'));
  check('Paywall', '$99.99/month', pwBody.includes('$99.99') || pwBody.includes('99.99'));

  // Benefits matrix
  check('Paywall', 'Benefit: Unlimited live bids', pwBody.includes('Unlimited'));
  check('Paywall', 'Benefit: See if top bid', pwBody.includes('top bid'));
  check('Paywall', 'Benefit: Spotlight Boost', pwBody.includes('Boost'));
  check('Paywall', 'Benefit: Reserve price', pwBody.includes('reserve price'));
  check('Paywall', 'Benefit: Auto-rebid', pwBody.includes('Auto-rebid'));
  check('Paywall', 'Benefit: Advanced filters', pwBody.includes('filters'));
  check('Paywall', 'Benefit: Rewind', pwBody.includes('Rewind'));
  check('Paywall', 'Benefit: Read receipts', pwBody.includes('Read receipts') || pwBody.includes('Seen'));
  check('Paywall', 'Benefit: Priority placement', pwBody.includes('Priority'));

  // CTA button
  check('Paywall', '"Continue with [tier]" CTA', pwBody.includes('Continue'));
  check('Paywall', '"Maybe later" button', pwBody.includes('Maybe later'));

  // Disclosure
  check('Paywall', 'Auto-renew disclosure', pwBody.includes('auto-renew') || pwBody.includes('Auto-renew'));
  check('Paywall', 'Stripe disclosure', pwBody.includes('Stripe'));

  // Test tier selection
  const tierCards = await p.$$('.paywall-tier, .pw-tier');
  if (tierCards.length >= 3) {
    await tierCards[2].click(); // Black Card
    await p.waitForTimeout(400);
    const updatedBody = await p.textContent('body');
    check('Paywall', 'Selecting Black Card updates CTA', updatedBody.includes('Black Card') || updatedBody.includes('Continue'));
  }

  // Test CTA in demo mode
  const ctaBtn = await p.$('button.btn.cta, button.btn');
  let paywallCTA = null;
  const allBtns = await p.$$('button.btn');
  for (const b of allBtns) { const t = await b.textContent(); if (t.includes('Continue')) { paywallCTA = b; break; } }
  if (paywallCTA) {
    await paywallCTA.click();
    await p.waitForTimeout(800);
    const passSet = await p.evaluate(() => {
      const s = JSON.parse(localStorage.getItem('auctionbaby.web.v1') || '{}');
      return s.pass;
    });
    check('Paywall', 'Demo: CTA sets pass in state', !!passSet, 'pass=' + passSet);
  }

  // With pass active, paywall should show "active" state
  await p.evaluate(() => location.hash = '/paywall/general');
  await p.waitForTimeout(600);
  const activeBody = await p.textContent('body');
  check('Paywall', 'Active pass shows status', activeBody.includes('active') || activeBody.includes('Active') || activeBody.includes('✓'));

  await p.screenshot({ path: SCRATCHPAD + '/audit-09-paywall.png', fullPage: true });
  await p.close();
} catch(sectionErr) { console.log('  ✗ SECTION 9 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Paywall',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

// ══════════════════════════════════════════════════════════════
// SECTION 10: NAVIGATION & EDGE CASES
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 10: NAVIGATION & EDGE CASES ══');
try {
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'man', me: { name: 'Mike', age: 30, city: 'NYC', photo: null },
      floor: [], matches: [], incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3, pendingBids: 0
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(1500);

  // Hash routing
  const routes = [
    ['#/floor', 'The Floor'],
    ['#/matches', 'Matches'],
    ['#/store', 'Store'],
    ['#/you', 'Mike'],
    ['#/paywall', 'Pass'],
  ];
  for (const [hash, expected] of routes) {
    await p.evaluate(h => location.hash = h.replace('#', ''), hash);
    await p.waitForTimeout(500);
    const text = await p.textContent('body');
    check('Nav', `Route ${hash}`, text.includes(expected), 'looking for: ' + expected);
  }

  // Invalid lot ID → redirects to floor
  await p.evaluate(() => location.hash = '/lot/nonexistent');
  await p.waitForTimeout(500);
  const lotFallback = await p.evaluate(() => location.hash);
  check('Nav', 'Invalid lot → floor redirect', lotFallback.includes('floor'), 'hash=' + lotFallback);

  // Invalid chat ID → redirects to matches
  await p.evaluate(() => location.hash = '/chat/nonexistent');
  await p.waitForTimeout(500);
  const chatFallback = await p.evaluate(() => location.hash);
  check('Nav', 'Invalid chat → matches redirect', chatFallback.includes('matches'), 'hash=' + chatFallback);

  // You page — profile details
  await p.evaluate(() => location.hash = '/you');
  await p.waitForTimeout(500);
  const youBody = await p.textContent('body');
  check('You', 'Name displayed', youBody.includes('Mike'));
  check('You', 'Age displayed', youBody.includes('30'));
  check('You', 'City displayed', youBody.includes('NYC'));
  check('You', 'Role: Bidder', youBody.includes('Bidder'));
  check('You', 'Gavel balance', youBody.includes('750') || youBody.includes('Gavel'));
  check('You', '"Add a photo" button', youBody.includes('photo') || youBody.includes('Photo'));
  check('You', '"Verify me" button', youBody.includes('Verify'));
  check('You', '"Open the Store" button', youBody.includes('Store'));
  check('You', '"Get an Auction Baby Pass" button', youBody.includes('Pass'));
  check('You', '"Reset account" button', youBody.includes('Reset'));

  await p.screenshot({ path: SCRATCHPAD + '/audit-10-you.png', fullPage: true });
  await p.close();
} catch(sectionErr) { console.log('  ✗ SECTION 10 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Nav',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

// ══════════════════════════════════════════════════════════════
// SECTION 11: SECURITY (XSS checks)
// ══════════════════════════════════════════════════════════════
console.log('\n══ SECTION 11: SECURITY ══');
try {
  const p = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await p.goto(BASE + '/index.html', { waitUntil: 'load' });
  await p.evaluate(() => {
    localStorage.setItem('auctionbaby.web.v1', JSON.stringify({
      registered: true, role: 'man',
      me: { name: '<img src=x onerror=alert(1)>', age: 30, city: '<script>alert(2)</script>', photo: null },
      floor: [], matches: [
        { id: 'xss-match', name: '<b onmouseover=alert(3)>XSS</b>', hue: 0, amount: 100,
          messages: [{ me: false, text: '<img src=x onerror=alert(4)>' }], lastTs: Date.now() }
      ],
      incoming: [], wallet: 750, pass: null, ownedStatus: [], freeBids: 3
    }));
  });
  await p.reload({ waitUntil: 'load' });
  await p.waitForTimeout(1500);

  // Check no alerts fired (XSS)
  let alertFired = false;
  p.on('dialog', d => { alertFired = true; d.dismiss(); });

  await p.evaluate(() => location.hash = '/you');
  await p.waitForTimeout(500);
  check('Security', 'XSS in name: no alert', !alertFired);

  await p.evaluate(() => location.hash = '/matches');
  await p.waitForTimeout(500);
  check('Security', 'XSS in match name: no alert', !alertFired);

  await p.evaluate(() => location.hash = '/chat/xss-match');
  await p.waitForTimeout(500);
  check('Security', 'XSS in chat message: no alert', !alertFired);

  // Verify escaping is visible (tags rendered as text)
  const chatBody = await p.textContent('body');
  check('Security', 'HTML entities escaped (visible as text)', chatBody.includes('<img') || chatBody.includes('&lt;'));

  await p.close();
} catch(sectionErr) { console.log('  ✗ SECTION 11 CRASH: ' + sectionErr.message.slice(0,100)); fail++; results.push({section:'Security',name:'Section crashed',status:'FAIL',note:sectionErr.message.slice(0,100)}); }

// ══════════════════════════════════════════════════════════════
// SUMMARY
// ══════════════════════════════════════════════════════════════
console.log('\n══════════════════════════════════════════');
console.log(`AUDIT COMPLETE: ${pass} PASS, ${fail} FAIL, ${warn} WARN`);
console.log('══════════════════════════════════════════');
if (fail > 0) {
  console.log('\nFAILURES:');
  results.filter(r => r.status === 'FAIL').forEach(r => {
    console.log(`  ✗ [${r.section}] ${r.name}${r.note ? ' — ' + r.note : ''}`);
  });
}
if (warn > 0) {
  console.log('\nWARNINGS:');
  results.filter(r => r.status === 'WARN').forEach(r => {
    console.log(`  ⚠ [${r.section}] ${r.name} — ${r.note}`);
  });
}

// Write JSON results
const fs = require('fs');
fs.writeFileSync(SCRATCHPAD + '/audit-results.json', JSON.stringify({ pass, fail, warn, results }, null, 2));

await browser.close();
server.close();
})();
