import SwiftUI

/// Posts a new buy/sell/trade listing to the Bro-ket.
struct CreateListingView: View {
    @State private var model: CreateListingViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Listing) -> Void

    init(service: MarketplaceService, onCreated: @escaping (Listing) -> Void) {
        _model = State(initialValue: CreateListingViewModel(service: service))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Listing") {
                    TextField("Title", text: $model.title)
                    TextField("Description (optional)", text: $model.description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Price", text: $model.priceText)
                        .keyboardType(.decimalPad)
                }
                Section("Category") {
                    Picker("Category", selection: $model.category) {
                        ForEach(ListingCategory.allCases, id: \.self) { category in
                            Text(category.label).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if case .failed(let message) = model.submitState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let listing = await model.submit() {
                                onCreated(listing)
                                dismiss()
                            }
                        }
                    } label: {
                        if model.submitState == .submitting {
                            ProgressView()
                        } else {
                            Text("Post").fontWeight(.bold)
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
        }
    }
}
