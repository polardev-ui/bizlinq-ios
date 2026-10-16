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
                    Label("My Meetings", systemImage: "calendar")
                }
                .tag(1)
            HostDashboardView()
                .tabItem {
                    Label("Host", systemImage: "plus.circle")
                }
                .tag(2)
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(3)
        }
        .tint(BizStyle.teal)
        .sensoryFeedback(.selection, trigger: tab)
        .onAppear {
            tab = initialTab
        }
    }
}
