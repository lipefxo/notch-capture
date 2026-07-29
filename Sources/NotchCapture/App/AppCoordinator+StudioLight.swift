extension AppCoordinator {
    func configureStudioLight() {
        guard !previewMode else { return }
        studioLightService.onChange = { [weak self] state in
            self?.viewModel.studioLightState = state
        }
        viewModel.studioLightState = studioLightService.state
    }
}
