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
        if lower.contains("crazy week") || lower.contains("so busy") || lower.contains("busy rn") || lower.contains("busy right now") {
            signals.append(.busyFog)
        }
        if lower.contains("maybe") || lower.contains("we'll see") || lower.contains("we will see") || lower.contains("idk") {
            signals.append(.noncommittal)
        }
        if lower.contains("come over") || lower.contains("u up") || lower.contains("you up") || lower.contains("wyd") {
            signals.append(.convenience)
        }
        if lower.contains("sorry just saw") || lower.contains("just saw this") || lower.contains("forgot to reply") {
            signals.append(.lateRepair)
        }
        if lower.contains("not ready") || lower.contains("not looking for") || lower.contains("go with the flow") {
            signals.append(.limitedIntent)
        }
        if lower.contains("miss you") || lower.contains("thinking of you") || lower.contains("want to see you") {
            signals.append(.warmth)
        }
        if hasActualPlan(lower) {
            signals.append(.actualPlan)
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
    }

    private func containsSafetySignal(_ text: String) -> Bool {
        let terms = ["hurt you", "kill", "threat", "hit me", "hit you", "stalk", "scared", "afraid", "self harm", "suicide"]
        return terms.contains { text.contains($0) }
    }

    private func hasActualPlan(_ text: String) -> Bool {
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "tonight", "tomorrow"]
        let planWords = ["dinner", "coffee", "drinks", "walk", "call", "meet", "reservation", "7", "8", "9"]
        return days.contains { text.contains($0) } && planWords.contains { text.contains($0) }
    }

    private func safetyResult(context: DecodeContext) -> DecodeResult {
        DecodeResult(
            headline: "This one leaves the joke drawer closed.",
            translation: "The message has threat or harm language. The useful read is not romance, manners, or office politics. It is safety.",
            psychology: "When someone uses intimidation, the priority is distance, documentation, and support from a trusted person or local emergency help if danger is immediate.",
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

    private func headline(for signals: [Signal], tone: DecodeTone) -> String {
        if signals.contains(.actualPlan) && signals.contains(.warmth) {
            return "There is a plan hiding under the cute. Rare species."
        }
        if signals.contains(.convenience) {
            return tone == .spicy ? "This smells like crumbs with cologne." : "This is low-effort interest wearing lip gloss."
        }
        if signals.contains(.limitedIntent) {
            return "They put the terms and conditions in tiny emotional font."
        }
        if signals.contains(.busyFog) && signals.contains(.lateRepair) {
            return "The calendar excuse has entered the chat."
        }
        if signals.contains(.noncommittal) {
            return "A maybe is a no wearing a tiny hat."
        }
        if signals.contains(.warmth) {
            return "There is warmth here, but make it buy a calendar."
        }
        return "The message is doing interpretive dance."
    }

    private func translation(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> String {
        if signals.contains(.actualPlan) {
            return "They are offering something measurable. Keep your standards awake, but this is more than vapor."
        }
        if signals.contains(.convenience) {
            return context == .dating
                ? "They may like access more than effort. Cute enough to text, not yet serious enough to plan."
                : "They want a quick yes without carrying the full ask."
        }
        if signals.contains(.limitedIntent) {
            return "They are telling you the ceiling is low. Believe the ceiling before you decorate the room."
        }
        if signals.contains(.busyFog) {
            return "They may be busy, but busy people still know nouns like day, time, and place."
        }
        if signals.contains(.noncommittal) {
            return "They are keeping the door cracked so they can feel polite while making no real promise."
        }
        if signals.contains(.lateRepair) {
            return "The apology is a coupon. Useful only if it can be redeemed for changed behavior."
        }
        if tone == .spicy {
            return "It is not a smoking clue, but it is also not a love letter. Call it boutique nonsense until more evidence arrives."
        }
        return "There is not enough clear effort yet. Ask one clean question and let the answer do the exposing."
    }

    private func psychology(for signals: [Signal], context: DecodeContext) -> String {
        if signals.contains(.actualPlan) {
            return "Specificity is a secure-attachment tell: it moves the interaction from fantasy to behavior, and behavior is the only receipt that counts. In Gottman's terms, a concrete plan is a clear bid for connection."
        }
        if signals.contains(.convenience) {
            return "A convenience bid is effort-minimizing access-seeking — the 'u up' school of breadcrumbing. It tests your boundary instead of investing in you. A clear standard separates genuine interest from someone shopping for the easiest yes."
        }
        if signals.contains(.limitedIntent) {
            return "This is avoidant honesty: ambivalent people confess the ceiling early, then hope charm makes you forget the confession. The CBT move is to believe the evidence over the story you want. Don't promote potential over pattern."
        }
        if signals.contains(.noncommittal) {
            return "A 'maybe' keeps the door cracked so the sender feels polite while risking nothing. Your nervous system fills that gap with hope — name it as the non-answer it is and let follow-through, not words, decide."
        }
        if signals.contains(.busyFog) {
            return context == .work
                ? "Vagueness here protects the sender from ownership. Ask for the deadline, owner, and next action so the fog has to commit to a shape."
                : "Busyness is real; repeated vagueness is also real. Intermittent low-effort contact is classic breadcrumbing — the pattern matters more than any single excuse."
        }
        return "Your nervous system wants certainty, but the text only earned a small interpretation. Ask one clean question once, then watch the follow-through — behavior over vibes."
    }

    private func replies(for signals: [Signal], tone: DecodeTone, context: DecodeContext) -> [String] {
        if signals.contains(.actualPlan) {
            return [
                "That works. Send the place and I will meet you there.",
                "Cute. I am in if the plan stays this clear.",
                "Yes, and I appreciate an actual time. Groundbreaking technology."
            ]
        }
        if signals.contains(.convenience) {
            return [
                "I am not doing mystery drop-ins. Pick a real plan if you want to see me.",
                "Tonight is not open-ended. Try me with a day, time, and plan.",
                tone == .spicy ? "That invite is giving bargain bin. Upgrade it." : "I like effort. What did you have in mind besides vague?"
            ]
        }
        if signals.contains(.limitedIntent) {
            return [
                "Thanks for being clear. I am looking for something with more intention.",
                "I hear you. I am not trying to audition for a half-open door.",
                "No hard feelings. I am going to put my energy where the plan is real."
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
            "I am free for clear plans, not fog machines.",
            "Say the quiet part in calendar form: day, time, place."
        ]
    }

    private func receipts(for signals: [Signal]) -> [String] {
        var values: [String] = []
        if signals.contains(.actualPlan) { values.append("Specific plan") }
        if signals.contains(.warmth) { values.append("Warm language") }
        if signals.contains(.busyFog) { values.append("Busy fog") }
        if signals.contains(.lateRepair) { values.append("Late repair") }
        if signals.contains(.noncommittal) { values.append("Noncommittal wording") }
        if signals.contains(.convenience) { values.append("Convenience bid") }
        if signals.contains(.limitedIntent) { values.append("Low stated intent") }
        if values.isEmpty { values.append("Not enough data") }
        return values
    }

    private func flags(for signals: [Signal]) -> [String] {
        var values: [String] = []
        if signals.contains(.convenience) { values.append("Low effort") }
        if signals.contains(.noncommittal) { values.append("Ambiguous") }
        if signals.contains(.limitedIntent) { values.append("Believe the disclaimer") }
        if signals.contains(.actualPlan) { values.append("Actionable") }
        return values
    }

    private func score(for signals: [Signal], context: DecodeContext) -> Int {
        var score = context == .work ? 58 : 52
        if signals.contains(.actualPlan) { score += 28 }
        if signals.contains(.warmth) { score += 12 }
        if signals.contains(.busyFog) { score -= 12 }
        if signals.contains(.lateRepair) { score -= 8 }
        if signals.contains(.noncommittal) { score -= 18 }
        if signals.contains(.convenience) { score -= 24 }
        if signals.contains(.limitedIntent) { score -= 30 }
        return min(100, max(0, score))
    }

    private func energy(for score: Int) -> String {
        switch score {
        case 80...100: return "Clear enough to leave the house"
        case 60..<80: return "Promising, but keep shoes on"
        case 40..<60: return "Needs a receipt"
        case 20..<40: return "Crumb buffet"
        default: return "Protect the peace"
        }
    }
}
