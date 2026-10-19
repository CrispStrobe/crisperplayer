import SwiftUI
import WidgetKit

struct PlayerEntry: TimelineEntry {
  let date: Date
  let title: String
  let author: String
  let playing: Bool
}
struct PlayerProvider: TimelineProvider {
  func placeholder(in context: Context) -> PlayerEntry {
    PlayerEntry(date: Date(), title: "Your audiobook", author: "CrisperPlayer", playing: false)
  }
  func getSnapshot(in context: Context, completion: @escaping (PlayerEntry) -> Void) { completion(read()) }
  func getTimeline(in context: Context, completion: @escaping (Timeline<PlayerEntry>) -> Void) {
    completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(900))))
  }
  private func read() -> PlayerEntry {
    let data = UserDefaults(suiteName: "group.com.crispstrobe.crisperplayer")?.dictionary(forKey: "playerSnapshot") ?? [:]
    return PlayerEntry(date: Date(), title: data["title"] as? String ?? "CrisperPlayer",
      author: data["author"] as? String ?? "Open the app to add books", playing: data["playing"] as? Bool ?? false)
  }
}
struct PlayerView: View {
  let entry: PlayerEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("CrisperPlayer", systemImage: "book.fill").font(.caption).foregroundStyle(.secondary)
      Text(entry.title).font(.headline).lineLimit(2)
      Text(entry.author).font(.caption).lineLimit(1)
      HStack {
        Link(destination: URL(string: "crisperplayer://control/backward")!) { Label("Back 30 seconds", systemImage: "gobackward.30").labelStyle(.iconOnly) }
        Spacer()
        Link(destination: URL(string: "crisperplayer://control/toggle")!) { Label(entry.playing ? "Pause" : "Play", systemImage: entry.playing ? "pause.fill" : "play.fill").labelStyle(.iconOnly) }
        Spacer()
        Link(destination: URL(string: "crisperplayer://control/forward")!) { Label("Forward 30 seconds", systemImage: "goforward.30").labelStyle(.iconOnly) }
      }.font(.title2).padding(.top, 4)
    }.padding().widgetURL(URL(string: "crisperplayer://control/play"))
  }
}
@main
struct CrisperPlayerWidget: Widget {
  let kind = "CrisperPlayerWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PlayerProvider()) { entry in PlayerView(entry: entry) }
      .configurationDisplayName("CrisperPlayer").description("Resume your audiobook and skip 30 seconds.")
      .supportedFamilies([.systemMedium])
  }
}
