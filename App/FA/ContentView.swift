import InvoicingCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FA — offline invoicing")
                .font(.title)
            Text("Scaffold build. Core module \(InvoicingCore.version).")
                .foregroundStyle(.secondary)
            Text("This app has no network permission; nothing leaves this Mac.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 240)
    }
}

#Preview {
    ContentView()
}
