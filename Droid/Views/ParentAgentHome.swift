import SwiftUI

struct ParentAgentHome: View {
    var onSubmit: (String) -> Void
    @State private var prompt = ""
    @State private var taskStore = ParentAgentTaskStore.shared
    @FocusState private var focused

    var body: some View {
        VStack(spacing: 0) {
            if let task = taskStore.activeTask {
                VStack(spacing: 0) {
                    ParentAgentHeaderControls(task: task, onNewThread: startNewTask, showsNewThread: true)
                        .padding(.top, 18)
                        .frame(maxWidth: 760, alignment: .leading)
                    ParentAgentTimelineView(task: task)
                }
                composer
                    .frame(maxWidth: 720)
            } else {
                ZStack(alignment: .topLeading) {
                    ParentAgentHeaderControls(task: nil, onNewThread: startNewTask, showsNewThread: false)
                        .padding(.top, 18)
                    VStack(spacing: 22) {
                        Spacer(minLength: 0)
                        Text("What do you want to do?")
                            .droidFont(size: 19, weight: .medium)
                            .foregroundStyle(DroidTheme.fg)
                        composer
                            .frame(maxWidth: 640)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 88)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DroidTheme.bg)
        .onAppear { focused = true }
        .onChange(of: taskStore.activeTask?.status) { _, status in
            guard status == .completed || status == .waitingForUser else { return }
            focused = true
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let question = taskStore.pendingQuestion?.question {
                ParentAgentQuestionPrompt(question: question)
            }
        ParentAgentComposer(
            prompt: $prompt,
            isFocused: $focused,
            placeholder: promptPlaceholder,
            isBusy: isBusy,
            onNewTask: startNewTask,
            onStop: stopParentAgent,
            onSubmit: submit
        )
        }
    }

    private var promptPlaceholder: String {
        taskStore.pendingQuestion == nil ? "What do you want to build, fix, or review?" : "Reply to Droid"
    }

    private var isBusy: Bool {
        guard taskStore.pendingQuestion == nil else { return false }
        guard let status = taskStore.activeTask?.status else { return false }
        return status == .planning || status == .running
    }

    private func startNewTask() {
        prompt = ""
        taskStore.clearActiveTask()
        focused = true
    }

    private func stopParentAgent() {
        ParentAgentController.shared.stop()
        focused = true
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prompt = ""
        onSubmit(text)
    }
}
