import SwiftUI

@main
struct ConversationTranslatorApp: App {
    init() { LocalArchive.cleanupAbandonedAudio() }
    var body: some Scene { WindowGroup { ConversationView() } }
}
