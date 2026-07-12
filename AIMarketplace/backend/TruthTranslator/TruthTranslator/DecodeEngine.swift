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

        // ── Effort & Investment Signals ──
        if lower.contains("crazy week") || lower.contains("so busy") || lower.contains("busy rn") || lower.contains("busy right now") || lower.contains("insane right now") || lower.contains("swamped") || lower.contains("overwhelmed") {
            signals.append(.busyFog)
        }
        if lower.contains("maybe") || lower.contains("we'll see") || lower.contains("we will see") || lower.contains("idk") || lower.contains("i guess") || lower.contains("i suppose") || lower.contains("possibly") || lower.contains("probably") || lower.contains("might") || lower.contains("could be") {
            signals.append(.noncommittal)
        }
        if lower.contains("come over") || lower.contains("u up") || lower.contains("you up") || lower.contains("wyd") || lower.contains("what are you doing") || lower.contains("come thru") || lower.contains("swing by") || lower.contains("pull up") || lower.contains("stop by") || lower.contains("wya") || lower.contains("where you at") {
            signals.append(.convenience)
        }
        if lower.contains("sorry just saw") || lower.contains("just saw this") || lower.contains("forgot to reply") || lower.contains("phone died") || lower.contains("was asleep") || lower.contains("didn't see") || lower.contains("notifications off") || lower.contains("my bad") || lower.contains("lost my phone") {
            signals.append(.lateRepair)
        }
        if lower.contains("not ready") || lower.contains("not looking for") || lower.contains("go with the flow") || lower.contains("see where this goes") || lower.contains("no pressure") || lower.contains("no labels") || lower.contains("keep it casual") || lower.contains("don't want to rush") || lower.contains("take it slow") || lower.contains("not trying to") || lower.contains("just having fun") {
            signals.append(.limitedIntent)
        }
        if hasActualPlan(lower) {
            signals.append(.actualPlan)
        }
        if lower.contains("miss you") || lower.contains("thinking of you") || lower.contains("want to see you") || lower.contains("can't stop thinking") || lower.contains("been thinking about you") || lower.contains("wish you were here") {
            signals.append(.warmth)
        }

        // ── Future Faking & Breadcrumbing ──
        if lower.contains("soon") || lower.contains("eventually") || lower.contains("one day") || lower.contains("down the road") || lower.contains("someday") || lower.contains("at some point") || lower.contains("when things calm down") || lower.contains("after this week") || lower.contains("next time") || lower.contains("let's plan") || lower.contains("we should definitely") {
            if !hasActualPlan(lower) {
                signals.append(.futureFaking)
            }
        }

        // ── Validation Seeking / Hot & Cold ──
        if lower.contains("i miss") || lower.contains("do you miss") || lower.contains("you mad") || lower.contains("are you mad") || lower.contains("what's wrong") || lower.contains("talk to me") || lower.contains("don't ignore") || lower.contains("you're ignoring") || lower.contains("why aren't you") || lower.contains("still there") {
            signals.append(.validationSeeking)
        }
        if (lower.contains("hey") && trimmed.count < 10) || lower.contains("just checking") || lower.contains("how are you") || lower.contains("what's up") || lower.contains("wyd") {
            if !hasActualPlan(lower) {
                signals.append(.lowEffortPing)
            }
        }

        // ── Intimacy Escalation Without Investment ──
        if lower.contains("beautiful") || lower.contains("gorgeous") || lower.contains("stunning") || lower.contains("so hot") || lower.contains("sexy") || lower.contains("incredible body") || lower.contains("look amazing") || lower.contains("obsessed with you") || lower.contains("can't get enough") {
            if !hasActualPlan(lower) && !signals.contains(.actualPlan) {
                signals.append(.loveBombing)
            }
        }

        // ── Deflection & Avoidance ──
        if lower.contains("you're overthinking") || lower.contains("relax") || lower.contains("chill") || lower.contains("it's not that deep") || lower.contains("why are you like this") || lower.contains("you're too much") || lower.contains("dramatic") || lower.contains("sensitive") || lower.contains("insecure") || lower.contains("crazy") || lower.contains("psycho") || lower.contains("jealous") {
            signals.append(.deflection)
        }
        if lower.contains("i didn't mean") || lower.contains("it was a joke") || lower.contains("you took that wrong") || lower.contains("that's not what") || lower.contains("i was just saying") || lower.contains("don't take it") || lower.contains("misunderstood") {
            signals.append(.gaslighting)
        }

        // ── Commitment Dodging ──
        if lower.contains("i need space") || lower.contains("need some time") || lower.contains("figure myself out") || lower.contains("right now") || lower.contains("at this point") || lower.contains("where i'm at") || lower.contains("not in a place") || lower.contains("can't give you") || lower.contains("you deserve better") || lower.contains("don't want to hurt you") {
            signals.append(.commitmentDodge)
        }

        // ── Genuine Interest Markers ──
        if lower.contains("i'd love to") || lower.contains("let me take you") || lower.contains("i want to take you") || lower.contains("made a reservation") || lower.contains("picked out") || lower.contains("thought of you when") || lower.contains("saw this and thought") || lower.contains("reminded me of you") || lower.contains("how was your") || lower.contains("how did it go") {
            signals.append(.genuineInvestment)
        }

        // ── Emotional Unavailability Signals ──
        if lower.contains("i'm not good at") || lower.contains("bad at this") || lower.contains("bad at relationships") || lower.contains("not good with") || lower.contains("i'm damaged") || lower.contains("broken") || lower.contains("fucked up") || lower.contains("messed up") || lower.contains("not relationship material") {
            signals.append(.selfDeprecationShield)
        }

        // ── Compliance Testing ──
        if lower.contains("send me") || lower.contains("send a") || lower.contains("show me") || lower.contains("let me see") || lower.contains("picture") || lower.contains("pic") || lower.contains("selfie") || lower.contains("snap") || lower.contains("proof") {
            if !hasActualPlan(lower) {
                signals.append(.complianceTest)
            }
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

    // MARK: - Signal Types (expanded with research-backed patterns)

    private enum Signal {
        case actualPlan
        case ambiguous
        case busyFog
        case convenience
        case lateRepair
        case limitedIntent
        case noncommittal
        case warmth
        case futureFaking        // "soon" "eventually" — no concrete plan
        case validationSeeking   // "you mad?" "still there?" — orbiting
        case lowEffortPing       // "hey" "wyd" — checking if you're still available
        case loveBombing         // excessive compliments with zero logistical effort
        case deflection         // "you're overthinking" — invalidating your valid read
        case gaslighting         // "it was a joke" "you took that wrong"
        case commitmentDodge     // "I need space" "you deserve better" — soft exit
        case genuineInvestment   // "I'd love to" "made a reservation" — real effort
        case selfDeprecationShield // "I'm not good at relationships" — preemptive excuse
        case complianceTest      // "send me a pic" — testing your boundaries
    }

    private func containsSafetySignal(_ text: String) -> Bool {
        let terms = ["hurt you", "kill", "threat", "hit me", "hit you", "stalk", "scared", "afraid", "self harm", "suicide", "rape", "force", "weapon"]
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
            translation: "The message has threat or harm language. This isn't a dating read — it's a safety read.",
            psychology: "When someone uses intimidation, your nervous system is giving you correct data. Distance, documentation, and real support come before any conversation about the relationship.",
            receipts: ["Threat language", "Safety first", "Do not debate your way into clarity"],
            suggestedReplies: [
                "I am not continuing this conversation.",
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
        // Compound signals first
        if signals.contains(.actualPlan) && signals.contains(.warmth) {
            return "He brought both the charm and the calendar. Unicorns exist."
        }
        if signals.contains(.loveBombing) && signals.contains(.convenience) {
            return "He's serving compliments for breakfast and crumbs for dinner."
        }
        if signals.contains(.deflection) && signals.contains(.gaslighting) {
            return "He's running the emotional Three-Card Monte."
        }
        if signals.contains(.futureFaking) && signals.contains(.busyFog) {
            return "The calendar is always full but the schedule is always empty."
        }
        if signals.contains(.validationSeeking) && signals.contains(.lowEffortPing) {
            return "He's checking if you're still in the waiting room."
        }
        if signals.contains(.selfDeprecationShield) && signals.contains(.commitmentDodge) {
            return "He handed you the disclaimer before you even asked for the contract."
        }
        if signals.contains(.complianceTest) {
            return "He's auditioning you, not dating you."
        }

        // Single signals
        if signals.contains(.actualPlan) {
            return "An actual plan. In this economy? Groundbreaking."
        }
        if signals.contains(.convenience) {
            return tone == .spicy ? "This smells like cologne over crumbs." : "He wants the room key, not the dinner reservation."
        }
        if signals.contains(.limitedIntent) {
            return "He put the terms and conditions in tiny emotional font."
        }
        if signals.contains(.busyFog) && signals.contains(.lateRepair) {
            return "The calendar excuse has entered the chat — fashionably late, naturally."
        }
        if signals.contains(.noncommittal) {
            return "A maybe is a no wearing a tiny hat."
        }
        if signals.contains(.warmth) {
            return "There's warmth here, but warmth without a plan is just a space heater."
        }
        if signals.contains(.futureFaking) {
            return "He's selling you a timeshare in a country that doesn't exist yet."
        }
        if signals.contains(.loveBombing) {
            return "The words are sweet. The calendar is empty. Do the math."
        }
        if signals.contains(.deflection) {
            return "He just told you your spidey sense is broken. Your spidey sense is fine."
        }
        if signals.contains(.gaslighting) {
            return "He's editing the replay and hoping you don't have DVR."
        }
        if signals.contains(.commitmentDodge) {
            return "He's leaving through the door he pretends isn't there."
        }
        if signals.contains(.validationSeeking) {
            return "He wants to know you're still waiting. He's not offering a reason to."
        }
        if signals.contains(.lowEffortPing) {
            return "That's not a text. That's a sonar ping."
        }
        if signals.contains(.selfDeprecationShield) {
            return "He pre-loaded the excuse so you'd feel bad for having a standard."
        }
        if signals.contains(.genuineInvestment) {
            return "This one brought receipts, not vibes."
        }
        return "The message is doing interpretive dance. Ask it to speak in sentences."
    }

    // MARK: - Translations (blunt, crude-ish, funny)

    private func translation(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> String {
        if signals.contains(.actualPlan) {
            return "He's offering something measurable. A man with a plan is a man with intent. Keep your standards awake, but this is more than vapor."
        }
        if signals.contains(.loveBombing) && signals.contains(.convenience) {
            return "He's using compliments as cover. The flattery gets your guard down, the late-night text gets him access. The question isn't whether he likes you — it's what he's willing to do about it."
        }
        if signals.contains(.convenience) {
            return context == .dating
                ? "He wants the benefits without the logistics. Cute enough to text at midnight, not serious enough to book a table at 7."
                : "They want a quick yes without carrying the full ask."
        }
        if signals.contains(.limitedIntent) {
            return "He's telling you the ceiling is low. Men who mean it show it with a plan. Men who don't, show it with a disclaimer. Believe the disclaimer."
        }
        if signals.contains(.busyFog) {
            return "He may be busy. Busy people still know nouns like day, time, and place. If he wanted to see you, he'd know when. The question wrote itself."
        }
        if signals.contains(.noncommittal) {
            return "He's keeping the door cracked so he can feel polite while making zero promises. A maybe is just a no that's too polite to look you in the eye."
        }
        if signals.contains(.lateRepair) {
            return "The apology is a coupon. Useful only if it can be redeemed for changed behavior. Otherwise it's just a coupon for more coupons."
        }
        if signals.contains(.futureFaking) {
            return "He's painting a beautiful picture of a future he has no intention of building. 'Soon' is the most loaded three-letter word in dating. It means 'not now' and 'not committed.'"
        }
        if signals.contains(.loveBombing) {
            return "Men who move fast with words often move slow with actions. The compliment tsunami feels amazing — but watch where the calendar is. If it's empty, the words are just the appetizer with no main course planned."
        }
        if signals.contains(.deflection) {
            return "He just tried to make your valid observation the problem. 'You're overthinking' is how men avoid being held accountable for what they actually wrote. Read it again — your read is correct."
        }
        if signals.contains(.gaslighting) {
            return "He's rewriting the scene and hoping you'll forget what actually happened. 'It was a joke' is the universal translator for 'I meant it and I don't want to own it.'"
        }
        if signals.contains(.commitmentDodge) {
            return "He's giving you a graceful exit disguised as self-awareness. 'You deserve better' is him agreeing with you. 'I need space' is him needing the exit. 'I'm not ready' means he's ready — just not for you. Take the hint and save the receipt."
        }
        if signals.contains(.validationSeeking) {
            return "He's checking whether you're still on the hook. A man who wants you doesn't need to ask if you're mad — he's too busy making a plan to fix it. The question is the plan."
        }
        if signals.contains(.lowEffortPing) {
            return "He's testing if you're still available without making himself available. A 'hey' with no plan is a fishing line with no bait — he's hoping you'll bait your own hook."
        }
        if signals.contains(.selfDeprecationShield) {
            return "He's telling you upfront that he's going to disappoint you, but framing it as vulnerability so you feel bad for having expectations. It's not a confession — it's a pre-emptive 'I told you so.'"
        }
        if signals.contains(.complianceTest) {
            return "He's testing your boundaries, not your beauty. Men who are genuinely interested don't ask for digital proof before they've earned the right to see you in person. The request is the red flag, not your hesitation."
        }
        if signals.contains(.genuineInvestment) {
            return "This is what effort looks like. He's not just saying nice things — he's doing them. The difference between a man who's interested and a man who's serious is a calendar entry."
        }
        if tone == .spicy {
            return "Not a smoking clue, but not a love letter either. Call it boutique nonsense until the receipts arrive."
        }
        return "Not enough clear effort yet. Ask one clean question and let the answer do the exposing."
    }

    // MARK: - Psychology (research-backed, therapy-informed)

    private func psychology(for signals: [Signal], context: DecodeContext) -> String {
        // Compound insights
        if signals.contains(.loveBombing) && signals.contains(.convenience) {
            return "Research shows men pursuing short-term mating strategies use exaggerated flattery to accelerate intimacy while minimizing investment (Buss & Schmitt, 1993). The compliments trigger your dopamine reward system, making you less likely to notice the logistical void. Therapists call this 'intermittent reinforcement' — it's the same pattern that makes slot machines addictive."
        }
        if signals.contains(.deflection) && signals.contains(.gaslighting) {
            return "Deflection and gaslighting are forms of 'reactive abuse' setup — he provokes, you react, he blames your reaction. Gottman's research identifies contempt and defensiveness as two of the four relationship-killers. When he says 'you're overthinking,' he's making your reality the problem instead of his behavior."
        }
        if signals.contains(.futureFaking) {
            return "Evolutionary psychology calls this 'future faking' — describing a shared future to secure present compliance. Men seeking short-term access learned that women's long-term mating strategy values commitment cues (Buss, 2016). The verbal promise costs nothing; the follow-through costs effort. Your brain processes the promise as real until evidence proves otherwise — that's the gap he's exploiting."
        }
        if signals.contains(.validationSeeking) {
            return "This is 'orbiting' — maintaining proximity without investment. Research on mate-guarding shows men monitor former partners' availability while avoiding the effort that real reconnection requires. He's not trying to fix it. He's checking if the door is still unlocked."
        }
        if signals.contains(.selfDeprecationShield) {
            return "Therapists call this 'preemptive self-deprecation' — lowering expectations before you can be disappointed. It's a manipulation shield: if he fails, he already warned you. In attachment theory, this maps to dismissive-avoidant patterns where vulnerability is performed but not practiced. He's not being honest — he's filing the paperwork for future plausible deniability."
        }
        if signals.contains(.complianceTest) {
            return "This is a boundary test from social psychology's 'compliance ladder' — small requests that escalate. Men who ask for photos before they've invested time, effort, or planning are screening for low resistance. Research on sexual coercion patterns shows boundary testing starts small and normalizes incrementally. Your 'no' is data about your standards, and his reaction to it is data about his character."
        }

        // Single signal insights
        if signals.contains(.actualPlan) {
            return "Specificity is the behavioral signature of genuine intent. Research shows that men who transition from short-term to long-term mating strategies shift from vague enthusiasm to concrete planning (Kenrick et al., 2010). A plan moves the interaction from fantasy to behavior. Behavior is the receipt — everything else is marketing."
        }
        if signals.contains(.convenience) {
            return "Convenience bids test your boundaries without testing his effort. Research on 'minimal investment theory' shows that men pursuing short-term mating use the lowest-cost strategy that still works (Buss, 2016). If you say yes to a 2am text, he learns that your threshold is the floor. The boundary you set now teaches him the investment level you require."
        }
        if signals.contains(.limitedIntent) {
            return "Men who verbalize low intent are doing you a favor — research shows they often mean exactly what they say (Haselton & Buss, 2000). The 'positive illusion bias' makes women hear 'for now' as 'not yet.' Ambivalent partners confess early, then hope charm makes you forget the confession. Do not promote potential over pattern."
        }
        if signals.contains(.busyFog) {
            return context == .work
                ? "Work ambiguity often protects the sender from ownership. Ask for the deadline, owner, and next action."
                : "Busyness is real. Repeated vagueness is also real. Research on 'investment model' (Rusbult, 1980) shows that men allocate time proportional to commitment. If he's too busy to plan, he's telling you where you rank. The pattern matters more than the excuse."
        }
        if signals.contains(.noncommittal) {
            return "Men's short-term mating strategy uses ambiguity to maintain access without commitment (Buss & Schmitt, 1993). Your brain's 'filling-in effect' completes the gap with hope — but the gap IS the information. Therapists call it 'cognitive reappraisal': you're rewriting his maybe into a yes because that feels better than the truth."
        }
        if signals.contains(.loveBombing) {
            return "Excessive early flattery activates your attachment system before trust has been earned. Research on 'love bombing' shows it's a short-term mating tactic where exaggerated investment signals override your risk assessment (Carter, 2021). The words feel like proof of depth, but depth is demonstrated through consistency, not intensity."
        }
        if signals.contains(.deflection) {
            return "'You're overthinking' is a conversational power move. Research on 'minimization' in abusive dynamics shows that invalidating someone's perception is the first step toward making them doubt their own reality. Your spidey sense developed over millions of years of social cognition — trust it over his reassurance."
        }
        if signals.contains(.gaslighting) {
            return "Gaslighting exploits your 'conflict aversion bias' — most people prefer to believe they misunderstood rather than confront manipulation. Gottman's research shows that successful relationships require partners who 'accept influence.' A man who rewrites the interaction to avoid accountability is doing the opposite."
        }
        if signals.contains(.commitmentDodge) {
            return "Men who say 'you deserve better' are agreeing with you. Research on 'mate switching' (Buss, 2017) shows that when men want to exit, they often frame it as self-sacrifice rather than preference. 'I need space' means he's already halfway out the door — he just wants you to hold it open in case he changes his mind."
        }
        if signals.contains(.lowEffortPing) {
            return "Low-effort pings exploit your 'reciprocity bias' — a 'hey' triggers your impulse to re-engage. Research on 'pursuit-retreat' cycles shows that inconsistent attention is more addictive than consistent attention. He's not starting a conversation. He's confirming you're still on standby."
        }
        if signals.contains(.genuineInvestment) {
            return "This matches the behavioral profile of genuine long-term mating interest: specificity, planning, and emotional attunement (Buss, 2016). Research shows that men who are genuinely interested don't just talk about you — they remember details, make plans, and follow through. The difference between interest and intent is always a calendar entry."
        }
        if signals.contains(.warmth) {
            return "Warmth without a plan is like a house with a fireplace and no walls. Your attachment system lights up at affection signals, but research shows that sustained warmth needs logistical follow-through to mean what it feels like. Enjoy the warmth, but ask to see the building permit."
        }
        return "Your nervous system wants certainty, but the text only earned a small interpretation. The research is clear: one clean question reveals more than ten readings. Ask for clarity once, then watch what he does, not what he says."
    }

    // MARK: - Suggested Replies (funny, blunt, boundary-setting)

    private func replies(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> [String] {
        if signals.contains(.actualPlan) && signals.contains(.warmth) {
            return [
                "That works. Send the place and I'll be there.",
                "Cute. I'm in if the plan stays this specific.",
                "Yes, and I appreciate an actual time. Groundbreaking technology."
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
                "Thanks for being clear. I'm looking for something with more intention.",
                "I hear you. I'm not trying to audition for a half-open door.",
                "No hard feelings. I'm going to put my energy where the plan is real."
            ]
        }
        if signals.contains(.futureFaking) {
            return [
                "I don't book flights to 'eventually.' What does next week look like?",
                "That sounds nice. Put a date on it and I'm listening.",
                "I'm a plans girl, not a 'someday' girl. What day works?"
            ]
        }
        if signals.contains(.loveBombing) {
            return [
                "Sweet. What day are we doing something about it?",
                "I love the words. Let me know when the calendar matches them.",
                tone == .spicy ? "Flattery is free. A dinner reservation is proof." : "Compliments are nice. A plan is nicer. Surprise me with one."
            ]
        }
        if signals.contains(.deflection) {
            return [
                "I'm not overthinking. I'm just reading what you wrote.",
                "My read is valid. But if you want to change it, change what you do, not how I think.",
                "Let's stay on the page you wrote. No need to rewrite."
            ]
        }
        if signals.contains(.gaslighting) {
            return [
                "I know what I read. Let's both stick to the original transcript.",
                "I don't need a translator. I need you to own what you said.",
                "If it was a joke, it missed. If it wasn't, we should talk about it."
            ]
        }
        if signals.contains(.commitmentDodge) {
            return [
                "I agree. I do deserve better. So let's close this chapter cleanly.",
                "Space is yours to take. Just know I'm not holding a spot.",
                "I'm not waiting for a maybe. Take all the time you need — I'll be living mine."
            ]
        }
        if signals.contains(.validationSeeking) {
            return [
                "I'm good. If you want to see me, make a plan.",
                "Nothing's wrong. But 'are you mad' isn't the same as 'let's get dinner.'",
                "I'm here. The question is whether you're showing up or just checking in."
            ]
        }
        if signals.contains(.lowEffortPing) {
            return [
                "Hey! What's the plan?",
                "Alive and well. What did you have in mind?",
                tone == .spicy ? "You rang?" : "Hey! Got something fun for us or just pinging?"
            ]
        }
        if signals.contains(.selfDeprecationShield) {
            return [
                "That's for you to work on, not for me to accept as a relationship discount.",
                "I appreciate the honesty. I'm still going to hold the standard.",
                "Vulnerability is great. Accountability is better. What are you doing about it?"
            ]
        }
        if signals.contains(.complianceTest) {
            return [
                "I save those for people who've earned them. What's the plan?",
                "How about we meet in person first? You pick the place.",
                "I'm more of a 'show me your calendar' than 'show me your camera roll' kind of girl."
            ]
        }
        if signals.contains(.actualPlan) {
            return [
                "That works. Send the place and I'll meet you there.",
                "Cute. I'm in if the plan stays this clear.",
                "Yes, and I appreciate an actual time. Groundbreaking technology."
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
        if signals.contains(.noncommittal) { values.append("Noncommittal") }
        if signals.contains(.convenience) { values.append("Convenience bid") }
        if signals.contains(.limitedIntent) { values.append("Low stated intent") }
        if signals.contains(.futureFaking) { values.append("Future faking") }
        if signals.contains(.loveBombing) { values.append("Love bombing") }
        if signals.contains(.validationSeeking) { values.append("Validation seeking") }
        if signals.contains(.lowEffortPing) { values.append("Low effort ping") }
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
        if signals.contains(.convenience) { values.append("Low effort") }
        if signals.contains(.noncommittal) { values.append("Ambiguous") }
        if signals.contains(.limitedIntent) { values.append("Believe the disclaimer") }
        if signals.contains(.actualPlan) { values.append("Actionable") }
        if signals.contains(.futureFaking) { values.append("No concrete plan") }
        if signals.contains(.loveBombing) { values.append("Words > Actions") }
        if signals.contains(.deflection) { values.append("Invalidating") }
        if signals.contains(.gaslighting) { values.append("Rewriting reality") }
        if signals.contains(.commitmentDodge) { values.append("Exiting") }
        if signals.contains(.complianceTest) { values.append("Testing boundaries") }
        if signals.contains(.selfDeprecationShield) { values.append("Preemptive excuse") }
        if signals.contains(.genuineInvestment) { values.append("Real effort") }
        return values
    }

    // MARK: - Reality Score

    private func score(for signals: [Signal], context: DecodeContext) -> Int {
        var score = context == .work ? 58 : 52
        if signals.contains(.actualPlan) { score += 28 }
        if signals.contains(.genuineInvestment) { score += 20 }
        if signals.contains(.warmth) { score += 10 }
        if signals.contains(.busyFog) { score -= 12 }
        if signals.contains(.lateRepair) { score -= 8 }
        if signals.contains(.noncommittal) { score -= 18 }
        if signals.contains(.convenience) { score -= 24 }
        if signals.contains(.limitedIntent) { score -= 30 }
        if signals.contains(.futureFaking) { score -= 15 }
        if signals.contains(.loveBombing) { score -= 12 }
        if signals.contains(.deflection) { score -= 20 }
        if signals.contains(.gaslighting) { score -= 25 }
        if signals.contains(.commitmentDodge) { score -= 28 }
        if signals.contains(.validationSeeking) { score -= 8 }
        if signals.contains(.lowEffortPing) { score -= 10 }
        if signals.contains(.selfDeprecationShield) { score -= 14 }
        if signals.contains(.complianceTest) { score -= 22 }
        return min(100, max(0, score))
    }

    // MARK: - Energy

    private func energy(for score: Int) -> String {
        switch score {
        case 80...100: return "Clear enough to leave the house 💅"
        case 60..<80: return "Promising, but keep shoes on 👠"
        case 40..<60: return "Needs a receipt 🧾"
        case 20..<40: return "Crumb buffet 🍞"
        default: return "Protect the peace 🕊️"
        }
    }
}