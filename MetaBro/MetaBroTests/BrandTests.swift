import Testing
@testable import MetaBro

struct BrandTests {
    @Test func sloganIsSet() {
        #expect(Brand.slogan == "The Man Cave of the Internet.")
        #expect(Brand.name == "MetaBro")
    }
}
