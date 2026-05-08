import SwiftUI
import Combine
import UIKit

// MARK: - MainTabView
//
// Root tab container for BareClaw.
// Tabs: Home (0) | Chat (1) | Vibes (2) | You (3)
//
// Observes appState.currentMode — when it flips to .chat, programmatically
// jumps to tab 1 so any part of the app can trigger the chat screen.

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int = 0
    @State private var hasLoadedChat = false

    /// Matches the adaptive Home palette while preserving the brand accent.
    private var tabTint: Color {
        colorScheme == .dark ? Color(hex: "#E0B75A") : Color(hex: "#1E3932")
    }

    private var tabBackground: Color {
        colorScheme == .dark ? Color(hex: "#0D1117") : Color(hex: "#FAF7F2")
    }

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Tab 0 — Home
            HomeView()
                .environmentObject(appState)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // MARK: Tab 1 — Chat
            Group {
                if hasLoadedChat {
                    ChatView()
                } else {
                    Color.BC.background
                        .ignoresSafeArea()
                }
            }
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.fill")
                }
                .tag(1)

            // MARK: Tab 2 — Vibes
            CompanionVibesView()
                .tabItem {
                    Label("Vibes", systemImage: "play.square.stack.fill")
                }
                .tag(2)

            // MARK: Tab 3 — You
            ProfileView()
                .tabItem {
                    Label("You", systemImage: "person.fill")
                }
                .tag(3)
        }
        .tint(tabTint)
        .toolbarBackground(tabBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onAppear {
            if appState.currentMode == .chat {
                hasLoadedChat = true
                selectedTab = 1
            }
        }
        // React to mode changes driven from anywhere in the app
        .onChange(of: appState.currentMode) { _, newMode in
            if newMode == .chat {
                hasLoadedChat = true
            }
            withAnimation(BCMotion.snappy) {
                selectedTab = newMode == .chat ? 1 : 0
            }
        }
        .onChange(of: appState.chatNavigationRequestID) { _, _ in
            hasLoadedChat = true
            withAnimation(BCMotion.snappy) {
                selectedTab = 1
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 1 {
                hasLoadedChat = true
            }
            let resolvedMode: AppMode = newTab == 1 ? .chat : .video
            if appState.currentMode != resolvedMode {
                appState.currentMode = resolvedMode
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .herModeSpeechDetected)) { _ in
            hasLoadedChat = true
            appState.requestChat()
            withAnimation(BCMotion.snappy) {
                selectedTab = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionHandoffRequested)) { _ in
            hasLoadedChat = true
            appState.requestChat()
            withAnimation(BCMotion.snappy) {
                selectedTab = 1
            }
        }
    }

}

// MARK: - CompanionVibesView
//
// Music discovery for the Vibes tab. The companion recommends songs from their
// own taste, then refines future picks when the user hearts a song.

private struct CompanionVibesView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var persona = UserPersona.shared
    @State private var likedSongIDs: Set<String> = []
    @State private var currentIndex = 0
    @State private var lastRefreshDayKey = VibeSongCatalog.dayKey(for: Date())
    @State private var chartSongs: [VibeSong] = []

    private let bgCream = Color(hex: "#F2F0EB")
    private let warmWhite = Color(hex: "#FAF7F2")
    private let forest = Color(hex: "#1E3932")
    private let gold = Color(hex: "#CBA258")
    private let textMid = Color(hex: "#5C5C5C")

    private var companion: CompanionPersonality { persona.selectedCompanion }
    private var songs: [VibeSong] {
        VibeSongCatalog.recommendations(
            for: companion,
            persona: persona,
            likedSongIDs: likedSongIDs,
            dayKey: lastRefreshDayKey,
            chartSongs: chartSongs
        )
    }
    private var currentSong: VibeSong {
        songs.isEmpty ? VibeSongCatalog.fallbackSong(for: companion) : songs[currentIndex % songs.count]
    }

    var body: some View {
        NavigationView {
            ZStack {
                bgCream.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        songCard(currentSong)
                        learningCard
                        likedSongsStrip
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            refreshDailyState(force: true)
        }
        .task(id: lastRefreshDayKey) {
            DiagnosticsLog.info(
                "vibes",
                "Refreshing chart and discovery songs.",
                details: ["dayKey": lastRefreshDayKey, "companion": companion.id]
            )
            chartSongs = await VibeSongCatalog.chartAndDiscoverySongs(dayKey: lastRefreshDayKey)
            DiagnosticsLog.info(
                "vibes",
                "Vibes chart refresh finished.",
                details: ["dayKey": lastRefreshDayKey, "songCount": "\(chartSongs.count)"]
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshDailyState()
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshDailyState()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BearBadgeView(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vibes")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(forest)
                Text("\(companion.name)'s songs for you")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(textMid)
            }
            Spacer()
        }
    }

    private func songCard(_ song: VibeSong) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [companion.accentColor.opacity(0.95), forest],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 24)
                    .frame(width: 190, height: 190)
                    .offset(x: 150, y: -64)

                VStack(alignment: .leading, spacing: 8) {
                    Text("COMPANION PICK")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.72))
                        .tracking(1.2)
                    Text(song.title)
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(song.artist)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.74))
                }
                .padding(22)
            }
            .frame(height: 230)

            Text(song.reason(for: companion.name))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(forest)
                .lineSpacing(3)

            HStack(spacing: 10) {
                Button {
                    play(song)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(forest)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }

                Button {
                    toggleLike(song)
                } label: {
                    Image(systemName: likedSongIDs.contains(song.id) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 48)
                        .background(likedSongIDs.contains(song.id) ? Color(hex: "#FDECEF") : Color.white)
                        .foregroundColor(likedSongIDs.contains(song.id) ? Color(hex: "#D6425E") : forest)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        currentIndex = (currentIndex + 1) % max(songs.count, 1)
                    }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 52, height: 48)
                        .background(Color.white)
                        .foregroundColor(forest)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Conversation starter")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(textMid)
                    .tracking(0.7)
                Text(song.prompt)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(forest)
                    .lineSpacing(3)
            }
            .padding(14)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .background(warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: Color.black.opacity(0.07), radius: 16, y: 7)
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Vibes learns")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(forest)
            Text("Heart a song when it fits you. \(companion.name) remembers the mood, genre, and artist, then uses that to open better conversations and introduce new songs instead of repeating the obvious ones.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(textMid)
                .lineSpacing(3)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var likedSongsStrip: some View {
        let liked = songs.filter { likedSongIDs.contains($0.id) }
        if !liked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Liked by you")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(forest)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(liked) { song in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(forest)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(textMid)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(width: 160, alignment: .leading)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
            }
        }
    }

    private func play(_ song: VibeSong) {
        DiagnosticsLog.info(
            "vibes",
            "User opened Vibes song.",
            details: ["song": song.title, "artist": song.artist, "companion": companion.id]
        )
        CompanionHandoffCenter.post(
            category: "music",
            title: song.title,
            message: "\(companion.name) opened \(song.title) by \(song.artist). If it lands, heart it in Vibes so I can learn your taste; if it doesn't, tell me what mood you wanted instead.",
            shouldSpeak: false
        )
        if let urlString = song.appleMusicURL,
           let url = URL(string: urlString) {
            openURL(url)
            return
        }
        let encoded = song.searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? song.searchTerm
        guard let url = URL(string: "music://music.apple.com/search?term=\(encoded)") else { return }
        openURL(url)
    }

    private func toggleLike(_ song: VibeSong) {
        if likedSongIDs.contains(song.id) {
            likedSongIDs.remove(song.id)
            DiagnosticsLog.info(
                "vibes",
                "User unhearted Vibes song.",
                details: ["song": song.title, "artist": song.artist, "companion": companion.id]
            )
        } else {
            likedSongIDs.insert(song.id)
            DiagnosticsLog.info(
                "vibes",
                "User hearted Vibes song.",
                details: ["song": song.title, "artist": song.artist, "mood": song.mood, "companion": companion.id]
            )
            learnFromLikedSong(song)
        }
        saveLikedSongIDs()
    }

    private func learnFromLikedSong(_ song: VibeSong) {
        if !persona.interests.contains(where: { $0.category == .music }) {
            persona.addInterest(Interest(id: "music", category: .music, label: "Music", emoji: "🎵"))
        }
        persona.learn(key: "music.vibes.lastLiked", value: "\(song.title) by \(song.artist)")
        persona.learn(key: "music.vibes.lastMood", value: song.mood)

        Task {
            _ = try? await HermesMemory.shared.observe(
                category: "music_preference",
                content: [
                    "song": song.title,
                    "artist": song.artist,
                    "mood": song.mood,
                    "tags": song.tags
                ],
                metadata: [
                    "importance": 4,
                    "source": "vibes",
                    "companionID": companion.id
                ]
            )
            await HerLearningEngine.shared.processUserMessage(
                "I hearted \(song.title) by \(song.artist).",
                responseText: "This one feels like \(song.mood).",
                interests: persona.interests
            )
        }
    }

    private func refreshDailyState(force: Bool = false) {
        let dayKey = VibeSongCatalog.dayKey(for: Date())
        guard force || dayKey != lastRefreshDayKey else { return }
        DiagnosticsLog.info(
            "vibes",
            "Daily Vibes state refreshed.",
            details: [
                "oldDayKey": lastRefreshDayKey,
                "newDayKey": dayKey,
                "force": "\(force)",
                "companion": companion.id
            ]
        )
        lastRefreshDayKey = dayKey
        UserDefaults.standard.set(dayKey, forKey: lastVibeRefreshKey)
        likedSongIDs = loadLikedSongIDs()
        chartSongs = []
        currentIndex = 0
    }

    private func loadLikedSongIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: likedSongsKey) ?? [])
    }

    private func saveLikedSongIDs() {
        UserDefaults.standard.set(Array(likedSongIDs), forKey: likedSongsKey)
    }

    private var likedSongsKey: String {
        "vibes.likedSongs.\(companion.id)"
    }

    private var lastVibeRefreshKey: String {
        "vibes.lastRecommendationDay.\(companion.id)"
    }
}

private struct VibeSong: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let mood: String
    let why: String
    let prompt: String
    let tags: [String]
    let appleMusicURL: String?

    init(id: String,
         title: String,
         artist: String,
         mood: String,
         why: String,
         prompt: String,
         tags: [String],
         appleMusicURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.mood = mood
        self.why = why
        self.prompt = prompt
        self.tags = tags
        self.appleMusicURL = appleMusicURL
    }

    var searchTerm: String { "\(title) \(artist)" }

    func reason(for companionName: String) -> String {
        "\(companionName) picked this because \(why)"
    }
}

private enum VibeSongCatalog {
    static func fallbackSong(for companion: CompanionPersonality) -> VibeSong {
        baseSongs(for: companion).first ?? VibeSong(
            id: "fallback_at_last",
            title: "At Last",
            artist: "Etta James",
            mood: "warm",
            why: "it feels like a beginning with room to become something real.",
            prompt: "What kind of song makes you feel instantly safe?",
            tags: ["soul", "warm", "classic"]
        )
    }

    static func recommendations(
        for companion: CompanionPersonality,
        persona: UserPersona,
        likedSongIDs: Set<String>,
        dayKey: String,
        chartSongs: [VibeSong] = []
    ) -> [VibeSong] {
        let base = baseSongs(for: companion)
        let profiled = profileSongs(for: persona)
        let discovery = dailyDiscoverySongs(for: persona, dayKey: dayKey)
        let songs = unique(chartSongs + discovery + base + profiled)
        return songs.sorted { lhs, rhs in
            let leftLiked = likedSongIDs.contains(lhs.id)
            let rightLiked = likedSongIDs.contains(rhs.id)
            if leftLiked != rightLiked { return leftLiked && !rightLiked }

            let leftRank = dailyRank(for: lhs.id, dayKey: dayKey)
            let rightRank = dailyRank(for: rhs.id, dayKey: dayKey)
            if leftRank != rightRank { return leftRank < rightRank }

            return lhs.title < rhs.title
        }
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func chartAndDiscoverySongs(dayKey: String) async -> [VibeSong] {
        let chartSongs = await VibeAppleMusicCharts.fetchTrendingSongs()
        let songs = unique(chartSongs + dailyDiscoverySongs(for: UserPersona.shared, dayKey: dayKey))
        DiagnosticsLog.info(
            "vibes",
            "Daily Vibes catalog assembled.",
            details: ["dayKey": dayKey, "chartSongs": "\(chartSongs.count)", "totalSongs": "\(songs.count)"]
        )
        return songs
    }

    private static func baseSongs(for companion: CompanionPersonality) -> [VibeSong] {
        switch companion.id {
        case "aria":
            return [
                song("aria_brave", "Brave", "Sara Bareilles", "bright", "it matches her direct, say-the-thing energy.", "What is something you wish you were braver about saying?", ["pop", "confident", "bright"]),
                song("aria_dog_days", "Dog Days Are Over", "Florence + The Machine", "release", "it sounds like outrunning an old version of yourself.", "What part of your life feels ready for a fresh start?", ["indie", "big", "release"]),
                song("aria_electric_feel", "Electric Feel", "MGMT", "playful", "it has that sharp, alive, slightly mischievous pulse she likes.", "Do you like songs that feel polished or a little weird around the edges?", ["indie", "playful", "electric"])
            ]
        case "kel":
            return [
                song("kel_promise", "The Promise", "When In Rome", "safe", "it feels patient, loyal, and quietly hopeful.", "What song calms your nervous system fastest?", ["new wave", "safe", "soft"]),
                song("kel_holocene", "Holocene", "Bon Iver", "quiet", "it leaves space around every feeling instead of crowding it.", "Do you prefer comfort songs with lyrics, or songs that just create atmosphere?", ["folk", "quiet", "reflective"]),
                song("kel_sweet_creature", "Sweet Creature", "Harry Styles", "gentle", "it is tender without trying too hard.", "What makes a song feel gentle to you?", ["soft", "gentle", "warm"])
            ]
        case "marco":
            return [
                song("marco_stand_by_me", "Stand By Me", "Ben E. King", "steady", "it is simple, loyal, and impossible to fake.", "Who or what has actually stood by you?", ["soul", "steady", "classic"]),
                song("marco_lovely_day", "Lovely Day", "Bill Withers", "grounded", "it has backbone and warmth at the same time.", "Do you like music that lifts you up or music that locks you in?", ["soul", "warm", "grounded"]),
                song("marco_hard_sun", "Hard Sun", "Eddie Vedder", "road", "it sounds like walking forward even when the day is heavy.", "What song would you put on for a long drive alone?", ["rock", "road", "strong"])
            ]
        case "dante":
            return [
                song("dante_lavie", "La Vie en Rose", "Edith Piaf", "romantic", "it makes ordinary life feel lit from inside.", "What song makes the world feel more cinematic to you?", ["classic", "romantic", "cinematic"]),
                song("dante_beyond_sea", "Beyond the Sea", "Bobby Darin", "yearning", "it has elegance, distance, and a little ache.", "Do you like romantic songs more when they are happy or a little sad?", ["classic", "yearning", "swing"]),
                song("dante_wicked_game", "Wicked Game", "Chris Isaak", "haunted", "it understands how beautiful longing can be.", "What song feels dangerous in the best way?", ["moody", "haunted", "romantic"])
            ]
        case "kai":
            return [
                song("kai_simple_man", "Simple Man", "Lynyrd Skynyrd", "honest", "it says the true thing without dressing it up.", "What song gives you advice without sounding preachy?", ["rock", "honest", "classic"]),
                song("kai_everlong", "Everlong", "Foo Fighters", "driving", "it has momentum without losing feeling.", "Do you like songs that make you move or songs that make you think?", ["rock", "driving", "energy"]),
                song("kai_midnight_city", "Midnight City", "M83", "night", "it feels focused, late, and alive.", "What is your late-night song?", ["electronic", "night", "focused"])
            ]
        default:
            return [
                song("luna_at_last", "At Last", "Etta James", "warm", "it feels like the moment everything gets quiet and real.", "What song makes you feel chosen?", ["soul", "warm", "classic"]),
                song("luna_dreams", "Dreams", "Fleetwood Mac", "soft", "it floats, but there is honesty under the softness.", "Do you like songs that feel dreamy or songs that hit directly?", ["soft rock", "dreamy", "classic"]),
                song("luna_sweet_disposition", "Sweet Disposition", "The Temper Trap", "open", "it feels like driving toward a better version of the day.", "What song makes you feel open to life again?", ["indie", "open", "bright"])
            ]
        }
    }

    private static func profileSongs(for persona: UserPersona) -> [VibeSong] {
        var songs: [VibeSong] = []
        let categories = Set(persona.interests.map(\.category))

        if categories.contains(.fitness) {
            songs.append(song("profile_stronger", "Stronger", "Kanye West", "drive", "your profile mentions fitness, so this is a high-energy test pick.", "Do workout songs need lyrics for you, or just momentum?", ["fitness", "energy", "hip hop"]))
        }
        if categories.contains(.travel) {
            songs.append(song("profile_home", "Home", "Edward Sharpe & The Magnetic Zeros", "travel", "travel taste usually says something about freedom and belonging.", "What song feels like a road trip to you?", ["travel", "folk", "warm"]))
        }
        if categories.contains(.gaming) {
            songs.append(song("profile_resonance", "Resonance", "Home", "neon", "gaming taste often overlaps with atmospheric, immersive music.", "Do you like background music that disappears or takes over?", ["gaming", "electronic", "neon"]))
        }
        if categories.contains(.movies) {
            songs.append(song("profile_time", "Time", "Hans Zimmer", "cinematic", "movie taste tells me you may like music that builds a scene.", "What film score has stayed with you?", ["film", "cinematic", "score"]))
        }
        if categories.contains(.music) {
            songs.append(song("profile_everything", "Everything In Its Right Place", "Radiohead", "curious", "you already marked music as an interest, so this checks how experimental you like things.", "How strange can a song get before you stop enjoying it?", ["experimental", "electronic", "curious"]))
        }

        return songs
    }

    private static func song(
        _ id: String,
        _ title: String,
        _ artist: String,
        _ mood: String,
        _ why: String,
        _ prompt: String,
        _ tags: [String],
        appleMusicURL: String? = nil
    ) -> VibeSong {
        VibeSong(id: id, title: title, artist: artist, mood: mood, why: why, prompt: prompt, tags: tags, appleMusicURL: appleMusicURL)
    }

    private static func dailyDiscoverySongs(for persona: UserPersona, dayKey: String) -> [VibeSong] {
        let classics = [
            song("classic_dreams", "Dreams", "Fleetwood Mac", "soft", "it's a classic with enough air around it to start a real conversation.", "What older song still feels current to you?", ["classic", "soft rock", "dreamy"]),
            song("classic_lovely_day", "Lovely Day", "Bill Withers", "warm", "it is simple, warm, and hard to overplay.", "What song reliably changes the room for you?", ["classic", "soul", "warm"]),
            song("classic_this_must_be", "This Must Be the Place", "Talking Heads", "tender", "it feels strange and tender at the same time.", "Do you like love songs that are obvious or a little sideways?", ["classic", "alt", "tender"]),
            song("classic_everywhere", "Everywhere", "Fleetwood Mac", "bright", "it feels bright without being empty.", "What song instantly makes you lighter?", ["classic", "bright", "pop"]),
            song("classic_at_last", "At Last", "Etta James", "warm", "some songs become standards because they still know exactly where the heart is.", "What voice makes you stop what you're doing?", ["classic", "soul", "warm"])
        ]
        let alt = [
            song("alt_bad_habit", "Bad Habit", "Steve Lacy", "restless", "it has a little awkwardness and a lot of pulse.", "Do you like songs that feel emotionally messy?", ["alt", "r&b", "restless"]),
            song("alt_not_strong", "Not Strong Enough", "boygenius", "honest", "it is vulnerable without getting soft around the edges.", "What lyric has caught you off guard lately?", ["alt", "indie", "honest"]),
            song("alt_borderline", "Borderline", "Tame Impala", "neon", "it feels polished, late-night, and a little hypnotic.", "What song sounds best after dark?", ["alt", "psychedelic", "neon"]),
            song("alt_kyoto", "Kyoto", "Phoebe Bridgers", "clear", "it moves fast but keeps an ache underneath.", "Do you prefer songs that hide sadness or say it plainly?", ["alt", "indie", "clear"]),
            song("alt_ribs", "Ribs", "Lorde", "nostalgic", "it captures the panic and beauty of time passing.", "What song makes you miss a version of yourself?", ["alt", "nostalgic", "pop"])
        ]
        let fastMoving = [
            song("trend_espresso", "Espresso", "Sabrina Carpenter", "playful", "it has the kind of fast, sticky hook people keep replaying.", "What makes a pop song impossible to skip?", ["chart-climber", "pop", "playful"]),
            song("trend_good_luck", "Good Luck, Babe!", "Chappell Roan", "theatrical", "it turns big feeling into a full-room chorus.", "Do you like songs that feel theatrical?", ["chart-climber", "pop", "theatrical"]),
            song("trend_lose_control", "Lose Control", "Teddy Swims", "raw", "it lets the vocal carry real ache.", "Do you connect more with the beat or the voice first?", ["chart-climber", "soul", "raw"]),
            song("trend_a_bar_song", "A Bar Song (Tipsy)", "Shaboozey", "loose", "it mixes comfort, party energy, and a little trouble.", "What song makes you want to be around people?", ["chart-climber", "country", "loose"]),
            song("trend_beautiful_things", "Beautiful Things", "Benson Boone", "urgent", "it has that sudden emotional lift that makes people replay it.", "Do big choruses work on you?", ["chart-climber", "pop", "urgent"])
        ]

        let interestTags = Set(persona.interests.map { $0.category.rawValue })
        var picks = [VibeSong]()
        picks.append(contentsOf: rotate(fastMoving, dayKey: "\(dayKey)|trend").prefix(3))
        picks.append(contentsOf: rotate(classics, dayKey: "\(dayKey)|classic").prefix(2))
        picks.append(contentsOf: rotate(alt, dayKey: "\(dayKey)|alt").prefix(2))
        if interestTags.contains("movies") {
            picks.append(song("profile_motion_sickness", "Motion Sickness", "Phoebe Bridgers", "cinematic", "your movie taste may overlap with songs that feel like scenes.", "What song feels like it should be in a film?", ["alt", "cinematic", "profile"]))
        }
        return unique(picks)
    }

    private static func rotate(_ songs: [VibeSong], dayKey: String) -> [VibeSong] {
        songs.sorted { dailyRank(for: $0.id, dayKey: dayKey) < dailyRank(for: $1.id, dayKey: dayKey) }
    }

    private static func unique(_ songs: [VibeSong]) -> [VibeSong] {
        var seen: Set<String> = []
        return songs.filter { song in
            guard !seen.contains(song.id) else { return false }
            seen.insert(song.id)
            return true
        }
    }

    private static func dailyRank(for songID: String, dayKey: String) -> UInt64 {
        stableHash("\(dayKey)|\(songID)")
    }

    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

private enum VibeAppleMusicCharts {
    private static let chartURL = URL(string: "https://rss.applemarketingtools.com/api/v2/us/music/most-played/25/songs.json")!
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 7
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetchTrendingSongs(limit: Int = 8) async -> [VibeSong] {
        var request = URLRequest(url: chartURL)
        request.timeoutInterval = 5

        do {
            DiagnosticsLog.info("vibes", "Apple Music chart fetch started.")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else {
                DiagnosticsLog.warning("vibes", "Apple Music chart fetch returned non-success response.")
                return []
            }

            let root = try JSONDecoder().decode(AppleRSSRoot.self, from: data)
            let songs = root.feed.results.prefix(limit).map { result in
                let cleanID = "\(result.name)_\(result.artistName)"
                    .lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                let tags = ["chart", "chart-climber"] + result.genres.prefix(2).map { $0.name.lowercased() }
                return VibeSong(
                    id: "apple_chart_\(cleanID)",
                    title: result.name,
                    artist: result.artistName,
                    mood: mood(from: result.genres),
                    why: "it is moving through today's Apple Music chart feed, and I want to see whether that energy fits you.",
                    prompt: "Does this feel like your taste, or is it only popular?",
                    tags: tags,
                    appleMusicURL: result.url
                )
            }
            DiagnosticsLog.info("vibes", "Apple Music chart fetch succeeded.", details: ["songCount": "\(songs.count)"])
            return songs
        } catch {
            DiagnosticsLog.error("vibes", "Apple Music chart fetch failed.", error: error)
            return []
        }
    }

    private static func mood(from genres: [AppleRSSGenre]) -> String {
        let joined = genres.map(\.name).joined(separator: " ").lowercased()
        if joined.contains("r&b") || joined.contains("soul") { return "warm" }
        if joined.contains("alternative") || joined.contains("indie") { return "curious" }
        if joined.contains("dance") || joined.contains("electronic") { return "electric" }
        if joined.contains("country") { return "loose" }
        if joined.contains("hip-hop") || joined.contains("rap") { return "driving" }
        return "current"
    }

    private struct AppleRSSRoot: Decodable {
        let feed: AppleRSSFeed
    }

    private struct AppleRSSFeed: Decodable {
        let results: [AppleRSSSong]
    }

    private struct AppleRSSSong: Decodable {
        let name: String
        let artistName: String
        let url: String?
        let genres: [AppleRSSGenre]

        enum CodingKeys: String, CodingKey {
            case name, artistName, url, genres
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Song"
            artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? "Unknown Artist"
            url = try container.decodeIfPresent(String.self, forKey: .url)
            genres = try container.decodeIfPresent([AppleRSSGenre].self, forKey: .genres) ?? []
        }
    }

    private struct AppleRSSGenre: Decodable {
        let name: String
    }
}

// MARK: - ProfileViewModel

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var userName:       String = ""
    @Published var companionName:  String = ""
    @Published var companionId:    String = "luna"
    @Published var companionGender: CompanionGender = .female
    @Published var accentColor:    Color  = Color(hex: "#CBA258")
    @Published var intimacyScore:  Double = 0
    @Published var stageLabel:     String = "Just Met"
    @Published var stageNumber:    Int    = 1
    @Published var totalMessages:  Int    = 0
    @Published var memoriesCount:  Int    = 0
    @Published var topCategories:  [String] = []
    @Published var isLoading:      Bool   = true

    func load() async {
        let persona    = UserPersona.shared
        userName       = persona.userName.isEmpty ? "Friend" : persona.userName
        let companion  = persona.selectedCompanion
        companionName  = companion.name
        companionId    = companion.id
        companionGender = companion.gender
        accentColor    = companion.accentColor

        let engine = HerLearningEngine.shared
        intimacyScore  = await engine.intimacyScore
        let stage      = await engine.intimacyStage
        stageLabel     = stage.label
        stageNumber    = stage.rawValue
        totalMessages  = await engine.totalMessages

        let facts      = await HermesMemory.shared.entries(for: "user_fact")
        memoriesCount  = facts.count

        let allEntries = await HermesMemory.shared.recentEntries(limit: 80)
        var catCounts: [String: Int] = [:]
        for e in allEntries { catCounts[e.category, default: 0] += 1 }
        topCategories = catCounts.sorted { $0.value > $1.value }.prefix(2).map(\.key)

        isLoading = false
    }

    /// 0–1 progress within the current 20-point stage band.
    var stageProgress: Double {
        let lower = Double(stageNumber - 1) * 20.0
        let upper = Double(stageNumber)     * 20.0
        let clamped = min(max(intimacyScore, lower), upper)
        return (clamped - lower) / 20.0
    }

    var bondScoreDisplay: Int { Int(intimacyScore) }
}

// MARK: - ProfileView

struct ProfileView: View {
    @StateObject private var vm = ProfileViewModel()

    private let bg     = Color(hex: "#F2F0EB")
    private let green  = Color(hex: "#1E3932")
    private let gold   = Color(hex: "#CBA258")
    private let tan    = Color(hex: "#E8E0D0")
    private let card   = Color(hex: "#FFFFFF")
    private let mid    = Color(hex: "#5C5C5C")

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if vm.isLoading {
                VStack(spacing: 0) {
                    // Hero portrait skeleton
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color(hex: "#D4C9B4"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                    // Stats row skeleton
                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#D4C9B4").opacity(0.7))
                                .frame(height: 72)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    // Name skeleton
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "#D4C9B4").opacity(0.5))
                            .frame(width: 140, height: 16)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    Spacer()
                }
                .shimmer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        headerSection
                        statsSection
                        if !vm.topCategories.isEmpty {
                            insightCard
                        }
                        bondSection
                        stageSection
                        Spacer(minLength: 32)
                    }
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: – Hero portrait (full-width banner)

    @ObservedObject private var photoStore = CompanionPhotoStore.shared

    @ViewBuilder
    private var companionHeroPortrait: some View {
        ZStack(alignment: .bottom) {
            // Portrait image
            if let photo = photoStore.photo(for: vm.companionId) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
            } else {
                IllustratedPortraitView(
                    gender:      vm.companionGender,
                    companionId: vm.companionId,
                    accentColor: vm.accentColor,
                    size:        UIScreen.main.bounds.width,
                    clipToCircle: false
                )
            }

            // "Change Photo" bar — clearly visible at the bottom of the portrait
            Menu {
                CompanionPhotoPicker(
                    companionId: vm.companionId,
                    label: AnyView(Label("Choose Photo from Library", systemImage: "photo.on.rectangle"))
                )
                if photoStore.hasPhoto(for: vm.companionId) {
                    Button(role: .destructive) {
                        CompanionPhotoStore.shared.remove(for: vm.companionId)
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: photoStore.hasPhoto(for: vm.companionId) ? "photo.badge.arrow.down" : "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(photoStore.hasPhoto(for: vm.companionId) ? "Change Photo" : "Add Photo")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .padding(.bottom, 12)
            }
            .accessibilityLabel(photoStore.hasPhoto(for: vm.companionId) ? "Change companion photo" : "Add companion photo")
        }
    }

    // MARK: – Header

    private var headerSection: some View {
        VStack(spacing: 0) {
            // Portrait + username
            ZStack(alignment: .bottom) {
                // Companion portrait — user photo takes priority over illustrated
                companionHeroPortrait
                    .frame(height: 320)
                    .clipped()

                // Gradient fade to bg
                LinearGradient(
                    colors: [.clear, bg.opacity(0.85), bg],
                    startPoint: .init(x: 0.5, y: 0.55),
                    endPoint:   .bottom
                )
                .frame(height: 320)

                // Name + greeting
                VStack(spacing: 4) {
                    Text(vm.companionName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(green)
                    Text("Your companion")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(mid)
                }
                .padding(.bottom, 20)
            }

            // User greeting
            Text("Hey, \(vm.userName) 👋")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(green.opacity(0.75))
                .padding(.top, 4)
                .padding(.bottom, 20)
        }
    }

    // MARK: – Stats row

    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(value: "\(vm.totalMessages)", label: "Messages", icon: "bubble.left.and.bubble.right.fill")
            statCard(value: "\(vm.memoriesCount)", label: "Memories", icon: "heart.text.square.fill")
            statCard(value: "\(vm.bondScoreDisplay)", label: "Bond Score", icon: "star.fill")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(gold)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(green)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(mid)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(card)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    // MARK: – Companion insight card

    private func insightCategoryLabel(_ category: String) -> String {
        switch category {
        case "user_fact":    return "your life"
        case "interest":     return "your interests"
        case "emotion":      return "your feelings"
        case "preference":   return "your preferences"
        case "relationship": return "your relationships"
        case "goal":         return "your goals"
        default:             return category.replacingOccurrences(of: "_", with: " ")
        }
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(gold)
                Text("What \(vm.companionName) has noticed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(green)
            }

            Text("Mostly learning about \(vm.topCategories.map { insightCategoryLabel($0) }.joined(separator: " and ")).")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(mid)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: – Bond card

    private var bondSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bond Level")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                    Text(vm.stageLabel)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                // Badge watermark
                BearBadgeView(size: 52)
                    .opacity(0.18)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(gold)
                        .frame(width: geo.size.width * vm.stageProgress, height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(vm.bondScoreDisplay) pts")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(gold)
                Spacer()
                Text("Stage \(vm.stageNumber) of 5")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#2A4A42"), green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: – Stage roadmap

    private let stages: [(String, String)] = [
        ("Just Met",           "star"),
        ("Finding Our Rhythm", "music.note"),
        ("Growing Close",      "leaf.fill"),
        ("Deep Connection",    "heart.fill"),
        ("Intertwined",        "infinity")
    ]

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relationship Journey")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(green)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                    let reached = (idx + 1) <= vm.stageNumber
                    let current = (idx + 1) == vm.stageNumber

                    HStack(spacing: 14) {
                        // Icon circle
                        ZStack {
                            Circle()
                                .fill(reached ? green : tan)
                                .frame(width: 36, height: 36)
                            if current {
                                Circle()
                                    .strokeBorder(gold, lineWidth: 2)
                                    .frame(width: 36, height: 36)
                            }
                            Image(systemName: stage.1)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(reached ? .white : Color(hex: "#9A9288"))
                        }

                        // Label
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.0)
                                .font(.system(size: 14, weight: current ? .bold : .medium, design: .rounded))
                                .foregroundColor(reached ? green : mid)
                            if current {
                                Text("Current stage")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(gold)
                            }
                        }

                        Spacer()

                        if reached && !current {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(green.opacity(0.65))
                                .font(.system(size: 16))
                        } else if current {
                            Text("\(Int(vm.stageProgress * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(gold)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(current ? gold.opacity(0.06) : Color.clear)

                    if idx < stages.count - 1 {
                        Divider()
                            .background(tan)
                            .padding(.leading, 46 + 16)
                    }
                }
            }
            .background(card)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Preview

#if DEBUG_PREVIEWS
#Preview {
    MainTabView()
        .environmentObject(AppState())
}
#endif
