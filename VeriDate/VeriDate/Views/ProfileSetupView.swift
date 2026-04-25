import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ProfileSetupViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Full name", text: $vm.fullName)
                    DatePicker(
                        "Date of birth",
                        selection: $vm.dateOfBirth,
                        in: vm.birthDateRange,
                        displayedComponents: .date
                    )
                    Picker("Gender", selection: $vm.gender) {
                        ForEach(GenderType.allCases, id: \.self) { gender in
                            Text(gender.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    TextField("City", text: $vm.city)
                    Picker("Height", selection: $vm.heightCm) {
                        ForEach(120...220, id: \.self) { height in
                            Text("\(height) cm").tag(height)
                        }
                    }
                }

                Section("Work & Education") {
                    TextField("Job title", text: $vm.jobTitle)
                    TextField("Company", text: $vm.companyName)
                    Picker("Education level", selection: $vm.educationLevel) {
                        ForEach(ProfileSetupViewModel.educationLevels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    TextField("School / University", text: $vm.schoolName)
                }

                Section("Dating") {
                    Picker("Relationship goal", selection: $vm.relationshipGoal) {
                        ForEach(RelationshipIntention.allCases, id: \.self) { goal in
                            Text(goal.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    TextField("Bio", text: $vm.bio, axis: .vertical)
                }

                Section {
                    Button {
                        Task {
                            guard let userId = session.currentUserId else { return }
                            let saved = await vm.save(userId: userId)
                            if saved {
                                await session.loadProfile()
                            }
                        }
                    } label: {
                        if vm.isSaving {
                            ProgressView()
                        } else {
                            Text("Save & Continue to Verification")
                        }
                    }
                    .disabled(vm.isSaving)
                }

                if let error = vm.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Create Profile")
        }
    }
}
