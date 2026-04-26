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

                    RangeSliderSection(
                        title: "Age",
                        unit: "years old",
                        minValue: $vm.minAge,
                        maxValue: $vm.maxAge,
                        bounds: 18...100,
                        step: 1
                    )

                    TextField("City", text: $vm.preferredCity)
                        .textInputAutocapitalization(.words)

                    RangeSliderSection(
                        title: "Distance",
                        unit: "km",
                        minValue: $vm.minDistanceKm,
                        maxValue: $vm.maxDistanceKm,
                        bounds: 0...200,
                        step: 5
                    )

                    RangeSliderSection(
                        title: "Height",
                        unit: "cm",
                        minValue: $vm.minHeightCm,
                        maxValue: $vm.maxHeightCm,
                        bounds: 120...220,
                        step: 1
                    )
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

private struct RangeSliderSection: View {
    let title: String
    let unit: String
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let bounds: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text("\(min(minValue, maxValue)) - \(max(minValue, maxValue)) \(unit)")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Minimum")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(minValue) },
                        set: { newValue in
                            minValue = Int(newValue.rounded())
                            if minValue > maxValue {
                                maxValue = minValue
                            }
                        }
                    ),
                    in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                    step: Double(step)
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Maximum")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(maxValue) },
                        set: { newValue in
                            maxValue = Int(newValue.rounded())
                            if maxValue < minValue {
                                minValue = maxValue
                            }
                        }
                    ),
                    in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                    step: Double(step)
                )
            }
        }
        .padding(.vertical, 4)
    }
}
