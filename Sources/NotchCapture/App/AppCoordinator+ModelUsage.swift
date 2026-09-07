extension AppCoordinator {
    func configureModelUsage() {
        guard !previewMode else { return }
        modelUsageService.onChange = { [weak self] state in
            self?.viewModel.modelUsageState = state
        }
        viewModel.modelUsageState = modelUsageService.state
    }
}
