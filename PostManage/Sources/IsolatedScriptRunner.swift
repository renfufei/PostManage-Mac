import Foundation

enum IsolatedScriptRunner {
    static let timeout: TimeInterval = 5

    static func run(_ script: String, variables: [String: String],
                    response: ResponseData? = nil, request: RequestItem? = nil) async throws -> ScriptResult {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScriptResult(variables: variables, logs: [])
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try runBlocking(script, variables: variables, response: response, request: request)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ script: String, variables: [String: String],
                                    response: ResponseData?, request: RequestItem?) throws -> ScriptResult {
        guard let executable = Bundle.main.executableURL else {
            throw RequestError.script("Application executable is unavailable")
        }
        let input = ScriptWorkerInput(script: script, variables: variables, request: request,
                                      responseStatus: response?.status, responseBody: response?.body)
        let data = try JSONEncoder().encode(input)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--script-worker"]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
        try inputPipe.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            throw RequestError.scriptTimeout(Int(timeout))
        }
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let output = try? JSONDecoder().decode(ScriptWorkerOutput.self, from: outputData) else {
            throw RequestError.script("Script worker exited unexpectedly")
        }
        if let error = output.error {
            throw RequestError.script(error)
        }
        let logs = redact(output.logs, before: variables, after: output.variables, request: request)
        return ScriptResult(variables: output.variables, logs: logs)
    }

    private static func redact(_ logs: [String], before: [String: String],
                               after: [String: String], request: RequestItem?) -> [String] {
        var secrets: Set<String> = []
        for (key, value) in before.merging(after, uniquingKeysWith: { _, new in new }) {
            let name = key.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
            if ["secret", "password", "token", "apikey", "accesskey", "credential"].contains(where: name.contains),
               value.count >= 3 {
                secrets.insert(value)
            }
        }
        if let auth = request?.auth {
            for value in [auth.token, auth.password, auth.value] where value.count >= 3 && !value.contains("{{") {
                secrets.insert(value)
            }
        }
        for header in request?.headers ?? [] where ["authorization", "x-api-key"].contains(header.key.lowercased()) {
            if header.value.count >= 3 && !header.value.contains("{{") { secrets.insert(header.value) }
        }
        let sorted = secrets.sorted { $0.count > $1.count }
        return logs.map { line in
            if let label = line.range(of: #"^(?:app[-_ ]?key|secret|password|token|authorization)\b"#,
                                      options: [.regularExpression, .caseInsensitive]) {
                return String(line[label]) + " [REDACTED]"
            }
            var safe = line
            for secret in sorted { safe = safe.replacingOccurrences(of: secret, with: "[REDACTED]") }
            return safe
        }
    }
}
