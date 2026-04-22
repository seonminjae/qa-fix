import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case tickets = "Tickets"
    case cost = "Cost"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .tickets: return "ticket"
        case .cost: return "dollarsign.circle"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selection: SidebarItem = .tickets

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .tickets:
            TicketListView()
        case .cost:
            CostDashboardView()
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    ContentView()
}
