# Profile Photo Generation Guide

Ready-to-paste prompts for generating every profile's photo (Midjourney,
DALL·E, Flux, etc.), matched to each character's bio, age, and styling.

## Workflow

1. Generate with the prompts below (all subjects are **fictional AI people** —
   that's the point, and it avoids any real-person likeness/consent issues).
2. Crop to **portrait 3:4** (e.g. 1200×1600). Faces in the upper third.
3. Drop each image into `AuctionBaby/Resources/Assets.xcassets` as a new
   Image Set with the **exact name** listed (e.g. `photo-mara`).
4. Done — the app picks them up everywhere automatically. Missing assets fall
   back to the generated portrait, so you can add them incrementally.

**Consistency tips:** append `photorealistic, shot on 85mm f/1.8, natural skin
texture, soft golden light, candid dating-app photo, no text, no watermark` to
every prompt. Reuse the same seed / character reference per person if you
generate multiple shots. Avoid studio-perfect looks for the *real* profiles —
slight candidness reads authentic; save the flawless look for the Copycats.

---

## The Lots (women, real profiles — candid & warm)

**`photo-mara`** — Mara Quinn, 27, SoHo gallery curator
> Portrait of a stylish 27-year-old woman at a modern art gallery opening,
> dark wavy hair, wine glass in hand, black turtleneck and gold earrings,
> confident half-smile, warm gallery lighting, candid

**`photo-priya`** — Priya Sethi, 29, Chicago ER doctor
> Portrait of a 29-year-old South Asian woman laughing at an outdoor café,
> athletic-casual style, denim jacket, hair down, genuine mid-laugh smile,
> late-afternoon city light, candid

**`photo-sloane`** — Sloane Carter, 31, Venice Beach founder
> Portrait of a 31-year-old woman with a blonde bob outside a Venice Beach
> coffee shop, linen blazer over a white tee, espresso cup, direct confident
> gaze, bright morning coastal light

**`photo-noor`** — Noor Haddad, 26, Seattle climate engineer
> Portrait of a 26-year-old Middle Eastern woman on a forest trail summit,
> hiking jacket, curly hair escaping a beanie, big genuine grin, misty
> evergreen background, overcast soft light

**`photo-valentina`** — Valentina Cruz, 28, Brooklyn pastry chef
> Portrait of a 28-year-old Latina woman in a bakery kitchen, flour-dusted
> apron over a vintage band tee, holding a plated dessert, playful proud
> smile, warm tungsten kitchen light

## The Bidders (men)

**`photo-mike`** — Mike Valasek, 39, Founder (the first Trillionaire)
> Portrait of a 39-year-old man in a perfectly tailored midnight-blue suit,
> no tie, seated in a dim luxury lounge with a gold-lit bar behind him,
> composed confident expression, cinematic rim light

**`photo-julian`** — Julian West, 34, Tribeca private equity
> Portrait of a 34-year-old man on a sailboat deck at golden hour, navy
> polo, sunglasses pushed up, relaxed smile, harbor background

**`photo-marcus`** — Marcus Bell, 38, Atlanta family business
> Portrait of a 38-year-old Black man in a cream linen suit at an outdoor
> evening event, pocket square, charming smile, string lights bokeh

**`photo-dominic`** — Dominic Vance, 41, Bel Air
> Portrait of a 41-year-old man leaning against a red sports car at dusk,
> black bomber jacket, watch catching the light, slight smirk, hills behind

**`photo-sam`** — Sam Okafor, 30, DC history teacher
> Portrait of a 30-year-old Black man in a cozy bookshop, cardigan over an
> oxford shirt, holding a paperback, warm open laugh, shelves of books behind

---

## The Copycats (AI lures — deliberately flawless, "too perfect")

These four should look like an 11/10: editorial-grade, symmetrical, impossibly
polished. That gloss *is* the tell for sharp-eyed players. Swimwear/athleisure
level only. The app overlays the `AI` watermark automatically in post-reveal
contexts — bake nothing in.

**`photo-bella`** — Bella Rose, 23, Miami Beach · *Poolside*
> Glamour portrait of a strikingly beautiful 23-year-old woman lounging at
> the edge of an infinity pool, designer bikini, flawless glowing skin, long
> honey-blonde waves, turquoise water and white cabanas behind, magazine-
> editorial perfection, golden-hour shimmer

**`photo-crystal`** — Crystal Lux, 24, Las Vegas · *Glam*
> Glamour portrait of a stunning 24-year-old woman in a fitted metallic
> cocktail dress at a rooftop bar at night, immaculate makeup, glossy dark
> hair, city lights bokeh, flawless editorial finish

**`photo-jade`** — Jade Rivera, 25, Tulum · *Yoga*
> Glamour portrait of a gorgeous 25-year-old woman in a matching sage yoga
> set on a Tulum beach platform at sunrise, perfect posture mid-stretch,
> sun-kissed flawless skin, ocean behind, editorial wellness-magazine look

**`photo-amber`** — Amber Skye, 24, Malibu · *Beach*
> Glamour portrait of a breathtaking 24-year-old woman walking out of the
> surf at golden hour in a coral one-piece swimsuit, wet sun-lightened hair,
> perfect symmetry, Malibu cliffs behind, cinematic magazine perfection
