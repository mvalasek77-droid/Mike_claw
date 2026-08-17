import Testing
import Foundation
@testable import MetaBro

struct AvatarCatalogTests {

    @Test func userHandleDropsAtAndLowercases() {
        let url = AvatarCatalog.user(handle: "@IronBro")
        #expect(url.absoluteString.hasSuffix("/ironbro.png"))
    }

    @Test func userHandleWithoutAtWorks() {
        let url = AvatarCatalog.user(handle: "newbro")
        #expect(url.absoluteString.hasSuffix("/newbro.png"))
    }

    @Test func communityUsesSlug() {
        let url = AvatarCatalog.community(slug: "fitness")
        #expect(url.absoluteString.hasSuffix("/fitness.png"))
    }

    @Test func keyNormalization() {
        #expect(AvatarCatalog.key("@Coach") == "coach")
        #expect(AvatarCatalog.key("coach") == "coach")
    }
}
