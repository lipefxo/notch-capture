extension AppCoordinator {
    func configureAudioOutput() {
        guard !previewMode else { return }
        audioOutputService.onChange = { [weak self] state in
            self?.viewModel.audioOutputState = state
        }
        viewModel.audioOutputState = audioOutputService.state
    }
}
