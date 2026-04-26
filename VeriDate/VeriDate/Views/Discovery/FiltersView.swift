import SwiftUI

struct FiltersView: View {
    @ObservedObject var vm: DiscoveryViewModel
    let userId: UUID
    let currentProfile: Profile?
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Who You Want To Meet") {
                    Picker("Preferred gender", selection: preferredGenderBinding) {
                        Text("Any").tag("")
                        ForEach(GenderType.allCases, id: \.self) { gender in
                            Text(display(gender.rawValue)).tag(gender.rawValue)
                        }
                    }

                    Stepper("Min age: \(vm.minAge)", value: $vm.minAge, in: 18...100)
                    Stepper("Max age: \(vm.maxAge)", value: $vm.maxAge, in: 18...100)

                    TextField("City", text: $vm.preferredCity)
                        .textInputAutocapitalization(.words)

                    Stepper("Min height: \(vm.minHeightCm) cm", value: $vm.minHeightCm, in: 120...220)
                }

                Section("Background") {
                    Picker("Education", selection: $vm.educationLevel) {
                        Text("Any").tag("")
                        ForEach(ProfileSetupViewModel.educationLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }

                    Picker("Relationship goal", selection: relationshipGoalBinding) {
                        Text("Any").tag("")
                        ForEach(RelationshipIntention.allCases, id: \.self) { goal in
                            Text(display(goal.rawValue)).tag(goal.rawValue)
                        }
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

    private var preferredGenderBinding: Binding<String> {
        Binding(
            get: { vm.preferredGender?.rawValue ?? "" },
            set: { vm.preferredGender = GenderType(rawValue: $0) }
        )
    }

    private var relationshipGoalBinding: Binding<String> {
        Binding(
            get: { vm.relationshipGoal?.rawValue ?? "" },
            set: { vm.relationshipGoal = RelationshipIntention(rawValue: $0) }
        )
    }

    private func display(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
