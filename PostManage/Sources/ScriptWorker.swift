import Foundation

struct ScriptWorkerInput: Codable {
    var script: String
    var variables: [String: String]
    var request: RequestItem?
    var responseStatus: Int?
    var responseBody: String?
}

struct ScriptWorkerOutput: Codable {
    var variables: [String: String]
    var logs: [String]
    var error: String?
}

enum ScriptWorker {
    static func runAndExit() -> Never {
        let output: ScriptWorkerOutput
        do {
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            let input = try JSONDecoder().decode(ScriptWorkerInput.self, from: inputData)
            let response: ResponseData?
            if let status = input.responseStatus {
                let body = input.responseBody ?? ""
                response = ResponseData(status: status, statusText: "", duration: 0,
                                        size: body.utf8.count, headers: [], body: body)
            } else {
                response = nil
            }
            let result = try RequestEngine.runScript(input.script, variables: input.variables,
                                                     response: response, request: input.request)
            output = ScriptWorkerOutput(variables: result.variables, logs: result.logs, error: nil)
        } catch {
            output = ScriptWorkerOutput(variables: [:], logs: [], error: error.localizedDescription)
        }
        if let data = try? JSONEncoder().encode(output) {
            FileHandle.standardOutput.write(data)
            exit(0)
        }
        exit(1)
    }
}
