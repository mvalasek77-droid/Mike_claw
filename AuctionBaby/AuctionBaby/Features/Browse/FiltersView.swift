import SwiftUI

/// Floor filters. Age range is free; verified-only and interest matching
/// are a Pass perk — locked rows that open the store.
struct FiltersView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss
    @State private var showStore = false

    private var f: Binding<FilterPreferences> { $store.filters }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ageCard
                    premiumCard
                    reserveRequirementsCard
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { Motion.run(Motion.snap) { store.filters = FilterPreferences() } }
                        .foregroundStyle(Theme.inkSoft)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold).fontWeight(.bold)
                }
            }
            .sheet(isPresented: $showStore) { PaywallView(trigger: .filters) }
        }
    }

    private var ageCard: some View {
        GlassCard(title: "Age", icon: "calendar", tint: Theme.gold) {
            HStack {
                Text("\(store.filters.minAge) – \(store.filters.maxAge)")
                    .font(.scaled(18, weight: .heavy, design: .rounded, relativeTo: .body)).foregroundStyle(Theme.gold)
                Spacer()
            }
            VStack(spacing: 4) {
                HStack { Text("Min").font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint); Spacer() }
                Slider(value: Binding(get: { Double(store.filters.minAge) },
                                      set: { store.filters.minAge = min(Int($0), store.filters.maxAge) }),
                       in: 18...80, step: 1).tint(Theme.gold)
                HStack { Text("Max").font(.scaled(11, relativeTo: .caption2)).foregroundStyle(Theme.inkFaint); Spacer() }
                Slider(value: Binding(get: { Double(store.filters.maxAge) },
                                      set: { store.filters.maxAge = max(Int($0), store.filters.minAge) }),
                       in: 18...80, step: 1).tint(Theme.gold)
            }
        }
    }

    private var hasReserve: Bool {
        guard let tier = storeKit.activeTier else { return false }
        return tier == .reserve || tier == .blackcard
    }

    private var premiumCard: some View {
        GlassCard(title: "Advanced filters", icon: "slider.horizontal.3", tint: Theme.rose) {
            if !hasReserve {
                Button { showStore = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Unlock advanced filters with Reserve")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.scaled(13, weight: .bold, design: .rounded, relativeTo: .footnote)).foregroundStyle(Theme.rose)
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
            Toggle(isOn: Binding(
                get: { store.filters.verifiedOnly },
                set: { newValue in
                    if newValue && !hasReserve { showStore = true; return }
                    Motion.run(Motion.snap) { store.filters.verifiedOnly = newValue }
                }
            )) {
                Label("Verified profiles only", systemImage: "checkmark.seal.fill")
                    .font(.scaled(14, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.verify)
            .opacity(hasReserve || store.filters.verifiedOnly ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("MATCH INTERESTS").font(.scaled(10, weight: .bold, design: .rounded, relativeTo: .caption2))
                    .tracking(1).foregroundStyle(Theme.inkFaint)
                FlowChips(items: FilterPreferences.interestPool, selected: f.interests)
                    .disabled(!hasReserve)
                    .opacity(hasReserve ? 1 : 0.45)
            }
            if !hasReserve && store.filters.hasPremiumFilters {
                Button {
                    Motion.run(Motion.snap) {
                        store.filters.verifiedOnly = false
                        store.filters.interests = []
                        store.filters.minHeightCm = 0
                        store.filters.smokingRequirement = nil
                        store.filters.drinkingRequirement = nil
                        store.filters.kidsRequirement = nil
                        store.filters.educationRequirement = nil
                    }
                } label: {
                    Label("Clear premium filters", systemImage: "xmark.circle.fill")
                        .font(.scaled(12, weight: .bold, design: .rounded, relativeTo: .caption1))
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Reserve Requirements — dealbreaker filters, Reserve-tier perk. A stated
    /// mismatch removes the profile from the feed; unset fields on the target
    /// profile always pass (we don't punish incomplete profiles).
    private var reserveRequirementsCard: some View {
        GlassCard(title: "Reserve Requirements", icon: "checklist", tint: Theme.gold) {
            Text("Dealbreakers. Anyone whose profile clearly doesn't fit is hidden from the floor. Blank fields on a profile always pass.")
                .font(.scaled(11, relativeTo: .caption2))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            if !hasReserve {
                Button { showStore = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Unlock Reserve Requirements")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.scaled(13, weight: .bold, design: .rounded, relativeTo: .footnote)).foregroundStyle(Theme.gold)
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }

            heightRow.disabled(!hasReserve).opacity(hasReserve ? 1 : 0.45)
            enumRow(title: "Smoking", options: Lifestyle.Smoking.allCases,
                    binding: $store.filters.smokingRequirement)
                .disabled(!hasReserve).opacity(hasReserve ? 1 : 0.45)
            enumRow(title: "Drinking", options: Lifestyle.Drinking.allCases,
                    binding: $store.filters.drinkingRequirement)
                .disabled(!hasReserve).opacity(hasReserve ? 1 : 0.45)
            enumRow(title: "Kids", options: Lifestyle.Kids.allCases,
                    binding: $store.filters.kidsRequirement)
                .disabled(!hasReserve).opacity(hasReserve ? 1 : 0.45)
            enumRow(title: "Education", options: Lifestyle.Education.allCases,
                    binding: $store.filters.educationRequirement)
                .disabled(!hasReserve).opacity(hasReserve ? 1 : 0.45)
        }
    }

    private var heightRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Minimum height").font(.scaled(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(store.filters.minHeightCm == 0 ? "Any" : Self.formatHeight(store.filters.minHeightCm))
                    .font(.scaled(13, weight: .heavy, design: .rounded, relativeTo: .footnote))
                    .foregroundStyle(Theme.gold)
            }
            // 0 = "Any", 150cm–200cm range covered by the slider.
            Slider(value: Binding(
                get: { Double(store.filters.minHeightCm == 0 ? 149 : store.filters.minHeightCm) },
                set: { store.filters.minHeightCm = Int($0) <= 149 ? 0 : Int($0) }
            ), in: 149...200, step: 1).tint(Theme.gold)
        }
    }

    private func enumRow<Option: RawRepresentable & Identifiable & CaseIterable>(
        title: String, options: Option.AllCases, binding: Binding<Option?>
    ) -> some View where Option.RawValue == String {
        HStack {
            Text(title).font(.scaled(13, weight: .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            Spacer()
            Menu {
                Button("Any") { binding.wrappedValue = nil }
                ForEach(Array(options), id: \.id) { option in
                    Button(option.rawValue) { binding.wrappedValue = option }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(binding.wrappedValue?.rawValue ?? "Any")
                        .font(.scaled(13, weight: .heavy, design: .rounded, relativeTo: .footnote))
                    Image(systemName: "chevron.down").font(.scaled(9, weight: .bold, relativeTo: .caption2))
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.gold.opacity(0.14)))
            }
        }
    }

    private static func formatHeight(_ cm: Int) -> String {
        let totalInches = Double(cm) / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        return "\(feet)′\(inches)″ (\(cm) cm)"
    }
}
