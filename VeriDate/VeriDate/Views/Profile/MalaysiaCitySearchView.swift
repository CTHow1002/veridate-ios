import Combine
import MapKit
import SwiftUI

struct MalaysiaCitySearchView: View {
    let title: String
    @Binding var selectedCity: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = MalaysiaCitySearchViewModel()

    var body: some View {
        NavigationStack {
            List {
                if vm.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        AppLanguageManager.localized("citySearch.empty.title"),
                        systemImage: "map",
                        description: Text(AppLanguageManager.localized("citySearch.empty.description"))
                    )
                    .accessibilityElement(children: .combine)
                } else if vm.isSearching {
                    HStack {
                        ProgressView()
                            .accessibilityHidden(true)
                        Text(AppLanguageManager.localized("citySearch.searching"))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if vm.results.isEmpty {
                    ContentUnavailableView(
                        AppLanguageManager.localized("citySearch.noResults.title"),
                        systemImage: "magnifyingglass",
                        description: Text(AppLanguageManager.localized("citySearch.noResults.description"))
                    )
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(vm.results, id: \.self) { result in
                        Button {
                            Task {
                                let city = await vm.cityName(for: result)
                                selectedCity = city
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.title)
                                    .foregroundStyle(.primary)

                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityLabel(cityResultAccessibilityLabel(for: result))
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchText, prompt: AppLanguageManager.localized("citySearch.searchPrompt"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLanguageManager.localized("common_cancel")) {
                        dismiss()
                    }
                    .accessibilityLabel(AppLanguageManager.localized("common_cancel"))
                }
            }
        }
    }
    private func cityResultAccessibilityLabel(for result: MKLocalSearchCompletion) -> String {
        if result.subtitle.isEmpty {
            return result.title
        }

        return String.localizedStringWithFormat(
            AppLanguageManager.localized("citySearch.result.accessibilityLabelFormat"),
            result.title,
            result.subtitle
        )
    }
}

@MainActor
private final class MalaysiaCitySearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchText = "" {
        didSet {
            updateSearchText()
        }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 4.2105, longitude: 101.9758),
            span: MKCoordinateSpan(latitudeDelta: 10.5, longitudeDelta: 10.5)
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let malaysiaResults = completer.results.filter { result in
            result.subtitle.localizedCaseInsensitiveContains("Malaysia") ||
            result.title.localizedCaseInsensitiveContains("Malaysia") ||
            !result.subtitle.localizedCaseInsensitiveContains("Singapore")
        }

        results = malaysiaResults
        isSearching = false
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        isSearching = false
    }

    func cityName(for result: MKLocalSearchCompletion) async -> String {
        let request = MKLocalSearch.Request(completion: result)
        request.region = completer.region

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                return cityStateText(from: item) ?? cleanedFallback(for: result)
            }
        } catch {
            return cleanedFallback(for: result)
        }

        return cleanedFallback(for: result)
    }

    private func updateSearchText() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        isSearching = !trimmed.isEmpty
        completer.queryFragment = trimmed.isEmpty ? "" : "\(trimmed) Malaysia"
    }

    private func cityStateText(from item: MKMapItem) -> String? {
        if let cityWithContext = item.addressRepresentations?.cityWithContext,
           let cityState = conciseCityState(from: cityWithContext) {
            return cityState
        }

        if let fullAddress = item.address?.fullAddress,
           let cityState = conciseCityState(from: fullAddress) {
            return cityState
        }

        return item.name
    }

    private func conciseCityState(from address: String) -> String? {
        var parts = address
            .replacingOccurrences(of: "\n", with: ",")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        parts.removeAll { part in
            let lowercased = part.lowercased()
            return lowercased == "malaysia" || lowercased == "my"
        }

        guard parts.count >= 2 else {
            return parts.first
        }

        let city = parts[parts.count - 2]
        let state = parts[parts.count - 1]
        return "\(city), \(state)"
    }

    private func cleanedFallback(for result: MKLocalSearchCompletion) -> String {
        var parts = [result.title, result.subtitle]
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        parts.removeAll { part in
            let lowercased = part.lowercased()
            return lowercased == "malaysia" || lowercased == "my"
        }

        return parts.prefix(2).joined(separator: ", ")
    }
}
