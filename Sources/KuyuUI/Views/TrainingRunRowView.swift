import SwiftUI

struct TrainingRunRowView: View {
    let item: TrainingRunListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: KuyuSpacing.sm) {
                Text(item.id)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let liveness = item.liveness {
                    StatusPill(liveness.displayLabel, tone: liveness.pillTone)
                } else {
                    StatusPill("unreadable", tone: .danger)
                }
            }
            if let unreadableReason = item.unreadableReason {
                Text(unreadableReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: KuyuSpacing.sm) {
                    if let createdAt = item.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let task = item.task {
                        Text(task)
                    }
                    if let profile = item.profile {
                        Text(profile)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
