import SwiftUI

struct ResourcesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("If your child is in immediate danger, call 911 (or your local emergency number).")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                Section("Reporting & guidance") {
                    ForEach(store.resources) { resource in
                        if let url = URL(string: resource.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(resource.title)
                                        .font(.subheadline.weight(.medium))
                                    Text(resource.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Get Help")
        }
    }
}
