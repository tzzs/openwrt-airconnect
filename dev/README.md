# Production LuCI view preview

From the repository root run `python3 -m http.server 8137 --bind 127.0.0.1`, then open http://127.0.0.1:8137/dev/ . No packages need installing. The page executes the production `overview.js` and CSS with small development-only LuCI form/UCI/RPC adapters. It is explicitly a mock backend, not a router connection or a LuCI integration test. All example names/UDNs and RFC 5737 IP addresses are synthetic.

Views: `/dev/?empty`, `?error`, `?conflict`, `?invalid` exercise empty discovery, status failure, legacy instance conflicts and backend validation rejection. Standard browser dark preference and 390px mobile viewport exercise themes/layout. `window.airconnectDemo` exposes the production view, staged UCI, mock status and RPC call counters for interaction checks. Logs start at zero calls, polling runs at ten seconds only while visible, and polling does not rerender input forms.

The adapters implement the subset of LuCI needed for this preview. Device/browser tests do not substitute for testing with real LuCI, rpcd, UCI apply rollback and service triggers in the target SDK image. The browser needs no external network access.
