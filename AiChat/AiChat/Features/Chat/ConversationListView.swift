import PhotosUI
import SwiftUI
import SwiftData
import UIKit

private let emojiCircleSize: CGFloat = 40
private let emojiFontSize: CGFloat = 20

struct ConversationListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var searchText = ""
    @State private var debouncedMessageSearchText = ""
    @State private var messageSearchConversationIDs: Set<UUID> = []
    @State private var messageSearchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var newChatText = ""
    @FocusState private var isNewChatFocused: Bool
    @FocusState private var isSearchFocused: Bool
    @State private var newConversationToOpen: Conversation?
    @State private var selectedConversation: Conversation?
    @State private var selectedConversationID: UUID?
    @State private var pendingAutoSendConversationID: UUID?
    @State private var showSettings = false
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var availableModels: [ModelSelection] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var imageAttachments: [ImageAttachment] = []
    @State private var audioAttachments: [AudioAttachment] = []
    private let serbianTranslatorTitle = "Сербский переводчик"
    private let serbianTranslatorEmoji = "🇷🇸"
    private let serbianTranslatorSystemPrompt = """
    Ты — AI-переводчик и языковой помощник для русскоязычных пользователей, работающий также с сербским языком. Твоя особенность — ты показываешь переводы и примеры **на сербском сразу в двух вариантах письма**: кириллице и латинице. Это помогает пользователю видеть и учить обе системы письма, которые официально используются в сербском языке.

    Ты автоматически определяешь намерение пользователя и работаешь по одному из трёх режимов:

    1) «Перевод»: если дано слово, фраза или текст для перевода (между сербским и русским, а также другими языками), выдай 3–6 вариантов перевода. Каждый сербский пример всегда приводи **в двух вариантах** — кириллицей и латиницей. Добавь краткие пояснения по грамматике, лексике и оттенкам значений.

    2) «Стилизация»: если просят подобрать вариант под контекст (например, «вежливо», «разговорно», «делово»), предложи несколько формулировок в разных регистрах: формальный, нейтральный, дружелюбный, краткий и т. д. Для каждого варианта — покажи сербскую версию и на кириллице, и на латинице. Объясни, где какой вариант уместен.

    3) «Разбор слова»: если введено одно слово или короткая фраза без контекста, выдай основные значения, примеры, типичные ошибки русскоязычных, формы, частотные коллокации и короткое пояснение об употреблении. Примеры сербских предложений показывай на обеих системах письма.

    Общие принципы:
    • Основные языки интерфейса — русский и сербский; ты можешь переключаться между ними по просьбе пользователя.
    • При показе сербского текста всегда давай обе формы: «кириллица / латиница» в паре.
    • Учитывай культурные и речевые различия между сербским и русским (например, обращение «ти» и «ви», различие в тонах вежливости, употребление уменьшительных форм и т. д.).
    • Объясняй грамматические особенности простыми словами, без избыточных терминов.
    • Формат ответов: чёткая структура, короткие абзацы, маркированные списки, дружелюбный профессиональный тон.
    • Не придумывай источники и не давай ложных примеров; если чего-то не знаешь, честно укажи.
    • Если возможны недопонимания из-за ложных друзей перевода или культурных нюансов — объясни их и предложи альтернативы.

    Ты — переводчик и стилист, потому что не просто переводишь слова, а помогаешь пользователю звучать естественно, вежливо и уместно на другом языке — адаптируешь стиль и культурный контекст, показывая при этом правильное написание и кириллицей, и латиницей.
    """
    private let factCheckAgentTitle = "Фактчекер"
    private let factCheckAgentEmoji = "🔎"
    private let factCheckAgentSystemPrompt = """
    Ты — ассистент, который дает ТОЛЬКО проверяемые ответы с опорой на источники.

    Цель: максимальная фактологическая точность и прослеживаемость. Если нет надежных данных — так и скажи и предложи, что именно нужно проверить.

    ОБЯЗАТЕЛЬНЫЕ ПРАВИЛА
    1) Источники по умолчанию:
       - Для любых фактов, чисел, дат, “кто сейчас”, “что изменилось”, “лучшее/самое” — сначала делай веб-поиск и опирайся на найденное.
       - Не используй память/интуицию для актуальных фактов, если это можно проверить.
    2) Цитирование:
       - Каждое ключевое утверждение (факт/цифра/дата/причина/сравнение) должно иметь ссылку на источник.
       - Отдавай приоритет первоисточникам: официальная документация, гос/междунар. организации, научные статьи, регуляторы, сайты компаний, репозитории.
       - Если источники противоречат — покажи расхождение и объясни, какой источник надежнее и почему.
    3) Уровень уверенности:
       - Для каждого ответа оцени уверенность: Высокая / Средняя / Низкая.
       - Если уверенность < Высокой — явно укажи, что именно неизвестно и какие данные нужны.
    4) Никаких выдумок:
       - Запрещено додумывать детали, “заполнять пробелы”, подставлять вероятные значения без пометки.
       - Если не знаешь — скажи “не нашел подтверждения”.
    5) Проверка формулировок:
       - Отлавливай скрытые предположения пользователя, двусмысленности, “всегда/никогда”, причинно-следственные заявления.
       - Если вопрос неоднозначен, дай лучший ответ по наиболее вероятной трактовке + список из 1–3 уточнений, которые сильнее всего повлияют на вывод.
    6) Структура ответа (по умолчанию):
       - 1–3 предложения: итоговый ответ.
       - Затем: “Доказательства” (буллеты с фактами + источники).
       - Затем (если нужно): “Ограничения/неопределенности”.
       - Затем (если уместно): “Что проверить дальше” (конкретные шаги/запросы).
    7) Короткие цитаты:
       - Прямые цитаты используй редко и коротко; лучше пересказывать и ссылаться.
    8) Безопасность:
       - Для медицины/юридического/финансового: не давать категоричных инструкций без оговорок; предлагать сверку с профессионалом; обязательно указывать источники.

    РЕЖИМЫ (если пользователь попросит)
    - “Только источники”: дай список источников + по 1 строке, что подтверждают.
    - “Сравнение”: таблица критериев + ссылки на подтверждения.
    - “Дебаг утверждения”: разложи тезис на проверяемые под-тезисы и проверь каждый.

    Стиль:
    - Нейтрально, без воды.
    - Термины определяй кратко, если они критичны для понимания.
    """

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
                Logger.shared.info("Model selection synced: \(newValue.provider.rawValue) - \(newValue.model.modelId)")
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if useSplitLayout(for: geometry.size) {
                splitLayout
            } else {
                stackLayout
            }
        }
    }

    private var stackLayout: some View {
        NavigationStack {
            listColumnContent(isSplitLayout: false)
                .navigationDestination(item: $newConversationToOpen) { conversation in
                    ChatView(
                        viewModel: ChatViewModel(
                            environment: environment,
                            conversationId: conversation.id,
                            autoSendFirstMessage: true
                        ),
                        showsBackButton: true
                    )
                }
                .navigationDestination(item: $selectedConversation) { conversation in
                    ChatView(
                        viewModel: ChatViewModel(
                            environment: environment,
                            conversationId: conversation.id
                        ),
                        showsBackButton: true
                    )
                }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            listColumnContent(isSplitLayout: true)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            splitDetailView
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedConversationID == nil {
                selectedConversationID = conversations.first?.id
            }
        }
        .onChange(of: conversations) { _, updatedConversations in
            if let selectedConversationID,
               !updatedConversations.contains(where: { $0.id == selectedConversationID }) {
                self.selectedConversationID = updatedConversations.first?.id
            } else if self.selectedConversationID == nil {
                self.selectedConversationID = updatedConversations.first?.id
            }
        }
    }

    private func useSplitLayout(for size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
    }

    private var splitDetailView: some View {
        Group {
            if let selectedConversationID,
               let conversation = conversations.first(where: { $0.id == selectedConversationID }) {
                ChatView(
                    viewModel: ChatViewModel(
                        environment: environment,
                        conversationId: conversation.id,
                        autoSendFirstMessage: pendingAutoSendConversationID == conversation.id
                    ),
                    showsBackButton: false
                )
                .id(conversation.id)
                .onAppear {
                    if pendingAutoSendConversationID == conversation.id {
                        pendingAutoSendConversationID = nil
                    }
                }
            } else {
                ContentUnavailableView("Выберите чат", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    private func listColumnContent(isSplitLayout: Bool) -> some View {
        conversationList(isSplitLayout: isSplitLayout)
            .safeAreaInset(edge: .bottom) {
                newChatComposer(preferSplitNavigation: isSplitLayout)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                        isSearching.toggle()
                        if isSearching {
                            isSearchFocused = true
                        } else {
                            searchText = ""
                            isSearchFocused = false
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                loadAvailableModels()
                environment.conversationStore.backfillConversationDerivedFieldsIfNeeded()
            }
            .onDisappear {
                cancelMessageSearch(resetResults: false)
            }
            .onChange(of: downloadManager.downloadedModels) { _, _ in
                loadAvailableModels()
            }
            .onChange(of: searchText) { _, newValue in
                scheduleMessageSearch(for: newValue)
            }
            .onChange(of: isSearching) { _, searching in
                if searching {
                    scheduleMessageSearch(for: searchText)
                } else {
                    cancelMessageSearch(resetResults: true)
                }
            }
            .onChange(of: speechRecognizer.transcript) {
                // Update composer text with transcribed speech
                if !speechRecognizer.transcript.isEmpty {
                    newChatText = speechRecognizer.transcript
                }
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
            .alert("Speech Recognition Error", isPresented: .constant(speechRecognizer.errorMessage != nil)) {
                Button("OK") {
                    speechRecognizer.reset()
                }
            } message: {
                if let error = speechRecognizer.errorMessage {
                    Text(error)
                }
            }
            .alert(item: $environment.persistenceError) { error in
                Alert(
                    title: Text("Persistence Error"),
                    message: Text("\(error.operation)\n\(error.message)"),
                    dismissButton: .default(Text("OK")) {
                        environment.clearPersistenceError()
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(environment: environment, showsCloseButton: true)
                }
            }
    }

    private func newChatComposer(preferSplitNavigation: Bool) -> some View {
        VStack(spacing: 0) {
            MessageComposerView(
                text: $newChatText,
                placeholder: "Start a new chat...",
                isFocused: $isNewChatFocused,
                isRecording: speechRecognizer.isRecording,
                lineLimit: 1...3,
                selectedPhotos: $selectedPhotos,
                imageAttachments: $imageAttachments,
                audioAttachments: $audioAttachments,
                canAttachImages: supportsImageAttachments,
                canAttachAudio: supportsAudioAttachments,
                onRemoveAttachment: removeImageAttachment,
                onRemoveAudio: removeAudioAttachment,
                onAudioPicked: handleAudioSelection,
                onSend: {
                    sendNewConversation(preferSplitNavigation: preferSplitNavigation)
                },
                onStop: nil,
                onRecordToggle: toggleRecording
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(Color.clear)
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

    private func conversationList(isSplitLayout: Bool) -> some View {
        Group {
            if isSearching {
                // Search view
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 17, weight: .medium))

                        TextField("Search conversations", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    Divider()

                    if filteredConversations.isEmpty {
                        searchEmptyState
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        hideKeyboard()
                                    }
                            )
                    } else {
                        conversationListContent(showAgentButton: false, isSplitLayout: isSplitLayout)
                    }
                }
            } else {
                if conversations.isEmpty {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            agentCreateCard(
                                title: serbianTranslatorTitle,
                                emoji: serbianTranslatorEmoji,
                                subtitle: "Переводы и стилизация для сербского языка",
                                action: {
                                    createSerbianTranslatorAgentConversation(preferSplitNavigation: isSplitLayout)
                                }
                            )
                            agentCreateCard(
                                title: factCheckAgentTitle,
                                emoji: factCheckAgentEmoji,
                                subtitle: "Проверяемые ответы со ссылками",
                                action: {
                                    createFactCheckAgentConversation(preferSplitNavigation: isSplitLayout)
                                }
                            )
                        }
                        .padding(.horizontal, 16)
                        emptyStateView
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        hideKeyboard()
                                    }
                            )
                    }
                } else {
                    conversationListContent(showAgentButton: true, isSplitLayout: isSplitLayout)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    hideKeyboard()
                }
        )
    }

    private func conversationListContent(showAgentButton: Bool, isSplitLayout: Bool) -> some View {
        List(selection: splitSelectionBinding(isSplitLayout: isSplitLayout)) {
            if showAgentButton {
                Section("Агенты") {
                    agentCreateCard(
                        title: serbianTranslatorTitle,
                        emoji: serbianTranslatorEmoji,
                        subtitle: "Переводы и стилизация для сербского языка",
                        action: {
                            createSerbianTranslatorAgentConversation(preferSplitNavigation: isSplitLayout)
                        }
                    )
                    agentCreateCard(
                        title: factCheckAgentTitle,
                        emoji: factCheckAgentEmoji,
                        subtitle: "Проверяемые ответы со ссылками",
                        action: {
                            createFactCheckAgentConversation(preferSplitNavigation: isSplitLayout)
                        }
                    )
                }
            }
            Section("Чаты") {
                ForEach(filteredConversations) { conversation in
                    rowContent(for: conversation)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSplitLayout {
                                selectedConversationID = conversation.id
                            } else {
                                selectedConversation = conversation
                            }
                        }
                        .tag(conversation.id)
                        .background(
                            Group {
                                if isSplitLayout && selectedConversationID == conversation.id {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func splitSelectionBinding(isSplitLayout: Bool) -> Binding<UUID?> {
        if isSplitLayout {
            return $selectedConversationID
        }

        return Binding<UUID?>(
            get: { nil },
            set: { _ in }
        )
    }

    private func rowContent(for conversation: Conversation) -> some View {
        ConversationRowView(conversation: conversation)
    }
    
    private func hideKeyboard() {
        isNewChatFocused = false
        isSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func removeImageAttachment(_ attachmentId: UUID) {
        imageAttachments.removeAll { $0.id == attachmentId }
    }

    private func removeAudioAttachment(_ attachmentId: UUID) {
        audioAttachments.removeAll { $0.id == attachmentId }
    }

    private var searchEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.primary)

            VStack(spacing: 4) {
                Text("No Results")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredConversations: [Conversation] {
        let trimmedSearchText = normalizedSearchText
        if trimmedSearchText.isEmpty {
            return conversations
        }

        let titleMatchIDs = Set(conversations.compactMap { conversation in
            conversation.title.localizedCaseInsensitiveContains(trimmedSearchText) ? conversation.id : nil
        })

        guard debouncedMessageSearchText == trimmedSearchText else {
            return conversations.filter { titleMatchIDs.contains($0.id) }
        }

        return conversations.filter { conversation in
            titleMatchIDs.contains(conversation.id) || messageSearchConversationIDs.contains(conversation.id)
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleMessageSearch(for text: String) {
        messageSearchTask?.cancel()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSearching, !trimmedText.isEmpty else {
            debouncedMessageSearchText = ""
            messageSearchConversationIDs = []
            return
        }

        let modelContainer = environment.modelContainer
        messageSearchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            let matchingConversationIDs = await Self.fetchConversationIDsMatchingMessageText(
                trimmedText,
                modelContainer: modelContainer
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                debouncedMessageSearchText = trimmedText
                messageSearchConversationIDs = matchingConversationIDs
            }
        }
    }

    private static func fetchConversationIDsMatchingMessageText(
        _ searchText: String,
        modelContainer: ModelContainer
    ) async -> Set<UUID> {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.text.localizedStandardContains(searchText)
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            let messages = (try? context.fetch(descriptor)) ?? []
            return Set(messages.map(\.conversationId))
        }.value
    }

    private func cancelMessageSearch(resetResults: Bool) {
        messageSearchTask?.cancel()
        messageSearchTask = nil

        if resetResults {
            debouncedMessageSearchText = ""
            messageSearchConversationIDs = []
        }
    }


    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 100, height: 100)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.primary)
            }

            VStack(spacing: 8) {
                Text("No Conversations")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Type a message below to start chatting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func agentCreateCard(
        title: String,
        emoji: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: emojiCircleSize, height: emojiCircleSize)

                    Text(emoji)
                        .font(.system(size: emojiFontSize))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func createNewConversation(
        attachments: [ImageAttachment] = [],
        audioAttachments: [AudioAttachment] = [],
        preferSplitNavigation: Bool = false
    ) {
        let trimmedText = newChatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty || !audioAttachments.isEmpty else { return }

        // Use selected model or fall back to active provider
        let providerId = selectedModel?.provider ?? environment.providerConfig.activeProvider
        let modelName = selectedModel?.model.modelId

        let attachmentPaths = buildAttachmentPaths(from: attachments)
        let audioPaths = buildAudioPaths(from: audioAttachments)

        let newConversation: Conversation
        do {
            newConversation = try environment.conversationStore.createConversation(
                title: "New Chat",
                providerId: providerId,
                modelName: modelName
            )

            _ = try environment.conversationStore.addMessage(
                text: trimmedText,
                role: .user,
                conversationId: newConversation.id,
                deliveryState: .delivered,
                sourceProvider: providerId,
                attachmentPaths: attachmentPaths,
                audioAttachmentPaths: audioPaths
            )
        } catch {
            AttachmentStore.deleteFiles(paths: attachmentPaths + audioPaths)
            return
        }

        // Clear the text field
        newChatText = ""
        isNewChatFocused = false

        if preferSplitNavigation {
            pendingAutoSendConversationID = newConversation.id
            selectedConversationID = newConversation.id
        } else {
            newConversationToOpen = newConversation
        }
    }

    private func sendNewConversation(preferSplitNavigation: Bool) {
        let attachments = imageAttachments
        let audio = audioAttachments
        imageAttachments = []
        audioAttachments = []
        createNewConversation(
            attachments: attachments,
            audioAttachments: audio,
            preferSplitNavigation: preferSplitNavigation
        )
    }

    private func loadAvailableModels() {
        availableModels = AvailableModelsProvider.getAllAvailableModels()

        // Set default selected model
        if selectedModel == nil, let firstModel = availableModels.first {
            selectedModel = firstModel
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selectedConversationID == conversation.id {
            selectedConversationID = nil
        }
        do {
            try environment.conversationStore.deleteConversation(conversation)
        } catch {}
    }

    private func createSerbianTranslatorAgentConversation(preferSplitNavigation: Bool = false) {
        let providerId = selectedModel?.provider ?? environment.providerConfig.activeProvider
        let modelName = selectedModel?.model.modelId
        let newConversation: Conversation
        do {
            newConversation = try environment.conversationStore.createConversation(
                title: "New Chat",
                providerId: providerId,
                modelName: modelName,
                systemPrompt: serbianTranslatorSystemPrompt
            )
        } catch {
            return
        }
        if preferSplitNavigation {
            selectedConversationID = newConversation.id
        } else {
            newConversationToOpen = newConversation
        }
    }

    private func createFactCheckAgentConversation(preferSplitNavigation: Bool = false) {
        let providerId = selectedModel?.provider ?? environment.providerConfig.activeProvider
        let modelName = selectedModel?.model.modelId
        let newConversation: Conversation
        do {
            newConversation = try environment.conversationStore.createConversation(
                title: "New Chat",
                providerId: providerId,
                modelName: modelName,
                systemPrompt: factCheckAgentSystemPrompt
            )
        } catch {
            return
        }
        if preferSplitNavigation {
            selectedConversationID = newConversation.id
        } else {
            newConversationToOpen = newConversation
        }
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

    private func buildAttachmentPaths(from attachments: [ImageAttachment]) -> [String] {
        guard !attachments.isEmpty else { return [] }
        var paths: [String] = []
        for attachment in attachments {
            if let path = AttachmentStore.saveImageData(attachment.data, fileExtension: attachment.fileExtension) {
                paths.append(path)
            }
        }
        return paths
    }

    private func buildAudioPaths(from attachments: [AudioAttachment]) -> [String] {
        guard !attachments.isEmpty else { return [] }
        var paths: [String] = []
        for attachment in attachments {
            if let path = AttachmentStore.saveAudioData(attachment.data, fileExtension: attachment.fileExtension) {
                paths.append(path)
            }
        }
        return paths
    }
}

struct ConversationRowView: View {
    let conversation: Conversation
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: emojiCircleSize, height: emojiCircleSize)

                Text(conversation.emoji ?? "💬")
                    .font(.system(size: emojiFontSize))
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(conversation.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    Text(formatRelativeTime(conversation.updatedAt))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let lastMessagePreview = conversation.lastMessagePreview {
                    HStack(spacing: 4) {
                        if conversation.lastMessageRole == .user {
                            Text("You:")
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                        }
                        Text(lastMessagePreview)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .font(.system(.subheadline, design: .rounded))
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onAppear {
            environment.conversationStore.ensureEmojiIfNeeded(conversation)
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        // Less than a minute
        if timeInterval < 60 {
            return "now"
        }
        
        // Less than an hour - show minutes only
        if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) min"
        }
        
        // Less than a day - show hours only
        if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hr"
        }
        
        // Less than a week - show days only
        if timeInterval < 604800 {
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        
        // Less than a month - show weeks only
        if timeInterval < 2592000 {
            let weeks = Int(timeInterval / 604800)
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        }
        
        // Less than a year - show months only
        if timeInterval < 31536000 {
            let months = Int(timeInterval / 2592000)
            return "\(months) month\(months == 1 ? "" : "s")"
        }
        
        // A year or more - show years only
        let years = Int(timeInterval / 31536000)
        return "\(years) year\(years == 1 ? "" : "s")"
    }
}
