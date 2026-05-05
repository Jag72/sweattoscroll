// PairingView.swift — PRD §6A entry; CloudKit 6-digit flow lives in `PairCodeEntryView` / `PairCodeGeneratorView`.

import SwiftUI

/// Unified pairing surface for navigation from menus or deep links.
struct PairingView: View {
    var body: some View {
        PairCodeEntryView()
    }
}
