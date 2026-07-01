import Foundation

extension SpeechInputController {
    func downloadSelectedModel() {
        runModelTask(.download)
    }

    func prepareSelectedModel() {
        runModelTask(.prepare)
    }

    func removeSelectedModel() {
        let model = selectedModel
        Task { [weak self] in
            guard let self else { return }
            await transcriber.unload()
            try? FileManager.default.removeItem(at: model.cacheURL)
            settingsStore.update { $0.isEnabled = false }
            cacheRefreshToken += 1
            status = .idle
            ToastState.shared.show("Speech model removed")
        }
    }

    func runModelTask(_ kind: SpeechModelTaskKind) {
        modelTaskRunner.run(
            kind: kind,
            model: selectedModel,
            onStatus: { [weak self] status in self?.status = status },
            onCacheChanged: { [weak self] in self?.cacheRefreshToken += 1 },
            onError: { [weak self] error in self?.handle(error) }
        )
    }
}
