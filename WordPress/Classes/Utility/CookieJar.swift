import Foundation
import WebKit

/// Provides a common interface to look for a logged-in WordPress cookie in different
/// cookie storage systems, to aid with the transition from UIWebView to WebKit.
///
@objc protocol CookieJar {
    func getCookies(url: URL, completion: @escaping ([HTTPCookie]) -> Void)
    func hasCookie(url: URL, username: String, completion: @escaping (Bool) -> Void)
    func removeCookies(_ cookies: [HTTPCookie], completion: @escaping () -> Void)
    func removeCookies(url: URL, username: String, completion: @escaping () -> Void)
}

// As long as CookieJar is @objc, we can't have shared methods in protocol
// extensions, as it needs to be accessible to Obj-C.
// Whenever we migrate enough code so this doesn't need to be called from Swift,
// a regular CookieJar protocol with shared implementation on an extension would suffice.
private protocol CookieJarSharedImplementation: CookieJar {
}

extension CookieJarSharedImplementation {
    func _hasCookie(url: URL, username: String, completion: @escaping (Bool) -> Void) {
        getCookies(url: url) { (cookies) in
            let cookie = cookies
                .first(where: { cookie in
                    return cookie.isWordPressLoggedIn(username: username)
                })

            completion(cookie != nil)
        }
    }

    func removeCookies(url: URL, matching: @escaping (HTTPCookie) -> Bool, completion: @escaping () -> Void) {
        getCookies(url: url) { [unowned self] (cookies) in
            self.removeCookies(cookies.filter(matching), completion: completion)
        }
    }

    func _removeCookies(url: URL, username: String, completion: @escaping () -> Void) {
        removeCookies(url: url, matching: { $0.isWordPressLoggedIn(username: username) }, completion: completion)
    }

    func removeCookies(url: URL, completion: @escaping () -> Void) {
        removeCookies(url: url, matching: { _ in true }, completion: completion)
    }
}

extension HTTPCookieStorage: CookieJarSharedImplementation {
    func getCookies(url: URL, completion: @escaping ([HTTPCookie]) -> Void) {
        completion(cookies(for: url) ?? [])
    }

    func hasCookie(url: URL, username: String, completion: @escaping (Bool) -> Void) {
        _hasCookie(url: url, username: username, completion: completion)
    }

    func removeCookies(_ cookies: [HTTPCookie], completion: @escaping () -> Void) {
        cookies.forEach(deleteCookie(_:))
        completion()
    }

    func removeCookies(url: URL, username: String, completion: @escaping () -> Void) {
        _removeCookies(url: url, username: username, completion: completion)
    }
}

@available(iOS 11.0, *)
extension WKHTTPCookieStore: CookieJarSharedImplementation {
    func getCookies(url: URL, completion: @escaping ([HTTPCookie]) -> Void) {
        getAllCookies { (cookies) in
            completion(cookies.filter({ (cookie) in
                return cookie.matches(url: url)
            }))
        }
    }

    func hasCookie(url: URL, username: String, completion: @escaping (Bool) -> Void) {
        _hasCookie(url: url, username: username, completion: completion)
    }

    func removeCookies(_ cookies: [HTTPCookie], completion: @escaping () -> Void) {
        let group = DispatchGroup()
        cookies
            .forEach({ [unowned self] (cookie) in
                group.enter()
                self.delete(cookie, completionHandler: {
                    group.leave()
                })
            })
        let result = group.wait(timeout: .now() + .seconds(2))
        if result == .timedOut {
            DDLogWarn("Time out waiting for WKHTTPCookieStore to remove cookies")
        }
        completion()
    }

    func removeCookies(url: URL, username: String, completion: @escaping () -> Void) {
        _removeCookies(url: url, username: username, completion: completion)
    }
}

#if DEBUG
    func __removeAllWordPressComCookies() {
        var jars = [CookieJarSharedImplementation]()
        jars.append(HTTPCookieStorage.shared)
        if #available(iOS 11.0, *) {
            jars.append(WKWebsiteDataStore.default().httpCookieStore)
        }
        let url = URL(string: "https://wordpress.com/")!
        let group = DispatchGroup()
        jars.forEach({ jar in
            group.enter()
            jar.removeCookies(url: url, matching: { _ in true }, completion: {
                group.leave()
            })
        })
        _ = group.wait(timeout: .now() + .seconds(5))
    }
#endif

private let loggedInCookieName = "wordpress_logged_in"
private extension HTTPCookie {
    func isWordPressLoggedIn(username: String) -> Bool {
        return name == loggedInCookieName
            && value.components(separatedBy: "%").first == username
    }

    func matches(url: URL) -> Bool {
        return domain == url.host
            && url.path.hasPrefix(path)
            && (!isSecure || (url.scheme == "https"))
    }
}
