import SwiftUI

/// A calm, one-line-explanation empty state -- used anywhere a list could
/// otherwise render as a confusing blank area (sharing off, no devices yet,
/// no history yet, no blocked devices).
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 2)
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}
