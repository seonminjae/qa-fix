import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var notionToken: String = ""
    var notionDatabaseID: String = ""
    var repositoryPath: String = ""
    var repositoryBookmark: Data?
    var model: AnthropicModel = .sonnet4
    var maxBudgetUSD: Double = 5.0

    var claudeVersionStatus: String = "Checking…"
    var claudeVersionOK: Bool = false
    var databaseValidationMessage: String?
    var mcpConfigPath: String?
    var loginTestResult: String?

    func load() {
        let defaults = UserDefaults.standard
        notionToken = KeychainManager.load(for: .notionToken) ?? ""
        notionDatabaseID = defaults.string(forKey: SettingsStoreKey.notionDatabaseID) ?? ""
        repositoryBookmark = defaults.data(forKey: SettingsStoreKey.repositoryBookmark)
        if let bookmark = repositoryBookmark, let url = try? BookmarkManager.resolve(bookmark) {
            repositoryPath = url.path
        }
        if let raw = defaults.string(forKey: SettingsStoreKey.model),
           let parsed = AnthropicModel(rawValue: raw) {
            model = parsed
        }
        if defaults.object(forKey: SettingsStoreKey.maxBudgetUSD) != nil {
            maxBudgetUSD = defaults.double(forKey: SettingsStoreKey.maxBudgetUSD)
        }
    }

    func saveTokenAndConfig() {
        if !notionToken.isEmpty {
            try? KeychainManager.save(notionToken, for: .notionToken)
            if let url = try? MCPConfigManager.writeNotionConfig(token: notionToken) {
                mcpConfigPath = url.path
            }
        }
        UserDefaults.standard.set(notionDatabaseID, forKey: SettingsStoreKey.notionDatabaseID)
        UserDefaults.standard.set(model.rawValue, forKey: SettingsStoreKey.model)
        UserDefaults.standard.set(maxBudgetUSD, forKey: SettingsStoreKey.maxBudgetUSD)
    }

    func selectRepository() {
        do {
            let (url, bookmark) = try BookmarkManager.promptForRepository()
            repositoryPath = url.path
            repositoryBookmark = bookmark
            UserDefaults.standard.set(bookmark, forKey: SettingsStoreKey.repositoryBookmark)
        } catch {
            // cancelled or error; ignore
        }
    }

    func probeClaudeVersion() async {
        do {
            let version = try await ClaudeCodeVersionProbe.probe()
            if version.isSupported {
                claudeVersionStatus = "\(version.raw) ✓"
                claudeVersionOK = true
            } else {
                claudeVersionStatus = "\(version.raw) — requires 2.1.0+"
                claudeVersionOK = false
            }
        } catch {
            claudeVersionStatus = error.localizedDescription
            claudeVersionOK = false
        }
    }

    /// Runs a minimal `claude -p "hi"` to verify the binary + auth work end-to-end.
    func verifyLogin() async {
        loginTestResult = "Testing…"
        guard let binary = ClaudeCodeVersionProbe.resolveBinary() else {
            loginTestResult = "❌ claude binary not found"
            return
        }
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "-p",
            "--verbose",
            "--output-format", "stream-json",
            "--permission-mode", "bypassPermissions"
        ]
        process.environment = ClaudeCodeVersionProbe.environment(for: binary)
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            loginTestResult = "❌ launch failed: \(error.localizedDescription)"
            return
        }
        stdin.fileHandleForWriting.write(Data("hi".utf8))
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let body = String(data: outData, encoding: .utf8) ?? ""
        let errBody = String(data: errData, encoding: .utf8) ?? ""
        if body.contains("Not logged in") || body.contains("/login") {
            loginTestResult = "❌ Not logged in — Terminal에서 /login 실행하세요"
        } else if process.terminationStatus == 0 {
            loginTestResult = "✓ 로그인 OK (exit 0)"
        } else {
            let snippet = (errBody.isEmpty ? body : errBody)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(140)
            loginTestResult = "❌ exit \(process.terminationStatus): \(snippet)"
        }
    }

    func validateDatabaseID() async {
        guard !notionToken.isEmpty, !notionDatabaseID.isEmpty else {
            databaseValidationMessage = "Token and database ID are required."
            return
        }
        let url = URL(string: "https://api.notion.com/v1/databases/\(notionDatabaseID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(notionToken)", forHTTPHeaderField: "Authorization")
        request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                databaseValidationMessage = "OK (HTTP \(http.statusCode))"
            } else if let http = response as? HTTPURLResponse {
                databaseValidationMessage = "HTTP \(http.statusCode)"
            }
        } catch {
            databaseValidationMessage = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notionSection
                repositorySection
                claudeSection
                agentSection
                HStack {
                    Spacer()
                    Button("Save") {
                        viewModel.saveTokenAndConfig()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                }
            }
            .padding(20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            viewModel.load()
            await viewModel.probeClaudeVersion()
        }
    }

    // MARK: - Sections

    private var notionSection: some View {
        sectionCard(title: "Notion") {
            field("Integration Token") {
                SecureField("secret_xxxxxxxx", text: $viewModel.notionToken)
                    .textFieldStyle(.roundedBorder)
            }
            field("Database ID") {
                TextField("32-character database UUID", text: $viewModel.notionDatabaseID)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Button("Validate Database ID") {
                    Task { await viewModel.validateDatabaseID() }
                }
                if let msg = viewModel.databaseValidationMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let path = viewModel.mcpConfigPath {
                Text("MCP config → \(path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var repositorySection: some View {
        sectionCard(title: "Repository") {
            field("iOS Repository Path") {
                HStack {
                    TextField("(not selected)", text: .constant(viewModel.repositoryPath))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Choose…") {
                        viewModel.selectRepository()
                    }
                }
            }
        }
    }

    private var claudeSection: some View {
        sectionCard(title: "Claude Code CLI") {
            field("Version") {
                Text(viewModel.claudeVersionStatus)
                    .foregroundStyle(viewModel.claudeVersionOK ? .green : .red)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    Task { await viewModel.probeClaudeVersion() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check version")
            }

            Text("Terminal에서 `claude` 실행 후 `/login` 한 번이면 Claude Max OAuth가 Keychain에 저장되어 subprocess에서도 재사용됩니다. 별도 API Key 입력은 필요하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Verify") {
                Button("Test `claude -p hi`") {
                    Task { await viewModel.verifyLogin() }
                }
                .help("Runs a minimal test to confirm CLI auth works.")
                Spacer(minLength: 0)
            }
            if let result = viewModel.loginTestResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? .green : (result.hasPrefix("❌") ? .red : .secondary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.claudeVersionOK {
                Link("Install Claude Code",
                     destination: URL(string: "https://docs.claude.com/en/docs/agents/claude-code")!)
                    .font(.caption)
            }
        }
    }

    private var agentSection: some View {
        sectionCard(title: "Agent") {
            field("Model") {
                Picker("", selection: $viewModel.model) {
                    ForEach(AnthropicModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            field("Max budget (USD)") {
                TextField("", value: $viewModel.maxBudgetUSD, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            // Wide: horizontal layout with label on left.
            HStack(alignment: .center, spacing: 12) {
                Text(label)
                    .frame(minWidth: 120, idealWidth: 160, maxWidth: 180, alignment: .leading)
                    .foregroundStyle(.secondary)
                content()
            }
            // Narrow: stacked — label above.
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
