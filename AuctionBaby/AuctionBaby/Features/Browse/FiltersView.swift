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
                    .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                Spacer()
            }
            VStack(spacing: 4) {
                HStack { Text("Min").font(.system(size: 11)).foregroundStyle(Theme.inkFaint); Spacer() }
                Slider(value: Binding(get: { Double(store.filters.minAge) },
                                      set: { store.filters.minAge = min(Int($0), store.filters.maxAge) }),
                       in: 18...80, step: 1).tint(Theme.gold)
                HStack { Text("Max").font(.system(size: 11)).foregroundStyle(Theme.inkFaint); Spacer() }
                Slider(value: Binding(get: { Double(store.filters.maxAge) },
                                      set: { store.filters.maxAge = max(Int($0), store.filters.minAge) }),
                       in: 18...80, step: 1).tint(Theme.gold)
            }
        }
    }

    private var premiumCard: some View {
        GlassCard(title: "Advanced filters", icon: "slider.horizontal.3", tint: Theme.rose) {
            if !storeKit.hasPass {
                Button { showStore = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("Unlock advanced filters with a Pass")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.rose)
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
            Toggle(isOn: f.verifiedOnly.animation(Motion.snap)) {
                Label("Verified profiles only", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            .tint(Theme.verify)
            .disabled(!storeKit.hasPass)
            .opacity(storeKit.hasPass ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 8) {
                Text("MATCH INTERESTS").font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1).foregroundStyle(Theme.inkFaint)
                FlowChips(items: FilterPreferences.interestPool, selected: f.interests)
                    .disabled(!storeKit.hasPass)
                    .opacity(storeKit.hasPass ? 1 : 0.45)
            }
        }
    }
}
