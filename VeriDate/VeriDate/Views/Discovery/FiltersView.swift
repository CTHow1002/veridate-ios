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

            RangeSlider(
                minValue: $minValue,
                maxValue: $maxValue,
                bounds: bounds,
                step: step
            )
        }
        .padding(.vertical, 4)
    }
}

private struct RangeSlider: View {
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let bounds: ClosedRange<Int>
    let step: Int

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - thumbSize, 1)
            let minX = xPosition(for: minValue, width: width)
            let maxX = xPosition(for: maxValue, width: width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: trackHeight)
                    .offset(x: thumbSize / 2)

                Capsule()
                    .fill(.tint)
                    .frame(width: max(maxX - minX, 0), height: trackHeight)
                    .offset(x: minX + thumbSize / 2)

                thumb
                    .offset(x: minX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                minValue = snappedValue(for: value.location.x - thumbSize / 2, width: width)
                                if minValue > maxValue {
                                    minValue = maxValue
                                }
                            }
                    )
                    .accessibilityLabel("Minimum")
                    .accessibilityValue("\(minValue)")

                thumb
                    .offset(x: maxX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                maxValue = snappedValue(for: value.location.x - thumbSize / 2, width: width)
                                if maxValue < minValue {
                                    maxValue = minValue
                                }
                            }
                    )
                    .accessibilityLabel("Maximum")
                    .accessibilityValue("\(maxValue)")
            }
            .frame(height: thumbSize)
        }
        .frame(height: 36)
    }

    private var thumb: some View {
        Circle()
            .fill(.background)
            .frame(width: thumbSize, height: thumbSize)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
            .overlay {
                Circle()
                    .stroke(.tint, lineWidth: 2)
            }
    }

    private func xPosition(for value: Int, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
        let percent = CGFloat(clamped - bounds.lowerBound) / CGFloat(bounds.upperBound - bounds.lowerBound)
        return percent * width
    }

    private func snappedValue(for xPosition: CGFloat, width: CGFloat) -> Int {
        let percent = min(max(xPosition / width, 0), 1)
        let rawValue = Double(bounds.lowerBound) + Double(percent) * Double(bounds.upperBound - bounds.lowerBound)
        let steppedValue = (rawValue / Double(step)).rounded() * Double(step)
        return min(max(Int(steppedValue), bounds.lowerBound), bounds.upperBound)
    }
}
