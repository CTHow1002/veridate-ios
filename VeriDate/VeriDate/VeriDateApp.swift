import SwiftUI
import UserNotifications
import UIKit
import ObjectiveC

enum AppLanguagePreferenceKey {
    static let selectedLanguage = "app.language.selected"

    static let defaults: [String: Any] = [
        selectedLanguage: AppLanguage.english.rawValue
    ]
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var localeIdentifier: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .english:
            return AppLanguageManager.localized("language.english")
        case .chineseSimplified:
            return AppLanguageManager.localized("language.chineseSimplified")
        }
    }

    var nativeTitle: String {
        switch self {
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        }
    }
}

private var localizedBundleAssociationKey: UInt8 = 0

private final class AppLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let path = objc_getAssociatedObject(self, &localizedBundleAssociationKey) as? String,
              let bundle = Bundle(path: path) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }

        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

enum AppLanguageManager {
    static let didChangeNotification = Notification.Name("AppLanguageDidChange")

    static var currentLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: AppLanguagePreferenceKey.selectedLanguage)
            ?? AppLanguage.english.rawValue
        return AppLanguage(rawValue: rawValue) ?? .english
    }

    static var currentLocale: Locale {
        Locale(identifier: currentLanguage.localeIdentifier)
    }

    static func localized(_ key: String) -> String {
        guard
            let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguagePreferenceKey.selectedLanguage)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else {
            return
        }

        object_setClass(Bundle.main, AppLocalizedBundle.self)
        objc_setAssociatedObject(
            Bundle.main,
            &localizedBundleAssociationKey,
            path,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func notifyChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

private struct AppLanguageRefreshIDKey: EnvironmentKey {
    static let defaultValue = UUID()
}

extension EnvironmentValues {
    var appLanguageRefreshID: UUID {
        get { self[AppLanguageRefreshIDKey.self] }
        set { self[AppLanguageRefreshIDKey.self] = newValue }
    }
}

enum NotificationPreferenceKey {
    static let pushEnabled = "notification.push.enabled"
    static let inAppMessagesEnabled = "notification.inAppMessages.enabled"
    static let messageAlertsEnabled = "notification.messages.enabled"
    static let matchAlertsEnabled = "notification.matches.enabled"
    static let accountAlertsEnabled = "notification.account.enabled"

    static let defaults: [String: Any] = [
        pushEnabled: false,
        inAppMessagesEnabled: true,
        messageAlertsEnabled: true,
        matchAlertsEnabled: true,
        accountAlertsEnabled: true
    ]
}

enum PrivacyPreferenceKey {
    static let showOnlineStatus = "privacy.showOnlineStatus"
    static let sendReadReceipts = "privacy.sendReadReceipts"
    static let showDistance = "privacy.showDistance"

    static let defaults: [String: Any] = [
        showOnlineStatus: true,
        sendReadReceipts: true,
        showDistance: true
    ]
}

enum DataStoragePreferenceKey {
    static let reducePhotoPreloading = "dataStorage.reducePhotoPreloading"
    static let useCellularForMedia = "dataStorage.useCellularForMedia"
    static let autoDownloadReceivedMedia = "dataStorage.autoDownloadReceivedMedia"

    static let defaults: [String: Any] = [
        reducePhotoPreloading: false,
        useCellularForMedia: true,
        autoDownloadReceivedMedia: false
    ]
}

private extension Notification.Name {
    static let appShouldMarkPresenceOffline = Notification.Name("AppShouldMarkPresenceOffline")
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        UserDefaults.standard.register(defaults: NotificationPreferenceKey.defaults)
        UserDefaults.standard.register(defaults: PrivacyPreferenceKey.defaults)
        UserDefaults.standard.register(defaults: DataStoragePreferenceKey.defaults)
        UserDefaults.standard.register(defaults: AppLanguagePreferenceKey.defaults)

        let rawLanguage = UserDefaults.standard.string(forKey: AppLanguagePreferenceKey.selectedLanguage) ?? AppLanguage.english.rawValue
        AppLanguageManager.apply(AppLanguage(rawValue: rawLanguage) ?? .english)

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        if UserDefaults.standard.bool(forKey: NotificationPreferenceKey.pushEnabled) {
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
        let token = tokenParts.joined()

        print("APNs Token:", token)

        // Post token for later saving (e.g., to Supabase)
        NotificationCenter.default.post(name: Notification.Name("DidReceivePushToken"), object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications:", error)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        NotificationCenter.default.post(name: .appShouldMarkPresenceOffline, object: nil)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        NotificationCenter.default.post(name: .appShouldMarkPresenceOffline, object: nil)
    }

    // Handle notification when app is foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle tap on notification
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo

        // Forward payload to app (e.g., navigate to chat)
        NotificationCenter.default.post(name: Notification.Name("DidTapPushNotification"), object: userInfo)

        completionHandler()
    }
}

@main
struct VeriDateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = SessionViewModel()
    @State private var splashFinished = false
    @AppStorage(AppLanguagePreferenceKey.selectedLanguage) private var selectedLanguage = AppLanguage.english.rawValue
    @State private var activeLocaleIdentifier = AppLanguage.english.localeIdentifier
    @State private var languageRefreshID = UUID()

    private var appLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguage) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if splashFinished {
                    RootView()
                        .environmentObject(session)
                } else {
                    SplashView(isFinished: $splashFinished)
                }
            }
            .id(languageRefreshID)
            .environment(\.locale, Locale(identifier: activeLocaleIdentifier))
            .environment(\.appLanguageRefreshID, languageRefreshID)
            .onAppear {
                refreshLanguage(appLanguage)
            }
            .onChange(of: selectedLanguage) { _, newValue in
                refreshLanguage(AppLanguage(rawValue: newValue) ?? .english)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppLanguageManager.didChangeNotification)) { _ in
                refreshLanguage(AppLanguageManager.currentLanguage)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appShouldMarkPresenceOffline)) { _ in
                updatePresenceForLifecycle(isOnline: false)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                updatePresenceForLifecycle(isOnline: true)
            case .inactive, .background:
                updatePresenceForLifecycle(isOnline: false)
            @unknown default:
                break
            }
        }
    }

    private func refreshLanguage(_ language: AppLanguage) {
        print("🌐 VeriDateApp refreshLanguage:", language.rawValue, language.localeIdentifier)
        AppLanguageManager.apply(language)
        activeLocaleIdentifier = language.localeIdentifier
        languageRefreshID = UUID()
    }

    private func updatePresenceForLifecycle(isOnline: Bool) {
        let backgroundTask: UIBackgroundTaskIdentifier = isOnline
            ? .invalid
            : UIApplication.shared.beginBackgroundTask(withName: "UpdatePresenceOffline")

        Task {
            await session.updatePresence(isOnline: isOnline, reportErrors: false)

            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }
    }
}
