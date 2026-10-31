import SwiftUI

/// Opens by itself when a reminder comes due: snooze or finish it right here.
struct TaskDueView: View {
    let viewModel: NotchViewModel
    private var store: TaskStore { viewModel.services.tasks }

    var body: some View {
        if let id = viewModel.dueTaskID, let task = store.task(id) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26, weight: .semibold))
                    .symbolEffect(.bounce, value: id)
                    .frame(width: 44, height: 44)
                    .glassSurface(Circle(), tint: .yellow.opacity(0.25))

                VStack(alignment: .leading, spacing: 2) {
                    Text("REMINDER")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.yellow)
                    Text(task.title)
                        .font(Design.text(14, .semibold))
                        .lineLimit(2)
                        .onTapGesture { viewModel.showTask(id) }
                    TaskMeta(task: task, showsDay: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassGroup(spacing: 6) {
                    VStack(spacing: 6) {
                        Button("Done") { finish { store.toggle(id) } }
                            .buttonStyle(PillButtonStyle(tint: .green.opacity(0.7)))
                        Button("Snooze 5 min") { finish { store.snooze(id) } }
                            .buttonStyle(PillButtonStyle(tint: Design.fill))
                    }
                }
            }
        } else {
            Color.clear.onAppear { viewModel.step(to: .tasks) }
        }
    }

    private func finish(_ action: () -> Void) {
        withAnimation(NotchViewModel.spring, action)
        if case .taskDue = viewModel.services.activities.current { viewModel.services.activities.dismiss() }
        viewModel.dueTaskID = nil
        viewModel.collapse()
    }
}
