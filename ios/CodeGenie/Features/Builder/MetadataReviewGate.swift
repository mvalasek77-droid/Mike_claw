import SwiftUI

/// Human gate for metadata review.
/// Shows all AI-generated App Store metadata and requires explicit user approval.
/// Rejection cancels the pipeline.
struct MetadataReviewGate: View {
    let metadata: PipelineClient.MetadataResult?
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(LiquidGlass.accent)

                        Text("Review Your App Store Listing")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)

                        Text("Apple requires accurate metadata. Review everything below carefully — if anything looks wrong, reject and fix it before continuing.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    if let meta = metadata {
                        metadataField("App Name", value: meta.name, icon: "app.badge")
                        metadataField("Subtitle", value: meta.subtitle, icon: "text.quote")
                        metadataField("Category", value: meta.category, icon: "folder")
                        metadataField("Description", value: meta.description, icon: "text.alignleft")
                        metadataField("Promotional Text", value: meta.promotionalText, icon: "megaphone")
                        metadataField("Keywords", value: meta.keywords.joined(separator: ", "), icon: "tag")
                        metadataField("Privacy Policy URL", value: meta.privacyPolicyURL, icon: "hand.raised")
                    } else {
                        GlassSurface(tier: .raised) {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.yellow)
                                Text("No metadata generated yet")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }

                    // Legal pages notice
                    GlassSurface(tier: .deep) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Privacy Policy & Terms of Use", systemImage: "doc.text.fill")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)

                            Text("Your privacy policy and terms of use will be published to GitHub Pages. Apple requires these URLs for App Store submission. You can edit them on GitHub anytime after publishing.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        .padding()
                    }

                    // Warning
                    GlassSurface(tier: .raised) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rejecting cancels the pipeline")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                Text("If any metadata is wrong, reject to stop. You can rebuild with corrections and re-run the pipeline.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                            }
                        }
                        .padding()
                    }
                }
                .padding(.horizontal, 20)
            }
            .navigationTitle("Metadata Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reject", role: .destructive) {
                        Haptics.warning()
                        onReject()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.success()
                        onApprove()
                    } label: {
                        Text("Approve")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                }
            }
        }
    }

    private func metadataField(_ label: String, value: String, icon: String) -> some View {
        GlassSurface(tier: .raised) {
            VStack(alignment: .leading, spacing: 6) {
                Label(label, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))

                if value.count > 120 {
                    Text(value)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                } else {
                    Text(value)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}