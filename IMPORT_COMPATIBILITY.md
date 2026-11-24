# Postman import compatibility

PostManage imports Postman Collection v2.0/v2.1 and Environment JSON files. It can export a selected collection as Postman Collection v2.1 JSON. Imports merge by Postman IDs where available; repeated imports update existing entries and keep local-only entries.

## Supported request fields

- Request name, description, method, URL, query parameters, and headers.
- Collection and folder variables, plus environment variables. The selected environment overrides a collection variable with the same key.
- Bearer token, Basic auth, and API key in a header or query parameter, including `{{variables}}`.
- Raw bodies with common content types, URL-encoded forms, multipart text and file fields, binary file bodies, and GraphQL query and variables.
- Collection, folder, and request pre-request/test scripts. The scripts run locally using the supported `pm` and `CryptoJS` functions.

## Current limits

- OAuth 1/2, Digest, AWS Signature authorization helpers, and other Postman auth types are not executed automatically. Import shows a warning for these types. A custom pre-request script can implement an authorization scheme when its required APIs are available.
- Postman script APIs beyond the documented `pm.environment`, `pm.variables`, `pm.request` fields, `pm.response`, `pm.test`, `pm.expect`, and HMAC-SHA256/Base64 subset are not guaranteed. In particular, `pm.sendRequest`, `pm.collectionVariables`, global variables, and external packages are not implemented.
- Nested Postman folders remain editable folders within their collection and retain their hierarchy on export. Older flat path collections are migrated on launch after a backup is saved as `workspace.pre-folder-migration.json`.
- File paths embedded in a Postman export may point to another computer. Use **Browse** in the multipart or binary body editor to select the file on this Mac.
- Certificates, proxy settings, cookie-jar management, and GraphQL schema exploration are outside this local client's current scope.
