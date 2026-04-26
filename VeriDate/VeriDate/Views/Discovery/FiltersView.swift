import SwiftUI

struct FiltersView: View {
    @ObservedObject var vm: DiscoveryViewModel
    let userId: UUID
    let currentProfile: Profile?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Distance") {
                    LabeledContent("Maximum") {
                        Text("\(vm.maxDistanceKm) km")
                    }

                    Slider(
                        value: Binding(
                            get: { Double(vm.maxDistanceKm) },
                            set: { vm.maxDistanceKm = Int($0.rounded()) }
                        ),
                        in: 0...200,
                        step: 5
                    )
                }

                if currentProfile?.latitude == nil || currentProfile?.longitude == nil {
                    Section {
                        Label("Add your location in your profile to use distance matching.", systemImage: "location")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let saved = await vm.saveFilters(userId: userId)
                            if saved {
                                await vm.loadProfiles(userId: userId, currentProfile: currentProfile)
                                onDone()
                            }
                        }
                    } label: {
                        if vm.isSavingFilters {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(vm.isSavingFilters)
                }
            }
        }
    }
}
