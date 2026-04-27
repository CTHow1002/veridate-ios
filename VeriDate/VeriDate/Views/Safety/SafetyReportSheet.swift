import SwiftUI

struct SafetyReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SafetyViewModel()
    @State private var reason: SafetyReportReason = .inappropriateBehavior
    @State private var details = ""

    let reporterUserId: UUID
    let reportedUserId: UUID
    let matchId: UUID?
    let reportedName: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        ForEach(SafetyReportReason.allCases) { reason in
                            Text(reason.rawValue).tag(reason)
                        }
                    }
                }

                Section("Details") {
                    TextField("Optional details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report \(reportedName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(vm.isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Submitting..." : "Submit") {
                        Task {
                            let didSubmit = await vm.submitReport(
                                reporterUserId: reporterUserId,
                                reportedUserId: reportedUserId,
                                matchId: matchId,
                                reason: reason,
                                details: details
                            )

                            if didSubmit {
                                dismiss()
                            }
                        }
                    }
                    .disabled(vm.isSubmitting)
                }
            }
        }
    }
}
