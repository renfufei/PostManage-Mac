# PostManage

A small, local-only macOS HTTP client built with SwiftUI. It requires no account, cloud service, or internet connection to start. Requests go directly to the URL you enter; collections and environments are stored in `~/Library/Application Support/PostManage/workspace.json`.

Current version: **1.0.1**. The macOS About panel and the bottom of Settings show the version.

## Build and run

Requires macOS 14 or later and Xcode with XcodeGen installed.

```sh
xcodegen generate
xcodebuild -project PostManage.xcodeproj -scheme PostManage -configuration Debug -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
open .build/Build/Products/Debug/PostManage.app
```

To create a Release `.app` and a drag-to-Applications `.dmg`, run:

```sh
./build.sh
```

The outputs are `dist/PostManage.app` and `dist/PostManage.dmg`. The script creates the app icon from `scripts/generate_icon.swift`; its full-size preview is `Artwork/PostManageIcon.png`. The Release app is ad-hoc signed for local use. It is not notarized for public distribution.

## Features

- Collections and requests with GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS.
- Query parameters, headers, Bearer/Basic/API-key authorization, raw JSON/text body, URL-encoded form, multipart text/file fields, binary file body, and GraphQL body.
- A globally remembered **Show Params in URL** checkbox shows enabled query parameters in the request URL preview, including `{{variables}}`. The base URL stays editable below it, and the preview can be copied without altering or duplicating the stored Params.
- Multiple environments. Use `{{name}}` in URL, parameter, header, or body fields.
- Use Postman's `{{$guid}}` in request fields to generate a fresh UUID when each request is sent, including raw JSON bodies.
- Pre-request and post-response JavaScript scripts, with local test output.
- The **Scripts** request tab has a left-side switch for pre-request and post-response scripts. Search results open the matching script directly.
- Response body as formatted text, JSON tree, image, or Hex, with original-byte saving, headers, cookies, redirects, staged timing, status, size, and session logs.
- Logs allow copying one entry or the full visible list. `[REDACTED]` marks a sensitive value hidden from script logs; it does not change the value sent in the request.
- JSON request and response bodies use syntax colors. **Format JSON** prettifies a request body or switches a response to its formatted view; invalid request JSON shows an error instead of changing its content.
- Params and Headers support single-row editing and **Bulk Edit**. Bulk mode accepts one `key: value` pair per line; prefix a line with `//` to disable it. Request edits remain drafts until **Save**.
- Import one or more Postman Collection v2.0/v2.1 and Postman Environment JSON files using the import button at the top of the sidebar. Reimporting the same source updates its existing collections, requests, folders, and environment variables without creating duplicates; local-only entries are preserved. A request with an unsaved draft is skipped with a warning so an import cannot silently replace its saved version. A failed file does not stop the rest. Nested folders retain their hierarchy.
- Drag the divider beside the sidebar to resize it, or drag the divider between Collections and Environments to adjust their heights. These sizes and the window frame are restored when the app reopens.
- Drag the divider between the request editor and response to adjust their heights; the position is remembered and can be reset in Settings.
- Collapse the Environments section with its chevron. The top sidebar menu groups Postman import and collection export; its other menu uses an ellipsis for collection and environment creation. Icon buttons have hover descriptions.
- Open **Settings** with the gear icon to switch between English and Simplified Chinese, choose whether the URL preview includes Params, open the local data folder, or reset sidebar layout.
- Settings and the rename dialogs use consistent form widths; the collection runner has extra width for result rows. Language changes update settings, search labels, action states, tooltips, and built-in messages immediately. Run `python3 scripts/audit_localization.py` to check static Chinese string coverage.
- Use a collection's **…** menu to add a request, edit collection variables, rename, export as Postman Collection v2.1 JSON, or delete it. Click the collection name to expand or collapse its requests.
- Each request has a right-click menu and an adjacent **…** menu for duplicate, cut, copy, rename, and delete. Paste copied or cut requests from a collection or folder menu. Dragging a request over another request shows a horizontal insertion marker before the target row.
- Duplicating a request opens a wide rename dialog immediately. Collection and folder renaming use the same dialog, and the request **…** button has no extra dropdown arrow.
- Collapse the sidebar with its toolbar icon. The request heading shows the collection and request names, and JavaScript editors color comments, strings, keywords, and API names.
- On launch, the sidebar expands only the active request's collection and folder path. Switching requests follows the newly active request; collection and folder chevrons still allow manual expansion. The interface uses a monospaced font throughout.
- Open multiple requests in tabs, review locally stored request history, and run a collection in sequence with test pass/fail results. History is stored in `~/Library/Application Support/PostManage/history.json`; sensitive query values with common key names are masked.
- Requests and environment editors share one tab strip. Opening an environment highlights its own closable tab; closing it returns to the most recently opened remaining tab.
- Request fields are edited in memory first. **Send** uses the current draft, while **Save** (`⌘S`) commits it to `workspace.json`. Unsaved requests are marked with a dot. Closing an edited tab asks whether to save or discard; closing the window keeps drafts for this app session, and quitting asks whether to save all drafts. Collection, folder, and environment changes still save automatically; the sidebar footer reports write failures and offers **Retry**.
- If `workspace.json` cannot be read, PostManage preserves it and pauses workspace writes. **Recover…** backs up the original file before saving the current workspace. History save failures also appear in the sidebar footer.
- An active request or collection run can be cancelled. A collection run stops before the next request after cancellation.
- Search from the magnifying-glass button or a collection's **…** menu. `⌘F` searches the current collection, `⇧⌘F` searches the whole workspace, and `⌥⌘F` opens search with replacement. Results include request names, URLs, parameters, headers, bodies, scripts, auth fields, collection variables, and environments. Replace one match from its result row, or review the count and confirm **Replace All**.

Script examples:

```js
pm.environment.set('token', 'abc123');
console.log(pm.environment.get('token'));
```

```js
pm.test('returns 200', function () {
  pm.expect(pm.response.code).to.eql(200);
});
const body = pm.response.json();
pm.environment.set('lastId', body.id);
```

Scripts run in an isolated local worker with a 5-second timeout. They support the `pm` functions shown above, not the full Postman script API. Logs are kept in memory for the current app session. Local workspace data is plain JSON, so avoid storing secrets on a shared macOS account.

Pre-request scripts can read `pm.request.method`, `pm.request.url.path`, `pm.request.url.port`, and `pm.request.url.query.members`. `CryptoJS.HmacSHA256(message, secret)` with `CryptoJS.enc.Base64.stringify(...)` is supported for request signing. Variables set before a request are saved even when the network request fails.

Postman imports cover the fields listed above, plus collection variables, request descriptions, and request/collection/folder scripts. Imported file paths may need to be reselected on this Mac. Unsupported authorization and body modes produce visible import warnings. See [IMPORT_COMPATIBILITY.md](IMPORT_COMPATIBILITY.md) for the detailed audit.
