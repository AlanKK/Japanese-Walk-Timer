import SwiftUI

struct SummaryView: View {
    let summary: SessionSummary
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Session Complete")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Divider()

                // Total time
                LabeledValue(label: "Total Time", value: summary.formattedTotalTime)

                // Fast intervals
                LabeledValue(
                    label: summary.fastLabel,
                    value: "\(summary.fastIntervalCount)"
                )

                // Slow intervals
                LabeledValue(
                    label: summary.slowLabel,
                    value: "\(summary.slowIntervalCount)"
                )

                Divider()

                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    SummaryView(
        summary: SessionSummary(
            totalTime: 732,
            fastIntervalCount: 3,
            slowIntervalCount: 3,
            fastLabel: "Fast Walk",
            slowLabel: "Slow Walk"
        ),
        onDismiss: {}
    )
}
