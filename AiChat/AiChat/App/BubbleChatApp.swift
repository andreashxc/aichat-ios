import Combine
import SwiftData
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        ModelDownloadManager.shared.setBackgroundCompletionHandler(
            completionHandler,
            for: identifier
        )
    }
}

@main
struct BubbleChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var startupState: AppStartupState

    init() {
        _startupState = StateObject(wrappedValue: AppStartupState())
    }

    var body: some Scene {
        WindowGroup {
            if let environment = startupState.environment,
               let modelContainer = startupState.modelContainer {
                ConversationListView()
                    .environmentObject(environment)
                    .modelContainer(modelContainer)
            } else if let startupError = startupState.startupError {
                StartupErrorView(error: startupError)
            }
        }
    }
}

@MainActor
final class AppStartupState: ObservableObject {
    let modelContainer: ModelContainer?
    let environment: AppEnvironment?
    let startupError: AppStartupError?

    init() {
        do {
            let container = try ModelContainer(
                for: Conversation.self,
                ChatMessage.self,
                LocalModelDescriptor.self
            )
            self.modelContainer = container
            self.environment = AppEnvironment(modelContainer: container)
            self.startupError = nil
        } catch {
            self.modelContainer = nil
            self.environment = nil
            self.startupError = AppStartupError(message: error.localizedDescription)
            Logger.shared.error("Failed to start model container: \(error.localizedDescription)")
        }
    }
}

struct AppStartupError: Identifiable {
    let id = UUID()
    let message: String
}

private struct StartupErrorView: View {
    let error: AppStartupError

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("AiChat could not open its data store")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Your conversations are not available right now. Restart the app and, if this keeps happening, collect logs with the error below.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(error.message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
    }
}
