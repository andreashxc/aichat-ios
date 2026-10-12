import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct BottomSentinelPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatView: View {
    private let bottomSentinelID = "chat-bottom-sentinel"
    private let scrollCoordinateSpace = "chat-scroll-space"
    private let bottomVisibilityThreshold: CGFloat = 96

    @StateObject var viewModel: ChatViewModel
    let showsBackButton: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var showEditTitleSheet = false
    @State private var showEditEmojiSheet = false
    @State private var showConversationActions = false
    @State private var showDeleteConfirmation = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var isUserAtBottom = true
    @State private var lastReadMessageCount = 0
    @FocusState private var isComposerFocused: Bool
    @State private var availableModels: [ModelSelection] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var imageAttachments: [ImageAttachment] = []
    @State private var audioAttachments: [AudioAttachment] = []
    @State private var isSelectionMode = false
    @State private var selectedBubbleIDs: Set<String> = []
    @State private var quotedTextOverrides: [String: String] = [:]
    @State private var quoteDraft = ""
    @State private var quoteTargetId: String?
    @State private var showQuoteSheet = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var composerInsetHeight: CGFloat = 0
    @State private var forceNextScrollToBottom = false
    @State private var scrollRequestID = UUID()

    // Synchronized model selection - reads from and writes to environment.providerConfig
    private var selectedModel: ModelSelection? {
        get {
            // Get selected model based on current provider and model from config
            guard let modelId = environment.providerConfig.currentModelId else { return nil }
            return availableModels.first { $0.id == "\(environment.providerConfig.activeProvider.rawValue)-\(modelId)" }
        }
        nonmutating set {
            // Update the config when model is selected
            if let newValue = newValue {
                environment.providerConfig.activeProvider = newValue.provider
                environment.providerConfig.updateCurrentModel(newValue.model.modelId)
                viewModel.updateModel(provider: newValue.provider, modelId: newValue.model.modelId)
                Logger.shared.info("ChatView: Model selection synced: \(newValue.provider.rawValue) - \(newValue.model.modelId)")
            }
        }
    }

    private var scrollFollowKey: String {
        let lastMessage = viewModel.messages.last
        return [
            "\(viewModel.messages.count)",
            lastMessage?.id.uuidString ?? "none",
            "\(lastMessage?.text.count ?? 0)",
            "\(viewModel.showTypingIndicator)"
        ].joined(separator: "|")
    }

    var body: some View {
        contentView
            .navigationBarTitleDisplayMode(.inline)
            .background(BackSwipeEnabler())
            .navigationBarBackButtonHidden(true)
            .toolbar {
                chatToolbar
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showEditTitleSheet) {
                EditConversationTitleSheet(
                    isPresented: $showEditTitleSheet,
                    title: viewModel.conversation.title
                ) { newTitle in
                    viewModel.updateTitle(newTitle)
                }
            }
            .sheet(isPresented: $showEditEmojiSheet) {
                EditConversationEmojiSheet(
                    isPresented: $showEditEmojiSheet,
                    emoji: viewModel.conversation.emoji ?? "💬"
                ) { newEmoji in
                    viewModel.updateEmoji(newEmoji)
                }
            }
        .sheet(isPresented: $showQuoteSheet) {
            VStack(spacing: 16) {
                Text("Quote")
                    .font(.headline)

                TextEditor(text: $quoteDraft)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .systemGray6))
                    )

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showQuoteSheet = false
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button("Save") {
                        saveQuote()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .presentationDetents([.medium])
        }
            .confirmationDialog("Conversation", isPresented: $showConversationActions, titleVisibility: .visible) {
                Button("Rename") {
                    showEditTitleSheet = true
                }
                Button("Change Emoji") {
                    showEditEmojiSheet = true
                }
                Button("Delete", role: .destructive) {
                    showDeleteConfirmation = true
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete Conversation", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConversation()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this conversation? This action cannot be undone.")
            }
            .onAppear {
                loadAvailableModels()
            }
            .onChange(of: downloadManager.downloadedModels) { _, _ in
                loadAvailableModels()
            }
            .onChange(of: selectedPhotos) { _, newItems in
                handlePhotoSelection(newItems)
            }
            .onChange(of: supportsImageAttachments) { _, supports in
                if !supports {
                    selectedPhotos = []
                    imageAttachments = []
                }
            }
            .onChange(of: supportsAudioAttachments) { _, supports in
                if !supports {
                    audioAttachments = []
                }
            }
            .onChange(of: speechRecognizer.transcript) {
                // Update composer text with transcribed speech
                if !speechRecognizer.transcript.isEmpty {
                    viewModel.composerText = speechRecognizer.transcript
                }
            }
        .onChange(of: isSelectionMode) { _, isEnabled in
            if isEnabled {
                isComposerFocused = false
            } else {
                selectedBubbleIDs.removeAll()
            }
        }
            .onDisappear {
                viewModel.persistDraftAndCleanupIfNeeded()
            }
            .alert("Speech Recognition Error", isPresented: .constant(speechRecognizer.errorMessage != nil)) {
                Button("OK") {
                    speechRecognizer.reset()
                }
            } message: {
                if let error = speechRecognizer.errorMessage {
                    Text(error)
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        chatScrollView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomInsetView
            }
            .overlay(alignment: .bottomTrailing) {
                newMessagesButton
            }
    }

    @ViewBuilder
    private var bottomInsetView: some View {
        Group {
            if isSelectionMode {
                selectionActionBar
            } else {
                composerView
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ComposerHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { height in
            composerInsetHeight = height
        }
    }

    @ViewBuilder
    private var newMessagesButton: some View {
        if !isUserAtBottom && unreadMessageCount > 0 {
            Button {
                isUserAtBottom = true
                lastReadMessageCount = viewModel.messages.count
                requestScrollToBottom()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(unreadMessageCount)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: [.black, Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, max(composerInsetHeight + 12, 72))
            .transition(.opacity.combined(with: .scale))
        }
    }

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        if showsBackButton {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        ToolbarItem(placement: .principal) {
            ModelSelectorMenu(
                availableModels: availableModels,
                selectedModel: Binding(
                    get: { selectedModel },
                    set: { selectedModel = $0 }
                )
            )
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showConversationActions = true
            } label: {
                Text(viewModel.conversation.emoji ?? "💬")
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    private func toggleRecording() async {
        if speechRecognizer.isRecording {
            // Stop recording
            speechRecognizer.stopRecording()
        } else {
            // Start recording
            speechRecognizer.reset()
            do {
                try await speechRecognizer.startRecording()
            } catch {
                // Error will be displayed via alert
            }
        }
    }

    private func handleClarify(_ message: ChatMessage) {
        let messagePreview = message.text.prefix(100)
        let replyText = "Can you clarify: \"\(messagePreview)\(message.text.count > 100 ? "..." : "")\""
        forceNextScrollToBottom = true
        viewModel.sendReply(replyText, replyingTo: message)
        requestScrollToBottom()
    }

    private func handleTellMeMore(_ message: ChatMessage) {
        let replyText = "Tell me more about this"
        forceNextScrollToBottom = true
        viewModel.sendReply(replyText, replyingTo: message)
        requestScrollToBottom()
    }

    private var unreadMessageCount: Int {
        max(0, viewModel.messages.count - lastReadMessageCount)
    }

    private var selectedDisplayItems: [MessageDisplayItem] {
        displayItems.filter { selectedBubbleIDs.contains($0.id) }
    }

    private var selectedText: String {
        selectedDisplayItems
            .map { quotedTextOverrides[$0.id] ?? $0.paragraphText }
            .joined(separator: "\n\n")
    }

    private func toggleSelection(for item: MessageDisplayItem) {
        if selectedBubbleIDs.contains(item.id) {
            selectedBubbleIDs.remove(item.id)
            quotedTextOverrides[item.id] = nil
        } else {
            selectedBubbleIDs.insert(item.id)
        }
        if selectedBubbleIDs.isEmpty {
            isSelectionMode = false
        }
    }

    private func startSelection(with item: MessageDisplayItem) {
        isSelectionMode = true
        selectedBubbleIDs = [item.id]
    }

    private func startQuote(with item: MessageDisplayItem) {
        isSelectionMode = true
        selectedBubbleIDs = [item.id]
        quoteDraft = item.paragraphText
        quoteTargetId = item.id
        showQuoteSheet = true
    }

    private func saveQuote() {
        let trimmed = quoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let targetId = quoteTargetId else {
            showQuoteSheet = false
            return
        }
        if trimmed.isEmpty {
            quotedTextOverrides[targetId] = nil
        } else {
            quotedTextOverrides[targetId] = trimmed
        }
        showQuoteSheet = false
    }

    private func copySelected() {
        let text = selectedText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedBubbleIDs.removeAll()
        quotedTextOverrides.removeAll()
    }

    private func requestScrollToBottom() {
        lastReadMessageCount = viewModel.messages.count
        scrollRequestID = UUID()
    }

    private func scrollToBottom(proxy: ScrollViewProxy?, animated: Bool) {
        guard let proxy = proxy else { return }
        let action = {
            proxy.scrollTo(bottomSentinelID, anchor: .bottom)
        }

        if animated {
            withAnimation {
                action()
            }
        } else {
            action()
        }
    }

    private var messageListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Top padding to prevent navbar overlap
                Color.clear
                    .frame(height: 8)

                ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                    let previousItem = index > 0 ? displayItems[index - 1] : nil
                    let isSameMessageGroup = previousItem?.message.id == item.message.id
                    let isSameAuthor = previousItem?.message.role == item.message.role
                    
                    // Spacing logic:
                    // 1. If it's the same message (split into paragraphs), very small spacing
                    // 2. If it's the same author but different message, medium spacing
                    // 3. If it's a different author, large spacing
                    let spacing: CGFloat = isSameMessageGroup ? 4 : (isSameAuthor ? 8 : 16)
                    
                    if index > 0 {
                        Color.clear.frame(height: spacing)
                    }
                    
                    MessageBubbleView(
                        message: item.message,
                        paragraphText: item.paragraphText,
                        showTail: item.isLastInGroup && (index == displayItems.count - 1 || displayItems[index + 1].message.role != item.message.role),
                        onClarify: item.message.role == .assistant ? {
                            handleClarify(item.message)
                        } : nil,
                        onTellMeMore: item.message.role == .assistant ? {
                            handleTellMeMore(item.message)
                        } : nil,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedBubbleIDs.contains(item.id),
                        onToggleSelection: {
                            toggleSelection(for: item)
                        },
                        onStartSelection: {
                            startSelection(with: item)
                        },
                        onQuote: { _ in
                            startQuote(with: item)
                        },
                        onTap: {
                            if !isSelectionMode {
                                hideKeyboard()
                            }
                        }
                    )
                    .id(item.id)
                }
                if viewModel.showTypingIndicator {
                    HStack {
                        TypingIndicatorView()
                        Spacer(minLength: 60)
                    }
                    .padding(.leading, 24)
                    .transition(.opacity)
                    .id("typing-indicator")
                }

                // A real bottom anchor. The safeAreaInset supplies composer/keyboard spacing.
                Color.clear
                    .frame(height: 1)
                    .id(bottomSentinelID)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: BottomSentinelPreferenceKey.self,
                                value: proxy.frame(in: .named(scrollCoordinateSpace)).minY
                            )
                        }
                    )
            }
            .padding(.horizontal, 16)
        }
    }
    
    private struct MessageDisplayItem: Identifiable {
        let id: String
        let message: ChatMessage
        let paragraphText: String
        let isPartOfSplitMessage: Bool
        let isFirstInGroup: Bool
        let isLastInGroup: Bool
    }
    
    private var displayItems: [MessageDisplayItem] {
        var items: [MessageDisplayItem] = []
        for message in viewModel.messages {
            let paragraphs = ParagraphDeliveryPipeline.splitText(message.text)
            if paragraphs.count > 1 {
                // Split into multiple bubbles
                for (index, paragraph) in paragraphs.enumerated() {
                    items.append(MessageDisplayItem(
                        id: "\(message.id.uuidString)-\(index)",
                        message: message,
                        paragraphText: paragraph,
                        isPartOfSplitMessage: true,
                        isFirstInGroup: index == 0,
                        isLastInGroup: index == paragraphs.count - 1
                    ))
                }
            } else {
                // Single paragraph, display as-is
                items.append(MessageDisplayItem(
                    id: message.id.uuidString,
                    message: message,
                    paragraphText: message.text,
                    isPartOfSplitMessage: false,
                    isFirstInGroup: true,
                    isLastInGroup: true
                ))
            }
        }
        return items
    }


    private func loadAvailableModels() {
        availableModels = AvailableModelsProvider.getAllAvailableModels()

        // selectedModel now reads from environment.providerConfig automatically
        // No need to set it manually - the computed property getter handles it
    }

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            messageListView
                .background(Color(uiColor: .systemGroupedBackground))
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { _ in
                            hideKeyboard()
                        }
                )
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: ScrollViewportHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                    }
                )
                .coordinateSpace(name: scrollCoordinateSpace)
                .onPreferenceChange(ScrollViewportHeightPreferenceKey.self) { height in
                    guard height > 0 else { return }
                    let changed = abs(scrollViewportHeight - height) > 1
                    scrollViewportHeight = height
                    if changed && isUserAtBottom {
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }
                .onPreferenceChange(BottomSentinelPreferenceKey.self) { sentinelMinY in
                    updateBottomVisibility(sentinelMinY: sentinelMinY)
                }
                .onChange(of: scrollFollowKey) { _, _ in
                    let shouldScroll = forceNextScrollToBottom || isUserAtBottom
                    if forceNextScrollToBottom {
                        forceNextScrollToBottom = false
                    }
                    if shouldScroll {
                        DispatchQueue.main.async {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                    }
                }
                .onChange(of: scrollRequestID) { _, _ in
                    DispatchQueue.main.async {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    lastReadMessageCount = viewModel.messages.count
                    DispatchQueue.main.async {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
        }
    }

    private func updateBottomVisibility(sentinelMinY: CGFloat) {
        guard scrollViewportHeight > 0, sentinelMinY.isFinite else { return }
        let isNearBottom = sentinelMinY <= scrollViewportHeight + bottomVisibilityThreshold
        if isUserAtBottom != isNearBottom {
            isUserAtBottom = isNearBottom
        }
        if isNearBottom {
            lastReadMessageCount = viewModel.messages.count
        }
    }
    
    private func hideKeyboard() {
        isComposerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var composerView: some View {
        MessageComposerView(
            text: $viewModel.composerText,
            placeholder: "Message",
            isFocused: $isComposerFocused,
            isRecording: speechRecognizer.isRecording,
            isSending: viewModel.isSending,
            lineLimit: 1...4,
            selectedPhotos: $selectedPhotos,
            imageAttachments: $imageAttachments,
            audioAttachments: $audioAttachments,
            canAttachImages: supportsImageAttachments,
            canAttachAudio: supportsAudioAttachments,
            onRemoveAttachment: { attachmentId in
                imageAttachments.removeAll { $0.id == attachmentId }
            },
            onRemoveAudio: { attachmentId in
                audioAttachments.removeAll { $0.id == attachmentId }
            },
            onAudioPicked: { urls in
                handleAudioSelection(urls)
            },
            onSend: {
                let attachments = imageAttachments
                let audio = audioAttachments
                imageAttachments = []
                audioAttachments = []
                forceNextScrollToBottom = true
                viewModel.sendMessage(imageAttachments: attachments, audioAttachments: audio)
                requestScrollToBottom()
            },
            onStop: {
                viewModel.cancelGeneration()
            },
            onRecordToggle: {
                await toggleRecording()
            }
        )
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Button {
                copySelected()
            } label: {
                selectionToolbarLabel("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .disabled(selectedBubbleIDs.isEmpty)

            ShareLink(item: selectedText) {
                selectionToolbarLabel("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(selectedBubbleIDs.isEmpty || selectedText.isEmpty)

            Button {
                exitSelectionMode()
            } label: {
                selectionToolbarLabel("Done", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func selectionToolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: .black.opacity(GlassStyleConfig.navbar.shadowOpacity),
                        radius: GlassStyleConfig.navbar.shadowRadius,
                        y: GlassStyleConfig.navbar.shadowY
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(GlassStyleConfig.navbar.borderGradientStart),
                                Color.primary.opacity(GlassStyleConfig.navbar.borderGradientEnd)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }

    private var supportsImageAttachments: Bool {
        false
    }

    private var supportsAudioAttachments: Bool {
        selectedModel != nil
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let jpegData = uiImage.jpegData(compressionQuality: 0.9) {
                    await MainActor.run {
                        imageAttachments.append(ImageAttachment(data: jpegData, fileExtension: "jpg"))
                    }
                }
            }
            await MainActor.run {
                selectedPhotos = []
            }
        }
    }

    private func handleAudioSelection(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var newAttachments: [AudioAttachment] = []
            for url in urls {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted { url.stopAccessingSecurityScopedResource() }
                }
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
                let mimeType = AttachmentStore.mimeType(forFileExtension: ext)
                let fileName = url.lastPathComponent
                newAttachments.append(
                    AudioAttachment(
                        data: data,
                        fileExtension: ext,
                        fileName: fileName,
                        mimeType: mimeType
                    )
                )
            }
            await MainActor.run {
                audioAttachments.append(contentsOf: newAttachments)
            }
        }
    }
}

#Preview("Chat - iPhone SE", traits: .fixedLayout(width: 320, height: 568)) {
    ChatViewPreviewContainer()
}

#Preview("Chat - iPhone", traits: .fixedLayout(width: 393, height: 852)) {
    ChatViewPreviewContainer()
}

#Preview("Chat - Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    ChatViewPreviewContainer()
}

#Preview("Chat - Landscape", traits: .fixedLayout(width: 852, height: 393)) {
    ChatViewPreviewContainer()
}

#Preview("Chat - Accessibility Type", traits: .fixedLayout(width: 393, height: 852)) {
    ChatViewPreviewContainer()
        .environment(\.dynamicTypeSize, .accessibility3)
}

@MainActor
private struct ChatViewPreviewContainer: View {
    @StateObject private var environment: AppEnvironment
    @StateObject private var viewModel: ChatViewModel

    init() {
        let environment = ChatViewPreviewFactory.makeEnvironment()
        let conversationID = environment.activeConversation?.id
        _environment = StateObject(wrappedValue: environment)
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                environment: environment,
                conversationId: conversationID
            )
        )
    }

    var body: some View {
        NavigationStack {
            ChatView(viewModel: viewModel, showsBackButton: true)
        }
        .environmentObject(environment)
    }
}

@MainActor
private enum ChatViewPreviewFactory {
    static func makeEnvironment() -> AppEnvironment {
        let schema = Schema([
            Conversation.self,
            ChatMessage.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let environment = AppEnvironment(
            modelContainer: container,
            providerConfig: ProviderConfig(
                activeProvider: .foundationModels,
                foundationModel: "foundation-model"
            )
        )
        let conversation = environment.ensureConversation()
        conversation.title = "Layout Preview"
        conversation.providerId = .foundationModels
        conversation.modelName = "foundation-model"
        conversation.emoji = "💬"

        let samples: [(MessageRole, String)] = [
            (
                .assistant,
                "Here is a longer assistant response that wraps across several lines so the preview exercises bubble sizing, scroll behavior, and the bottom sentinel."
            ),
            (
                .user,
                "Can you keep this usable on a small phone with the keyboard open?"
            ),
            (
                .assistant,
                "Yes. The composer now sits in the safe area inset, so the scroll view receives the correct bottom inset from SwiftUI instead of relying on fixed padding."
            ),
            (
                .user,
                "Also check landscape and large text."
            ),
            (
                .assistant,
                "The preview includes narrow, regular, Pro Max, landscape, and accessibility Dynamic Type sizes."
            )
        ]

        for sample in samples {
            _ = try? environment.conversationStore.addMessage(
                text: sample.1,
                role: sample.0,
                conversationId: conversation.id,
                deliveryState: .delivered,
                sourceProvider: .foundationModels
            )
        }

        return environment
    }
}
