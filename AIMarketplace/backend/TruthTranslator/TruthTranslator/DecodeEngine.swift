import Foundation

struct DecodeEngine {
    func decode(text: String, tone: DecodeTone, context: DecodeContext) -> DecodeResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DecodeResult.placeholder
        }

        let lower = trimmed.lowercased()
        if containsSafetySignal(lower) {
            return safetyResult(context: context)
        }

        var signals: [Signal] = []

        // ── Effort, availability, and warmth ──
        if lower.containsAny("crazy week", "so busy", "busy rn", "busy right now", "swamped", "slammed", "overwhelmed", "insane right now") {
            signals.append(.busyFog)
        }
        if lower.containsAny("maybe", "we'll see", "we will see", "idk", "i guess", "i suppose", "possibly", "probably", "we'll figure") {
            signals.append(.noncommittal)
        }
        if lower.containsAny("come over", "u up", "you up", "wyd", "come thru", "swing by", "pull up", "stop by", "wya", "where you at") {
            signals.append(.convenience)
        }
        if lower.containsAny("sorry just saw", "just saw this", "forgot to reply", "phone died", "was asleep", "didn't see", "notifications off", "my bad", "lost my phone") {
            signals.append(.lateRepair)
        }
        if lower.containsAny("not ready", "not looking for", "go with the flow", "see where this goes", "no pressure", "no labels", "keep it casual", "take it slow", "just having fun", "nothing serious") {
            signals.append(.limitedIntent)
        }
        if lower.containsAny("miss you", "thinking of you", "want to see you", "can't stop thinking", "wish you were here", "been thinking about you") {
            signals.append(.warmth)
        }
        if hasActualPlan(lower) {
            signals.append(.actualPlan)
        }

        // ── Breadcrumbing & future-faking ──
        if lower.containsAny("soon", "eventually", "one day", "someday", "at some point", "down the road", "when things calm", "after this week", "next time", "let's plan", "we should def"), !hasActualPlan(lower) {
            signals.append(.futureFaking)
        }
        if lower.containsAny("you mad", "are you mad", "why aren't you", "still there", "don't ignore", "you're ignoring", "talk to me", "what's wrong with you") {
            signals.append(.validationSeeking)
        }
        if (lower.containsAny("just checking", "what's up", "sup") || (lower.contains("hey") && trimmed.count < 10)), !hasActualPlan(lower) {
            signals.append(.lowEffortPing)
        }

        // ── Intensity without investment ──
        if lower.containsAny("gorgeous", "stunning", "so hot", "sexy", "perfect", "obsessed with you", "can't get enough", "dream girl", "never felt this"), !hasActualPlan(lower) {
            signals.append(.loveBombing)
        }
        if lower.containsAny("send me a pic", "send a pic", "send pic", "show me", "let me see", "selfie", "send nudes", "snap me"), !hasActualPlan(lower) {
            signals.append(.complianceTest)
        }

        // ── Deflection, gaslighting, soft exits ──
        if lower.containsAny("overthinking", "you need to relax", "just chill", "not that deep", "being dramatic", "so sensitive", "insecure", "you're crazy", "being crazy", "psycho", "jealous") {
            signals.append(.deflection)
        }
        if lower.containsAny("just a joke", "it was a joke", "you took that wrong", "that's not what i", "i was just saying", "don't take it", "misunderstood", "never said that") {
            signals.append(.gaslighting)
        }
        if lower.containsAny("need space", "need some time", "figure myself out", "not in a place", "can't give you", "you deserve better", "don't want to hurt you", "it's not you it's me") {
            signals.append(.commitmentDodge)
        }
        if lower.containsAny("bad at this", "bad at relationships", "not good with", "i'm damaged", "i'm broken", "messed up", "not relationship material", "emotionally unavailable") {
            signals.append(.selfDeprecationShield)
        }

        // ── Genuine investment ──
        if lower.containsAny("made a reservation", "picked out", "thought of you when", "saw this and thought", "reminded me of you", "how was your", "how did it go", "proud of you", "let me take you") {
            signals.append(.genuineInvestment)
        }

        if signals.isEmpty {
            signals.append(.ambiguous)
        }

        let score = score(for: signals, context: context)
        return DecodeResult(
            headline: headline(for: signals, tone: tone),
            translation: translation(for: signals, tone: tone, context: context),
            psychology: psychology(for: signals, context: context),
            receipts: receipts(for: signals),
            suggestedReplies: replies(for: signals, tone: tone, context: context),
            realityScore: score,
            energy: energy(for: score),
            flags: flags(for: signals)
        ).normalized
    }

    private enum Signal {
        case actualPlan
        case ambiguous
        case busyFog
        case convenience
        case lateRepair
        case limitedIntent
        case noncommittal
        case warmth
        case futureFaking          // "soon" / "eventually" with no concrete plan
        case validationSeeking     // "you mad?" / "still there?" — orbiting
        case lowEffortPing         // "hey" / "wyd" — checking if you're still available
        case loveBombing           // compliment tsunami, empty calendar
        case complianceTest        // "send a pic" — boundary probe
        case deflection            // "you're overthinking" — invalidating your read
        case gaslighting           // "it was a joke" — rewriting the transcript
        case commitmentDodge       // "I need space" — soft exit
        case selfDeprecationShield // "I'm bad at relationships" — preemptive excuse
        case genuineInvestment     // remembered details, real effort
    }

    private func containsSafetySignal(_ text: String) -> Bool {
        let terms = ["hurt you", "kill", "threat", "hit me", "hit you", "stalk", "scared", "afraid",
                     "self harm", "self-harm", "suicide", "kill myself", "end it all", "weapon",
                     "rape", "force you", "won't let you leave", "regret it", "know where you live"]
        return terms.contains { text.contains($0) }
    }

    private func hasActualPlan(_ text: String) -> Bool {
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tonight", "tomorrow"]
        let planWords = ["dinner", "coffee", "drinks", "walk", "call", "meet", "reservation", "7", "8", "9", "brunch", "lunch", "movie", "concert", "tickets", "booked", "reserved"]
        return days.contains { text.contains($0) } && planWords.contains { text.contains($0) }
    }

    // MARK: - Safety

    private func safetyResult(context: DecodeContext) -> DecodeResult {
        DecodeResult(
            headline: "This one leaves the joke drawer closed.",
            translation: "The message has threat or harm language. This isn't a dating read — it's a safety read. Distance and documentation come before any conversation about the relationship.",
            psychology: "Intimidation is a control tactic, not a communication style. When your body reads danger, that instinct is data — trust it over any charm that follows. Distance, saved evidence, and a trusted person or local emergency help (if danger is immediate) come first.",
            receipts: ["Threat language", "Safety first", "Do not debate your way into clarity"],
            suggestedReplies: [
                "I am not continuing this conversation. Do not contact me again.",
                "I need space. I am saving this message and stepping away.",
                context == .work ? "Please keep future communication professional and in writing." : "I am done engaging with this."
            ],
            realityScore: 5,
            energy: "Exit plan",
            flags: ["Safety"]
        )
    }

    // MARK: - Headlines (funny, blunt, never mean)

    private func headline(for signals: [Signal], tone: DecodeTone) -> String {
        // Compound combos first — the funniest reads
        if signals.contains(.actualPlan) && signals.contains(.warmth) {
            return "He brought the charm AND the calendar. Rare species — do not spook it."
        }
        if signals.contains(.loveBombing) && signals.contains(.convenience) {
            return "Compliments for breakfast, crumbs for dinner."
        }
        if signals.contains(.deflection) && signals.contains(.gaslighting) {
            return "He's running the emotional three-card monte."
        }
        if signals.contains(.futureFaking) && signals.contains(.busyFog) {
            return "The calendar is always full but the schedule is always empty."
        }
        if signals.contains(.selfDeprecationShield) && signals.contains(.commitmentDodge) {
            return "He handed you the disclaimer before you asked for the contract."
        }

        // Single signals
        if signals.contains(.complianceTest) { return "He's auditioning you, not dating you." }
        if signals.contains(.gaslighting) { return "He's editing the replay and hoping you don't have DVR." }
        if signals.contains(.deflection) { return "He told you your spidey sense is broken. Your spidey sense is fine." }
        if signals.contains(.commitmentDodge) { return "He's leaving through the door he pretends isn't there." }
        if signals.contains(.loveBombing) { return "The words are sweet, the calendar is empty. Do the math." }
        if signals.contains(.futureFaking) { return "He's selling you a timeshare in a country that doesn't exist yet." }
        if signals.contains(.validationSeeking) { return "He wants to know you're still waiting — not to give you a reason to." }
        if signals.contains(.lowEffortPing) { return "That's not a text, that's a sonar ping." }
        if signals.contains(.selfDeprecationShield) { return "He pre-loaded the excuse so you'd feel bad for having a standard." }
        if signals.contains(.actualPlan) { return "An actual plan. In this economy? Groundbreaking." }
        if signals.contains(.genuineInvestment) { return "This one brought receipts, not vibes." }
        if signals.contains(.convenience) {
            return tone == .spicy ? "This smells like crumbs with cologne." : "He wants the room key, not the dinner reservation."
        }
        if signals.contains(.limitedIntent) { return "He put the terms and conditions in tiny emotional font." }
        if signals.contains(.busyFog) && signals.contains(.lateRepair) { return "The calendar excuse has entered the chat — fashionably late." }
        if signals.contains(.noncommittal) { return "A maybe is a no wearing a tiny hat." }
        if signals.contains(.warmth) { return "There's warmth here, but warmth without a plan is just a space heater." }
        return "The message is doing interpretive dance. Ask it to speak in sentences."
    }

    // MARK: - Translations (blunt, funny)

    private func translation(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> String {
        if signals.contains(.actualPlan) {
            return "He's offering something measurable. A man with a plan is a man with intent. Keep standards awake, but this is more than vapor."
        }
        if signals.contains(.complianceTest) {
            return "He's testing your boundaries, not your beauty. The request is the red flag — not your hesitation."
        }
        if signals.contains(.gaslighting) {
            return "He's rewriting the scene and hoping you forget what actually happened. 'It was a joke' usually means 'I meant it and won't own it.'"
        }
        if signals.contains(.deflection) {
            return "He just made your valid observation the problem. Read it again — your read is correct; his reframe is the tell."
        }
        if signals.contains(.commitmentDodge) {
            return "He's handing you a graceful exit dressed as self-awareness. 'You deserve better' is him agreeing with you. Take the hint, keep the receipt."
        }
        if signals.contains(.loveBombing) {
            return "Fast words, slow actions. The compliment tsunami feels amazing, but check the calendar — if it's empty, it's all appetizer, no main course."
        }
        if signals.contains(.futureFaking) {
            return "Beautiful picture of a future he has no plan to build. 'Soon' is the most loaded three-letter word in dating: it means 'not now' and 'not committed.'"
        }
        if signals.contains(.convenience) {
            return context == .dating
                ? "He wants the benefits without the logistics — cute enough to text at midnight, not serious enough to book a table at 7."
                : "They want a quick yes without carrying the full ask."
        }
        if signals.contains(.limitedIntent) {
            return "He's telling you the ceiling is low. Men who mean it show a plan; men who don't show a disclaimer. Believe the disclaimer."
        }
        if signals.contains(.busyFog) {
            return "He may be busy. Busy people still know nouns like day, time, and place. If he wanted to see you, he'd know when."
        }
        if signals.contains(.noncommittal) {
            return "He's keeping the door cracked so he can feel polite while promising nothing. A maybe is a no that's too shy to say so."
        }
        if signals.contains(.lateRepair) {
            return "The apology is a coupon — useful only if it can be redeemed for changed behavior. Otherwise it's a coupon for more coupons."
        }
        if signals.contains(.genuineInvestment) {
            return "This is what effort looks like: he remembers details and acts on them. The gap between interested and serious is a calendar entry, and he made one."
        }
        if tone == .spicy {
            return "Not a smoking clue, but not a love letter either. Call it boutique nonsense until the receipts arrive."
        }
        return "Not enough clear effort yet. Ask one clean question and let the answer do the exposing."
    }

    // MARK: - Psychology (named patterns, therapy-informed)

    private func psychology(for signals: [Signal], context: DecodeContext) -> String {
        if signals.contains(.gaslighting) && signals.contains(.deflection) {
            return "This is the DARVO pattern — Deny, Attack, Reverse Victim and Offender. Naming your reaction as the problem is how accountability gets dodged. In Gottman's framework this is contempt plus defensiveness, two of the four horsemen. Your perception is the evidence; his reframe is the manipulation."
        }
        if signals.contains(.complianceTest) {
            return "This is a boundary probe from the compliance ladder: small asks that escalate. Requests that arrive before any real investment are screening for low resistance. Your 'no' is data about your standards; his reaction to it is data about his character."
        }
        if signals.contains(.loveBombing) {
            return "Intensity isn't intimacy. Early over-the-top flattery activates your attachment system before trust is earned — intermittent reinforcement, the same loop that makes slot machines sticky. Depth shows up as consistency, not volume."
        }
        if signals.contains(.futureFaking) {
            return "Future-faking describes a shared future to secure present attention. The promise is free; the follow-through costs effort. Your brain files the promise as real until evidence says otherwise — that's the gap being exploited."
        }
        if signals.contains(.commitmentDodge) {
            return "'You deserve better' is agreement, not sacrifice. 'I need space' is a soft exit that asks you to hold the door open in case he changes his mind. Avoidant patterns confess the exit early — believe the pattern, not the potential."
        }
        if signals.contains(.validationSeeking) {
            return "This is orbiting — proximity without investment. He's monitoring whether you're still available while avoiding the effort real reconnection requires. He's not fixing anything; he's checking the door is still unlocked."
        }
        if signals.contains(.selfDeprecationShield) {
            return "Preemptive self-deprecation lowers your expectations before you can be disappointed — a dismissive-avoidant move where vulnerability is performed, not practiced. It's not a confession; it's future plausible deniability."
        }
        if signals.contains(.actualPlan) {
            return "Specificity is a secure-attachment tell: it moves the interaction from fantasy to behavior, and behavior is the only receipt that counts. In Gottman's terms a concrete plan is a clear bid for connection."
        }
        if signals.contains(.convenience) {
            return "A convenience bid is effort-minimizing access-seeking — the 'u up' school of breadcrumbing. It tests your boundary instead of investing in you. A clear standard separates genuine interest from someone shopping for the easiest yes."
        }
        if signals.contains(.limitedIntent) {
            return "This is avoidant honesty: ambivalent people confess the ceiling early, then hope charm makes you forget it. The CBT move is to believe the evidence over the story you want. Don't promote potential over pattern."
        }
        if signals.contains(.noncommittal) {
            return "A 'maybe' keeps the door cracked so the sender feels polite while risking nothing. Your nervous system fills that gap with hope — name it as the non-answer it is and let follow-through, not words, decide."
        }
        if signals.contains(.busyFog) {
            return context == .work
                ? "Vagueness here protects the sender from ownership. Ask for the deadline, owner, and next action so the fog has to commit to a shape."
                : "Busyness is real; repeated vagueness is also real. Intermittent low-effort contact is classic breadcrumbing — the pattern matters more than any single excuse."
        }
        if signals.contains(.genuineInvestment) {
            return "Remembering details and acting on them is the behavioral profile of genuine interest. Secure partners don't just talk about you — they plan, follow through, and attune. That's the difference between interest and intent."
        }
        return "Your nervous system wants certainty, but the text only earned a small interpretation. Ask one clean question once, then watch the follow-through — behavior over vibes."
    }

    // MARK: - Suggested replies (boundary-setting, funny)

    private func replies(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> [String] {
        if signals.contains(.actualPlan) {
            return [
                "That works. Send the place and I'll be there.",
                "Cute. I'm in if the plan stays this specific.",
                "Yes, and I appreciate an actual time. Groundbreaking technology."
            ]
        }
        if signals.contains(.complianceTest) {
            return [
                "I save those for people who've earned them. What's the plan?",
                "How about we meet in person first? You pick the place.",
                "More of a 'show me your calendar' than 'show me your camera roll' kind of person."
            ]
        }
        if signals.contains(.gaslighting) {
            return [
                "I know what I read. Let's stick to the original transcript.",
                "If it was a joke, it missed. If it wasn't, we should talk about it.",
                "I don't need a translator. I need you to own what you said."
            ]
        }
        if signals.contains(.deflection) {
            return [
                "I'm not overthinking. I'm just reading what you wrote.",
                "My read is valid. Change what you do, not how I think.",
                "Let's stay on the page you wrote. No need to rewrite it."
            ]
        }
        if signals.contains(.commitmentDodge) {
            return [
                "Agreed — I do deserve better. So let's close this cleanly.",
                "Space is yours to take. Just know I'm not holding a spot.",
                "I'm not waiting on a maybe. Take your time; I'll be living mine."
            ]
        }
        if signals.contains(.loveBombing) {
            return [
                "Sweet. What day are we doing something about it?",
                "Love the words. Let me know when the calendar matches them.",
                tone == .spicy ? "Flattery is free. A dinner reservation is proof." : "Compliments are nice. A plan is nicer. Surprise me."
            ]
        }
        if signals.contains(.futureFaking) {
            return [
                "I don't book flights to 'eventually.' What does next week look like?",
                "Sounds nice. Put a date on it and I'm listening.",
                "I'm a plans person, not a 'someday' person. What day works?"
            ]
        }
        if signals.contains(.convenience) {
            return [
                "I'm not doing mystery drop-ins. Pick a real plan if you want to see me.",
                "Tonight isn't open-ended. Try me with a day, time, and plan.",
                tone == .spicy ? "That invite is giving bargain bin. Upgrade it." : "I like effort. What did you have in mind besides vague?"
            ]
        }
        if signals.contains(.limitedIntent) {
            return [
                "Thanks for being clear. I'm looking for more intention.",
                "I hear you. I'm not auditioning for a half-open door.",
                "No hard feelings. I'll put my energy where the plan is real."
            ]
        }
        if signals.contains(.validationSeeking) {
            return [
                "I'm good. If you want to see me, make a plan.",
                "Nothing's wrong. But 'are you mad' isn't 'let's get dinner.'",
                "I'm here. The question is whether you're showing up or just checking in."
            ]
        }
        if signals.contains(.selfDeprecationShield) {
            return [
                "That's for you to work on, not for me to accept as a discount.",
                "I appreciate the honesty. I'm still holding the standard.",
                "Vulnerability is great. Accountability is better. What are you doing about it?"
            ]
        }
        if context == .work {
            return [
                "Can you confirm the owner, deadline, and next step?",
                "I can help once the ask is specific. What outcome do you need?",
                "Please send the details in one thread so nothing gets lost."
            ]
        }
        return [
            "What does that look like as an actual plan?",
            "I'm free for clear plans, not fog machines.",
            "Say the quiet part in calendar form: day, time, place."
        ]
    }

    // MARK: - Receipts

    private func receipts(for signals: [Signal]) -> [String] {
        var values: [String] = []
        if signals.contains(.actualPlan) { values.append("Specific plan") }
        if signals.contains(.genuineInvestment) { values.append("Genuine effort") }
        if signals.contains(.warmth) { values.append("Warm language") }
        if signals.contains(.busyFog) { values.append("Busy fog") }
        if signals.contains(.lateRepair) { values.append("Late repair") }
        if signals.contains(.noncommittal) { values.append("Noncommittal wording") }
        if signals.contains(.convenience) { values.append("Convenience bid") }
        if signals.contains(.limitedIntent) { values.append("Low stated intent") }
        if signals.contains(.futureFaking) { values.append("Future faking") }
        if signals.contains(.loveBombing) { values.append("Love bombing") }
        if signals.contains(.validationSeeking) { values.append("Validation seeking") }
        if signals.contains(.lowEffortPing) { values.append("Low-effort ping") }
        if signals.contains(.deflection) { values.append("Deflection") }
        if signals.contains(.gaslighting) { values.append("Gaslighting") }
        if signals.contains(.commitmentDodge) { values.append("Soft exit") }
        if signals.contains(.selfDeprecationShield) { values.append("Preemptive excuse") }
        if signals.contains(.complianceTest) { values.append("Boundary test") }
        if values.isEmpty { values.append("Not enough data") }
        return values
    }

    // MARK: - Flags

    private func flags(for signals: [Signal]) -> [String] {
        var values: [String] = []
        if signals.contains(.actualPlan) { values.append("Actionable") }
        if signals.contains(.genuineInvestment) { values.append("Real effort") }
        if signals.contains(.convenience) { values.append("Low effort") }
        if signals.contains(.noncommittal) { values.append("Ambiguous") }
        if signals.contains(.limitedIntent) { values.append("Believe the disclaimer") }
        if signals.contains(.futureFaking) { values.append("No concrete plan") }
        if signals.contains(.loveBombing) { values.append("Words > actions") }
        if signals.contains(.validationSeeking) { values.append("Orbiting") }
        if signals.contains(.lowEffortPing) { values.append("Sonar ping") }
        if signals.contains(.deflection) { values.append("Invalidating") }
        if signals.contains(.gaslighting) { values.append("Rewriting reality") }
        if signals.contains(.commitmentDodge) { values.append("Exiting") }
        if signals.contains(.complianceTest) { values.append("Testing boundaries") }
        if signals.contains(.selfDeprecationShield) { values.append("Preemptive excuse") }
        return values
    }

    // MARK: - Reality score

    private func score(for signals: [Signal], context: DecodeContext) -> Int {
        var score = context == .work ? 58 : 52
        if signals.contains(.actualPlan) { score += 28 }
        if signals.contains(.genuineInvestment) { score += 20 }
        if signals.contains(.warmth) { score += 12 }
        if signals.contains(.busyFog) { score -= 12 }
        if signals.contains(.lateRepair) { score -= 8 }
        if signals.contains(.noncommittal) { score -= 18 }
        if signals.contains(.convenience) { score -= 24 }
        if signals.contains(.limitedIntent) { score -= 30 }
        if signals.contains(.futureFaking) { score -= 15 }
        if signals.contains(.loveBombing) { score -= 12 }
        if signals.contains(.validationSeeking) { score -= 8 }
        if signals.contains(.lowEffortPing) { score -= 10 }
        if signals.contains(.deflection) { score -= 20 }
        if signals.contains(.gaslighting) { score -= 25 }
        if signals.contains(.commitmentDodge) { score -= 28 }
        if signals.contains(.selfDeprecationShield) { score -= 14 }
        if signals.contains(.complianceTest) { score -= 22 }
        return min(100, max(0, score))
    }

    // MARK: - Energy

    private func energy(for score: Int) -> String {
        switch score {
        case 80...100: return "Green flag, grab your keys 🗝️"
        case 60..<80: return "Promising, keep your shoes on 👠"
        case 40..<60: return "Needs a receipt 🧾"
        case 20..<40: return "Crumb buffet 🍞"
        default: return "Protect your peace 🕊️"
        }
    }
}

private extension String {
    /// True if the string contains any of the given needles.
    func containsAny(_ needles: String...) -> Bool {
        needles.contains { contains($0) }
    }
}
