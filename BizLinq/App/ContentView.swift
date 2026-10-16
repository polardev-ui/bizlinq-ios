import SwiftUI

struct ContentView: View {
    var initialTab: Int = 0
    var autoOpenDetail: Bool = false
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            BrowseView(autoOpenDetail: autoOpenDetail)
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }
                .tag(0)
            AttendeeMeetingsView()
                .tabItem {
                    Label("My Meetings", systemImage: "ticket.fill")
                }
                .tag(1)
            HostDashboardView()
                .tabItem {
                    Label("Host", systemImage: "megaphone.fill")
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
