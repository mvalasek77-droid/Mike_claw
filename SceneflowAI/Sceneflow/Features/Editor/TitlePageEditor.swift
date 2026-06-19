import SwiftUI

struct TitlePageEditor: View {
    @Binding var screenplay: Screenplay

    var body: some View {
        Form {
            Section("Title page") {
                TextField("Title", text: $screenplay.titlePage.title)
                TextField("Credit (e.g. Written by)", text: $screenplay.titlePage.credit)
                TextField("Author", text: $screenplay.titlePage.author)
                TextField("Based on (optional)", text: $screenplay.titlePage.source)
                TextField("Draft (e.g. First Draft)", text: $screenplay.titlePage.draftDate)
                TextField("Contact", text: $screenplay.titlePage.contact, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Story") {
                TextField("Genre", text: $screenplay.genre)
                TextField("Logline", text: $screenplay.logline, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("Title Page")
        .navigationBarTitleDisplayMode(.inline)
    }
}
