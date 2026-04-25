import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var session: SessionViewModel
    @StateObject private var vm = ProfileSetupViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic") {
                    TextField("Full name", text: $vm.fullName)
                    TextField("Date of birth, e.g. 1995-10-02", text: $vm.dateOfBirth)
                    Picker("Gender", selection: $vm.gender) {
                        ForEach(GenderType.allCases, id: \.self) { gender in
                            Text(gender.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    TextField("City", text: $vm.city)
                    TextField("Height in cm", text: $vm.heightCm)
                }

                Section("Work & Education") {
                    TextField("Job title", text: $vm.jobTitle)
                    TextField("Company", text: $vm.companyName)
                    TextField("Education level", text: $vm.educationLevel)
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
