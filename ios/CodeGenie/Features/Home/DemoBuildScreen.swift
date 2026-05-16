import SwiftUI

/// Thin wrapper around `BuildScreen` that runs in demo mode.
///
/// Same screen the user sees during a real build — same transcript,
/// same cost meter, same diff stream, same success overlay. The only
/// difference is the events come from a canned JSON script bundled in
/// the app, not the backend. No tokens spent, no signup required.
///
/// This is the **first-time user moment.** They get to see the
/// entire product before paying anything.
struct DemoBuildScreen: View {
    let sample: SampleApp
    @EnvironmentObject private var session: AppSession

    var body: some View {
        let job = BuildJob(description: sample.description)
        return BuildScreen(job: job, demoSampleID: sample.id)
            .environmentObject(session)
    }
}
