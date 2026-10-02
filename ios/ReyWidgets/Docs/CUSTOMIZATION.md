# Customize a widget

## Native layout JSON

The designer and JSON editor target the same `NativeDesign` model. After editing JSON, tap **Apply native JSON**, then **Run preview** or **Publish**. Unsaved JSON in the code pane does not silently override visual controls.

```json
{
  "layout": "metric",
  "title": "MANILA",
  "value": "{{/current/temperature_2m}}°",
  "subtitle": "Feels like {{/current/apparent_temperature}}°",
  "footer": "Open-Meteo",
  "symbol": "cloud.sun.fill",
  "background": "#123045",
  "accent": "#9AE3FF",
  "foreground": "#FFFFFF",
  "progress": 0.4,
  "rows": ["First row", "Second row"]
}
```

All keys are required when editing the complete JSON object. Layout values are `metric`, `clock`, `list`, and `progress`. Colors use six hexadecimal digits. `progress` is between 0 and 1. The clock uses a native SwiftUI date view. List rows are capped at 30, with the visible count fitted to the widget family. The progress bar is manually configured; its text can bind to an API. To derive the bar value dynamically, extend `NativeWidgetView` or use JavaScript in an HTML design.

Text bindings use **RFC 6901 JSON Pointer**, not dot-path or JavaScript expressions:

| JSON | Pointer / binding |
| --- | --- |
| `{"current":{"temp":29}}` | `{{/current/temp}}` |
| `{"items":[{"name":"Rey"}]}` | `{{/items/0/name}}` |
| `{"a/b":{"~key":1}}` | `{{/a~1b/~0key}}` |

Missing or null values display an em dash. Numbers, booleans, strings, and nested JSON values are supported.

## HTML/CSS/JavaScript contract

HTML is a **body fragment**. Put styles in the CSS pane and scripts in the JavaScript pane. The runtime adds the document, viewport, data bindings, and security policy. JavaScript runs after the HTML DOM is available.

```html
<main>
  <h2>My API widget</h2>
  <strong data-bind="/current/temperature_2m"></strong>
  <span id="caption"></span>
</main>
```

```css
body { background: #123045; color: white; font-family: system-ui; }
main { padding: 20px; height: 100%; }
strong { font-size: 52px; color: #9ae3ff; }
@media (max-width: 220px) { strong { font-size: 32px; } }
@media (min-height: 250px) { strong { font-size: 96px; } }
```

```javascript
const wind = Number(widget.get('/current/wind_speed_10m', 0));
document.querySelector('#caption').textContent = `Wind: ${wind.toFixed(1)} km/h`;
```

| API | Meaning |
| --- | --- |
| `widget.data` | Parsed sample JSON, cached JSON, or fresh API JSON selected for the current render |
| `widget.get('/path', fallback)` | Resolve a JSON Pointer; default fallback is `—` |
| `widget.size` | `small`, `medium`, or `large` |
| `widget.width`, `widget.height` | The design preset dimensions |
| `widget.ready` | A Promise the snapshotter awaits; defaults to an already resolved Promise |
| `data-bind="/path"` | Set an element's text content from JSON, without HTML injection |

For async computation, assign a Promise to `widget.ready`. Publishing waits for it, fonts, image decoding and two animation frames, with a 10-second timeout per size. Avoid infinite loops and long work. CSS animation only contributes the captured frame to the Home Screen image.

HTML has no native JavaScript message bridge. External connections, iframes, form submissions and navigation are blocked. Inline styles, inline scripts, inline SVG, data/blob images and embedded fonts are supported. Use the native API configuration to fetch data; `fetch()` inside HTML is deliberately blocked by the content security policy. The WebKit data store is ephemeral and does not inherit Safari cookies.

## API configuration

1. Enter a final **HTTPS** endpoint. Use the API's documented GET or read-only POST method.
2. Add headers as a JSON string dictionary. Example: `{"Authorization":"Bearer YOUR_TOKEN","Accept":"application/json"}`. Header values are saved in the shared Keychain. Use the request body for a read-only POST query when necessary.
3. Tap **Test API & preview response**. Inspect the returned structure and add JSON Pointer bindings.
4. Enable **Use API when publishing**. Publish to save the request and design.

Native widgets reuse a cached response until refresh is due, then fetch within a limited request window. They preserve previous successful data on failure and mark it cached. HTML publish fetches fresh data, renders every size, and only then changes the saved snapshot revision. If a size fails, the previous published images remain selected.

Redirects are rejected to avoid forwarding credentials to another endpoint; use the final URL. Responses must be valid JSON and are bounded to 1 MB while streaming. Requests time out, do not use a shared cookie store, and cannot embed user/password URL credentials. Refresh intervals range from 15 minutes to 24 hours; actual scheduling is controlled by WidgetKit.

Use endpoints that read data. Background widget refresh can repeat a request, so a POST that performs a purchase or changes server state is unsuitable. Local network endpoints must still use valid HTTPS certificates; the app does not bypass TLS validation.

## Extending the native source

- Add a layout case in `Core/Models.swift`, render it in `Core/NativeWidgetView.swift`, and expose its controls in `App/EditorView.swift`.
- Extend `APIConfiguration` if you need multiple endpoints or other methods. Keep headers out of exported definitions and preserve bounded requests.
- Update `WidgetDocument.schemaVersion` with an explicit migration before changing persisted required fields. The current importer rejects unsupported versions instead of guessing.
- Add supported widget families in `Widget/ReyWidget.swift` only after adding matching layouts and snapshot sizes.
- Keep WebKit and model inference in the containing app. The extension should remain small enough for WidgetKit's resource budget.
