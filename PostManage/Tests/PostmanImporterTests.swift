import XCTest
@testable import PostManage

final class PostmanImporterTests: XCTestCase {
    func testCollectionImport() throws {
        let json = """
        {
          "info": {"name": "API", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
          "event": [{"listen": "prerequest", "script": {"exec": ["console.log('root');"]}}],
          "item": [{"name": "Users", "item": [{
            "name": "Create", "request": {
              "method": "POST",
              "url": {"raw": "http://localhost:8080/users?old=1", "query": [{"key": "old", "value": "1"}, {"key": "off", "value": "2", "disabled": true}]},
              "header": [{"key": "X-Key", "value": "{{token}}"}],
              "body": {"mode": "raw", "raw": "{\\"name\\":\\"A\\"}"}
            },
            "event": [{"listen": "test", "script": {"exec": ["pm.test('ok', function() {});"]}}]
          }]}]
        }
        """
        let result = try PostmanImporter.parse(Data(json.utf8), fallbackName: "fallback")
        XCTAssertEqual(result.collections.first?.name, "API")
        XCTAssertEqual(result.collections.first?.folders?.first?.name, "Users")
        let request = try XCTUnwrap(result.collections.first?.requests.first)
        XCTAssertEqual(request.folderID, result.collections.first?.folders?.first?.id)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "http://localhost:8080/users")
        XCTAssertEqual(request.params.count, 2)
        XCTAssertFalse(request.params[1].enabled)
        XCTAssertEqual(request.headers.first?.value, "{{token}}")
        XCTAssertEqual(request.bodyType, "raw")
        XCTAssertTrue(request.preScript.contains("root"))
        XCTAssertTrue(request.postScript.contains("pm.test"))
    }

    func testEnvironmentImport() throws {
        let json = """
        {"name":"Local","_postman_variable_scope":"environment","values":[
          {"key":"baseUrl","value":"http://localhost:8080","enabled":true},
          {"key":"old","value":"x","enabled":false}
        ]}
        """
        let result = try PostmanImporter.parse(Data(json.utf8), fallbackName: "fallback")
        XCTAssertEqual(result.environments.first?.name, "Local")
        XCTAssertEqual(result.environments.first?.variables.count, 2)
        XCTAssertFalse(try XCTUnwrap(result.environments.first?.variables.last).enabled)
    }

    func testVariableURLSurvivesQueryImport() throws {
        let json = """
        {"info":{"name":"API","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item":[{"name":"Get","request":{"method":"GET","url":{"raw":"{{baseUrl}}/users?id=1","query":[{"key":"id","value":"1"}]}}}]}
        """
        let result = try PostmanImporter.parse(Data(json.utf8), fallbackName: "fallback")
        XCTAssertEqual(result.collections.first?.requests.first?.url, "{{baseUrl}}/users")
    }

    func testRepeatedImportMergesAndUpdates() throws {
        let first = """
        {"info":{"name":"API","_postman_id":"collection-1","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item":[{"id":"request-1","name":"Get Users","request":{"method":"GET","url":"http://localhost/users"}}]}
        """
        let changed = first.replacingOccurrences(of: "http://localhost/users", with: "http://localhost/v2/users")
        var workspace = Workspace()
        let firstResult = try PostmanImporter.parse(Data(first.utf8), fallbackName: "api")
        _ = PostmanImporter.merge(firstResult, into: &workspace)
        let collectionID = try XCTUnwrap(workspace.collections.first?.id)
        let requestID = try XCTUnwrap(workspace.collections.first?.requests.first?.id)
        let repeated = PostmanImporter.merge(firstResult, into: &workspace)
        XCTAssertEqual(workspace.collections.count, 1)
        XCTAssertEqual(workspace.collections.first?.requests.count, 1)
        XCTAssertEqual(repeated.addedCollections, 0)
        XCTAssertEqual(repeated.updatedCollections, 0)
        XCTAssertEqual(repeated.addedRequests, 0)
        XCTAssertEqual(repeated.updatedRequests, 0)

        let updatedResult = try PostmanImporter.parse(Data(changed.utf8), fallbackName: "api")
        _ = PostmanImporter.merge(updatedResult, into: &workspace)
        XCTAssertEqual(workspace.collections.first?.id, collectionID)
        XCTAssertEqual(workspace.collections.first?.requests.first?.id, requestID)
        XCTAssertEqual(workspace.collections.first?.requests.first?.url, "http://localhost/v2/users")
    }

    func testEnvironmentMergeKeepsLocalVariables() throws {
        let first = """
        {"id":"environment-1","name":"Local","_postman_variable_scope":"environment","values":[{"key":"baseUrl","value":"http://localhost"}]}
        """
        let changed = first.replacingOccurrences(of: "http://localhost", with: "http://localhost:8080")
        var workspace = Workspace()
        _ = PostmanImporter.merge(try PostmanImporter.parse(Data(first.utf8), fallbackName: "local"), into: &workspace)
        workspace.environments[0].variables.append(KVItem(key: "localOnly", value: "keep"))
        let changedResult = try PostmanImporter.parse(Data(changed.utf8), fallbackName: "local")
        _ = PostmanImporter.merge(changedResult, into: &workspace)
        XCTAssertEqual(workspace.environments.count, 1)
        XCTAssertEqual(workspace.environments[0].variables.count, 2)
        XCTAssertEqual(workspace.environments[0].variables.first { $0.key == "baseUrl" }?.value, "http://localhost:8080")
        XCTAssertEqual(workspace.environments[0].variables.first { $0.key == "localOnly" }?.value, "keep")
        let repeated = PostmanImporter.merge(changedResult, into: &workspace)
        XCTAssertEqual(repeated.updatedEnvironments, 0)
    }

    func testPreviousWorkspaceDecodesWithoutImportKeys() throws {
        let old = """
        {"collections":[{"id":"00000000-0000-0000-0000-000000000001","name":"Old","requests":[]}],"environments":[]}
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(old.utf8))
        XCTAssertNil(workspace.collections.first?.importKey)
    }

    func testImportWithoutPostmanIDsIsIdempotent() throws {
        let json = """
        {"info":{"name":"API","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item":[{"name":"Folder","item":[{"name":"Get","request":{"method":"GET","url":"http://localhost"}}]}]}
        """
        let imported = try PostmanImporter.parse(Data(json.utf8), fallbackName: "api")
        var workspace = Workspace()
        _ = PostmanImporter.merge(imported, into: &workspace)
        let repeated = PostmanImporter.merge(imported, into: &workspace)
        XCTAssertEqual(workspace.collections.count, 1)
        XCTAssertEqual(workspace.collections[0].requests.count, 1)
        XCTAssertEqual(repeated.updatedCollections, 0)
    }

    func testAuthVariablesMultipartAndExportRoundTrip() throws {
        let json = """
        {
          "info":{"name":"Upload API","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
          "variable":[{"key":"baseUrl","value":"http://localhost:8080"}],
          "auth":{"type":"bearer","bearer":[{"key":"token","value":"{{token}}"}]},
          "item":[{"name":"Upload","request":{
            "method":"POST","url":{"raw":"{{baseUrl}}/upload","query":[]},
            "body":{"mode":"formdata","formdata":[
              {"key":"note","type":"text","value":"hello"},
              {"key":"file","type":"file","src":"/tmp/example.txt"}
            ]}
          }}]
        }
        """
        let imported = try PostmanImporter.parse(Data(json.utf8), fallbackName: "fallback")
        let collection = try XCTUnwrap(imported.collections.first)
        let request = try XCTUnwrap(collection.requests.first)
        XCTAssertEqual(collection.variables?.first?.key, "baseUrl")
        XCTAssertEqual(request.auth?.type, "bearer")
        XCTAssertEqual(request.auth?.token, "{{token}}")
        XCTAssertEqual(request.bodyType, "multipart")
        XCTAssertEqual(request.multipart?.last?.filePath, "/tmp/example.txt")

        let exported = try PostmanExporter.export(collection)
        let reimported = try PostmanImporter.parse(exported, fallbackName: "fallback")
        XCTAssertEqual(reimported.collections.first?.variables?.first?.value, "http://localhost:8080")
        XCTAssertEqual(reimported.collections.first?.requests.first?.auth?.token, "{{token}}")
        XCTAssertEqual(reimported.collections.first?.requests.first?.multipart?.count, 2)
        var workspace = Workspace()
        _ = PostmanImporter.merge(imported, into: &workspace)
        _ = PostmanImporter.merge(reimported, into: &workspace)
        XCTAssertEqual(workspace.collections.count, 1)
        XCTAssertEqual(workspace.collections.first?.requests.count, 1)
    }

    func testGraphQLBinaryAndUnsupportedAuthWarning() throws {
        let json = """
        {"info":{"name":"API","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "auth":{"type":"oauth2"},
         "item":[
           {"name":"GraphQL","request":{"method":"POST","url":"http://localhost/graphql","body":{"mode":"graphql","graphql":{"query":"{ ping }","variables":"{\\"id\\":1}"}}}},
           {"name":"Binary","request":{"method":"POST","url":"http://localhost/file","body":{"mode":"file","file":{"src":"/tmp/input.bin"}}}}
         ]}
        """
        let result = try PostmanImporter.parse(Data(json.utf8), fallbackName: "API")
        XCTAssertEqual(result.collections.first?.requests[0].bodyType, "graphql")
        XCTAssertEqual(result.collections.first?.requests[0].graphqlVariables, "{\"id\":1}")
        XCTAssertEqual(result.collections.first?.requests[1].binaryPath, "/tmp/input.bin")
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testStringRequestImport() throws {
        let json = """
        {"info":{"name":"API","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item":[{"name":"Ping","request":"http://localhost/ping"}]}
        """
        let result = try PostmanImporter.parse(Data(json.utf8), fallbackName: "API")
        XCTAssertEqual(result.collections.first?.requests.first?.method, "GET")
        XCTAssertEqual(result.collections.first?.requests.first?.url, "http://localhost/ping")
    }

    func testExportKeepsRawAndEditedQueryParameters() throws {
        var request = RequestItem()
        request.url = "http://localhost/search?existing=one"
        request.params = [KVItem(key: "added", value: "two")]
        let data = try PostmanExporter.export(RequestCollection(name: "API", requests: [request]))
        let imported = try PostmanImporter.parse(data, fallbackName: "API")
        let restored = try XCTUnwrap(imported.collections.first?.requests.first)
        XCTAssertEqual(restored.url, "http://localhost/search")
        XCTAssertEqual(restored.params.map(\.key), ["existing", "added"])
    }

    func testNestedFoldersRoundTripAndLegacyMigration() throws {
        let json = """
        {"info":{"name":"API","_postman_id":"root-id","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},
         "item":[{"id":"users-id","name":"Users","item":[{"id":"admin-id","name":"Admin","item":[
            {"id":"get-id","name":"Get","request":{"method":"GET","url":"http://localhost/users"}}
         ]}]}]}
        """
        let imported = try PostmanImporter.parse(Data(json.utf8), fallbackName: "API")
        let collection = try XCTUnwrap(imported.collections.first)
        XCTAssertEqual(collection.folders?.count, 2)
        XCTAssertEqual(collection.folderPath(for: try XCTUnwrap(collection.requests.first)), "Users / Admin")
        let exported = try PostmanExporter.export(collection)
        let restored = try PostmanImporter.parse(exported, fallbackName: "API")
        XCTAssertEqual(restored.collections.first?.folders?.count, 2)
        var workspace = Workspace()
        _ = PostmanImporter.merge(imported, into: &workspace)
        let repeated = PostmanImporter.merge(restored, into: &workspace)
        XCTAssertEqual(workspace.collections[0].folders?.count, 2)
        XCTAssertEqual(workspace.collections[0].requests.count, 1)
        XCTAssertEqual(repeated.updatedCollections, 0)

        var oldRequest = RequestItem()
        oldRequest.name = "Legacy"
        let legacy = RequestCollection(importKey: "postman:collection:root-id/folder:users-id",
                                       name: "API / Users", requests: [oldRequest])
        var oldWorkspace = Workspace(collections: [legacy])
        XCTAssertTrue(WorkspaceMigration.migrateLegacyFolderCollections(&oldWorkspace))
        XCTAssertEqual(oldWorkspace.collections.count, 1)
        XCTAssertEqual(oldWorkspace.collections[0].name, "API")
        XCTAssertEqual(oldWorkspace.collections[0].folderPath(for: oldWorkspace.collections[0].requests[0]), "Users")
    }
}
