import SwiftUI

struct ContentView: View {
    var initialTab: Int = 0
    var autoOpenDetail: Bool = false
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            BrowseView(autoOpenDetail: autoOpenDetail)
                .tabItem {
                    Label("Discover", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)
            PostMeetingView()
                .tabItem {
                    Label("Post", systemImage: "plus.circle.fill")
                }
                .tag(1)
            MyMeetingsView()
                .tabItem {
                    Label("My Posts", systemImage: "tray.full")
                }
                .tag(2)
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
                .tag(3)
        }
        .onAppear {
            tab = initialTab
        }
    }
}
