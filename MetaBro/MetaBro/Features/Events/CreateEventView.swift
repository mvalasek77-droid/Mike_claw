import SwiftUI

/// Spin up a real-world meetup, optionally hosted by one of your Bro-hoods.
struct CreateEventView: View {
    @State private var model: CreateEventViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Event) -> Void

    init(eventService: EventService, communityService: CommunityService, onCreated: @escaping (Event) -> Void) {
        _model = State(initialValue: CreateEventViewModel(service: eventService, communityService: communityService))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What's happening?") {
                    TextField("Title", text: $model.title)
                    TextEditor(text: $model.details)
                        .frame(minHeight: 100)
                }
                Section("When & where") {
                    DatePicker("Starts", selection: $model.startDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    TextField("Location", text: $model.location)
                }
                Section("Hosting Bro-hood (optional)") {
                    Picker("Bro-hood", selection: $model.community) {
                        Text("None — just you").tag(Community?.none)
                        ForEach(model.communities) { community in
                            Text(community.name).tag(Community?.some(community))
                        }
                    }
                }
                if case .failed(let message) = model.submitState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if let event = await model.submit() {
                                onCreated(event)
                                dismiss()
                            }
                        }
                    } label: {
                        if model.submitState == .submitting {
                            ProgressView()
                        } else {
                            Text("Create").fontWeight(.bold)
                        }
                    }
                    .disabled(!model.canSubmit)
                }
            }
        }
        .task { await model.loadCommunities() }
    }
}
