// The size of the app's form sheets (Record Payment, the closing events, the client and series forms,
// the Issue sheet): sized to their content on macOS 15 (`presentationSizing(.form)`), a fixed width range
// before that.

import SwiftUI

extension View {
    @ViewBuilder func formSheetSized(minWidth: CGFloat = 560, maxWidth: CGFloat = 720) -> some View {
        if #available(macOS 15, *) {
            frame(minWidth: minWidth, maxWidth: maxWidth).presentationSizing(.form)
        } else {
            frame(minWidth: minWidth, maxWidth: maxWidth)
        }
    }
}
