import WidgetKit
import SwiftUI

@main
struct BoxCallWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextOpeningWidget()
        TopPositionWidget()
        OpeningLiveActivity()
    }
}
