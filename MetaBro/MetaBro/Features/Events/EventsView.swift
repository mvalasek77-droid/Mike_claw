import SwiftUI

/// Real-world Bro-hood meetups: upcoming first, then past. RSVP and add to
/// your calendar from the card; the + button spins up a new one.
struct EventsView: View {
    private let container: AppContainer
    @State private var model: EventsViewModel
    @State private var showingCreate = false
    @State private var calendarToast: String?
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: EventsViewModel(service: container.eventService))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Events")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create event")
                    }
                }
                .sheet(isPresented: $showingCreate) {
                    CreateEventView(eventService: container.eventService,
                                    communityService: container.communityService) { event in
                        model.created(event)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let calendarToast {
                        Text(calendarToast)
                            .font(Tokens.Typography.caption.weight(.semibold))
                            .padding(.horizontal, Tokens.Spacing.lg)
                            .padding(.vertical, Tokens.Spacing.sm)
                            .liquidGlass(radius: Tokens.Radius.pill)
                            .padding(.bottom, Tokens.Spacing.lg)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No events yet", systemImage: "calendar",
                                   description: Text("Spin up a meetup with the + button."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let events):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.lg) {
                    ForEach(events) { event in
                        EventCard(
                            event: event,
                            onRSVP: { status in Task { await model.rsvp(event, status: status) } },
                            onAddToCalendar: { Task { await addToCalendar(event) } }
                        )
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: events)
            }
            .refreshable { await model.load() }
        }
    }

    private func addToCalendar(_ event: Event) async {
        let result = await CalendarExporter.add(event)
        let message: String
        switch result {
        case .added: message = "Added to your calendar"
        case .denied: message = "Calendar access denied — enable it in Settings"
        case .failed: message = "Couldn't add to your calendar"
        }
        withAnimation(Tokens.Motion.gentle) { calendarToast = message }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation(Tokens.Motion.gentle) { calendarToast = nil }
    }
}

private struct EventCard: View {
    let event: Event
    let onRSVP: (RSVPStatus) -> Void
    let onAddToCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            header
            Text(event.title)
                .font(Tokens.Typography.headline)
                .foregroundStyle(Tokens.Color.textPrimary)
            if !event.details.isEmpty {
                Text(event.details)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(3)
            }
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "mappin.and.ellipse")
                Text(event.location)
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(Tokens.Color.textSecondary)

            footer
        }
        .padding(Tokens.Spacing.lg)
        .liquidGlass()
        .opacity(event.isPast ? 0.6 : 1)
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            UserAvatar(user: event.host, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let community = event.community {
                    Text(community.name)
                        .font(Tokens.Typography.caption.weight(.semibold))
                }
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            Text("\(event.attendeeCount) going")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.vertical, 4)
                .liquidGlass(radius: Tokens.Radius.pill)
        }
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.md) {
            rsvpMenu
            Spacer()
            if !event.isPast {
                Button(action: onAddToCalendar) {
                    Image(systemName: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Color.textSecondary)
                .accessibilityLabel("Add to calendar")
            }
        }
    }

    private var rsvpMenu: some View {
        Menu {
            ForEach(RSVPStatus.allCases.filter { $0 != .none }, id: \.self) { status in
                Button(status.label) { onRSVP(status) }
            }
        } label: {
            Text(event.myRSVP.label)
                .font(Tokens.Typography.caption.weight(.bold))
                .foregroundStyle(event.myRSVP == .going ? .white : Tokens.Color.textSecondary)
                .padding(.horizontal, Tokens.Spacing.lg)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    Capsule().fill(event.myRSVP == .going
                                   ? AnyShapeStyle(Tokens.Color.accent)
                                   : AnyShapeStyle(.ultraThinMaterial))
                }
        }
        .accessibilityLabel("RSVP, currently \(event.myRSVP.label)")
    }
}
