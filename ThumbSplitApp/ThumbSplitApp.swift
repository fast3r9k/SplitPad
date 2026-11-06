import SwiftUI

@main
struct ThumbSplitApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

private struct SetupView: View {
    @State private var sampleText = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    setupCard
                    typingCard
                    Label("Кнопка рядом с правым пробелом соединяет и разделяет клавиатуру. Удерживайте её для настроек размеров и звука. Цвет клавиатуры следует системной теме.", systemImage: "slider.horizontal.3")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    privacyCard
                }
                .frame(maxWidth: 760)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ThumbSplit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isTyping {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { isTyping = false }
                    }
                }
            }
        }
        .tint(.indigo)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            // A keyboard extension can dismiss without updating SwiftUI's focus binding.
            // Resign the test field so the next tap starts a fresh editing session.
            isTyping = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Image(systemName: "keyboard")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.indigo)
                    .padding(18)
                    .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ближе к большим пальцам")
                        .font(.largeTitle.bold())
                    Text("Разделённая клавиатура для iPad")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Две половины по краям или цельная клавиатура. Русский и английский языки. Размеры под ваш хват.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Подключение за три шага")
                .font(.title2.bold())
            step(1, "Откройте настройки iPad", "Основные → Клавиатура → Клавиатуры → Новые клавиатуры.")
            step(2, "Добавьте ThumbSplit", "Выберите ThumbSplit в списке сторонних клавиатур. «Полный доступ» не нужен.")
            step(3, "Переключитесь на неё", "Откройте поле ввода и удерживайте кнопку глобуса на клавиатуре. Выберите ThumbSplit.")
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var typingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Попробуйте здесь")
                    .font(.title2.bold())
                Spacer()
                if !sampleText.isEmpty {
                    Button("Очистить") { sampleText = "" }
                }
            }
            Text("Коснитесь поля и выберите ThumbSplit через глобус.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $sampleText)
                .font(.system(size: 22))
                .focused($isTyping)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 180)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.indigo.opacity(isTyping ? 0.65 : 0.12), lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("Поле для проверки клавиатуры")
                .accessibilityIdentifier("keyboard-test-field")
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Без полного доступа", systemImage: "lock.shield")
                .font(.headline)
            Text("Клавиатура работает локально: не отправляет текст в сеть и не сохраняет историю ввода. Сохраняются язык, режим, звук, настройки размеров, последние 40 выбранных эмодзи и выбранные оттенки кожи. Поисковые запросы не сохраняются.")
            Text("Авто-заглавная, двойной пробел для точки, свайп вниз для второго символа и удержание для вариантов. Над клавишами доступны подсказки и варианты с пометкой «Исправить»: нажмите, чтобы заменить ошибочное русское или английское слово. Текст сам не меняется. Эмодзи — по кнопке рядом с глобусом. В панели эмодзи доступны категории, недавние и поиск на русском и английском. Удерживайте эмодзи с маленькой точкой, чтобы выбрать оттенок кожи. Tab в начале второго ряда вставляет табуляцию. Без автоматической замены слов и непрерывного свайп-набора. В полях паролей и приложениях, запрещающих сторонние клавиатуры, iPadOS покажет системную клавиатуру.")
            Text("Короткое нажатие на глобус меняет язык, долгое — переключает на следующую системную клавиатуру. Двойное нажатие Shift включает Caps Lock.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.indigo)
                .frame(width: 32, height: 32)
                .background(.indigo.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}
