import Foundation

@main
struct ObserverRuntimeConfigurationTests {
    private static var checks = 0
    private static var failures = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() {
            failures += 1
            print("FAIL \(name)")
        }
    }

    private static func rejects(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            expect(false, name)
        } catch {
            expect(true, name)
        }
    }

    static func main() {
        do {
            let defaults = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: ObserverRuntimeConfigurationStore.defaultBaseURLString,
                projectID: ObserverRuntimeConfigurationStore.defaultProjectID
            )
            expect(defaults.baseURL.scheme == "https", "default URL requires HTTPS")
            expect(defaults.baseURL.host == "vcw-observer-read-edge.vercel.app", "default stable edge host")
            expect(defaults.baseURL.port == nil, "default stable edge uses standard HTTPS port")
            expect(defaults.projectID == "vcw-acceptance", "default project scope")
        } catch {
            expect(false, "defaults validate")
        }

        rejects("HTTP URL rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "http://example.test:8443",
                projectID: "vcw-acceptance"
            )
        }

        rejects("URL query rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://example.test:8443?token=bad",
                projectID: "vcw-acceptance"
            )
        }

        rejects("URL credentials rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://user:pass@example.test:8443",
                projectID: "vcw-acceptance"
            )
        }

        rejects("invalid project rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedSettings(
                baseURLString: "https://example.test:8443",
                projectID: "../other"
            )
        }

        do {
            let token = try ObserverRuntimeConfigurationStore.validatedBearerToken("obsr_example")
            expect(token == "obsr_example", "token accepted without mutation")
        } catch {
            expect(false, "valid token accepted")
        }

        rejects("token whitespace rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedBearerToken("obsr_bad token")
        }

        rejects("oversized token rejected") {
            _ = try ObserverRuntimeConfigurationStore.validatedBearerToken(
                String(repeating: "x", count: 257)
            )
        }

        print(
            "Observer runtime configuration tests: checks=\(checks) " +
            "pass=\(checks - failures) fail=\(failures)"
        )
        if failures > 0 {
            exit(1)
        }
    }
}
