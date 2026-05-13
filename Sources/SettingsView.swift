import SwiftUI

struct SettingsView: View {
    let configManager: ConfigManager
    let onDismiss: () -> Void

    @State private var llmProvider: LLMProvider = .openai
    @State private var apiKey: String = ""
    @State private var apiBaseURL: String = ""
    @State private var modelName: String = "gpt-4o-mini"
    @State private var summaryFrequency: SummaryFrequency = .daily
    @State private var hasChanges = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DigitalShadow 设置")
                .font(.headline)
                .padding(.top, 8)

            Divider()

            Picker("AI 提供商", selection: $llmProvider) {
                Text("OpenAI").tag(LLMProvider.openai)
                Text("Anthropic").tag(LLMProvider.anthropic)
                Text("自定义").tag(LLMProvider.custom)
            }
            .pickerStyle(.segmented)
            .onChange(of: llmProvider) { _ in
                hasChanges = true
                if llmProvider != .custom { apiBaseURL = "" }
                if llmProvider == .anthropic && modelName == "gpt-4o-mini" {
                    modelName = "claude-haiku-4-5-20251001"
                }
                if llmProvider == .openai && modelName.contains("claude") {
                    modelName = "gpt-4o-mini"
                }
            }

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: apiKey) { _ in hasChanges = true }

            if llmProvider == .custom {
                TextField("API 地址 (如 https://api.example.com)", text: $apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiBaseURL) { _ in hasChanges = true }
            }

            TextField("模型名称", text: $modelName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: modelName) { _ in hasChanges = true }

            Divider()

            Picker("自动总结频率", selection: $summaryFrequency) {
                Text("每 4 小时").tag(SummaryFrequency.fourHours)
                Text("每 8 小时").tag(SummaryFrequency.eightHours)
                Text("每天").tag(SummaryFrequency.daily)
                Text("每 3 天").tag(SummaryFrequency.threeDays)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: summaryFrequency) { _ in hasChanges = true }

            Divider()

            HStack {
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])

                Button("保存") {
                    saveConfig()
                    onDismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(apiKey.isEmpty)
            }

            if hasChanges {
                Text("有未保存的更改")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        let config = (try? configManager.load()) ?? AppConfig()
        llmProvider = config.llmProvider
        apiKey = config.apiKey
        apiBaseURL = config.apiBaseURL
        modelName = config.modelName
        summaryFrequency = config.summaryFrequency
    }

    private func saveConfig() {
        let config = AppConfig(
            llmProvider: llmProvider,
            apiKey: apiKey,
            apiBaseURL: apiBaseURL,
            modelName: modelName,
            summaryFrequency: summaryFrequency,
            isPaused: false,
            videoCaptionMinDurationSec: 60
        )
        try? configManager.save(config)
    }
}
