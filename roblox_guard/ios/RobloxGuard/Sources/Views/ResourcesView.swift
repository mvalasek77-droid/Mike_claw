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
                Section {
                    NavigationLink {
                        Roblox101View()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Roblox 101")
                                    .font(.subheadline.weight(.medium))
                                Text("Never used Roblox? What it is, what Robux are, how strangers can reach your child — in plain words.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "graduationcap")
                        }
                    }
                    NavigationLink {
                        KnowTheDangersView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Know the Dangers")
                                    .font(.subheadline.weight(.medium))
                                Text("How targeting works, the warning signs, and the response playbook.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "book.closed")
                        }
                    }
                }
                Section {
                    DisclosureGroup("Do I install anything on my child's phone?") {
                        Text("No. RobloxGuard runs only on YOUR phone. It watches the public footprint of your child's Roblox account — friend list, friends' profiles, online status — which is visible without any access to their device or password. Nothing to install, nothing for them to delete, nothing that breaks when they get a new device.")
                            .font(.footnote)
                    }
                    DisclosureGroup("How do I start coverage?") {
                        Text("Tap + on the Dashboard, enter your child's Roblox username (just the public username — never a password), and confirm you're their parent or guardian. Monitoring starts immediately: a baseline scan first, then automatic re-checks around the clock.")
                            .font(.footnote)
                    }
                    DisclosureGroup("How does it keep up with new threats?") {
                        Text("Detection rules come from a threat feed that updates itself — new apps predators funnel kids toward, new coded phrases, newly flagged experiences — without waiting for an app update. Your feedback on alerts also tunes monitoring for your child: real problems raise vigilance, irrelevant alerts get muted.")
                            .font(.footnote)
                    }
                    DisclosureGroup("Can it read my child's chats?") {
                        Text("No — and no honest app can. Private Roblox chats are visible only to Roblox's own moderators. That's why reporting in-platform matters: Roblox can see the messages and act on them.")
                            .font(.footnote)
                    }
                } header: {    Text("Common questions")}
                Section {
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
                } header: {    Text("Reporting & guidance")}
            }
            .navigationTitle("Get Help")
        }
    }
}
