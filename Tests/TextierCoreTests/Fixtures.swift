/// Real-world Inputs shared across test suites.
enum Fixtures {
    /// The Laravel/Monolog line from the grilling session.
    static let monologLine = #"""
    [2026-10-07 11:17:10] develop.WARNING: [REPOSITORY SCOPE LEAK] __call invoked with non-empty scopeQueries {"url":"http://app.bo.test/player/api/v1/signin","repository":"Modules\\Notification\\Repositories\\EmailTemplateRepository","method":"where","scope_count":1,"caller_file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php","caller_line":118,"caller_function":"findActiveTemplate","backtrace":[{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Services/EmailTemplateService.php","line":80,"function":"__call"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/Modules/Notification/Listeners/SendLoginFromNewIPEmailToPlayer.php","line":118,"function":"findActiveTemplate"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":603,"function":"shouldQueue"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":552,"function":"handlerWantsToBeQueued"},{"file":"/Users/mac/Documents/Projects/dv/acme-store-upgraded/vendor/laravel/framework/src/Illuminate/Events/Dispatcher.php","line":479,"function":"Illuminate\\Events\\{closure}"}]}
    """#

    /// The JSON context at the end of `monologLine`, as logged.
    static var monologContextJSON: String {
        String(monologLine[monologLine.range(of: #"{"url""#)!.lowerBound...])
    }
}

extension Fixtures {
    /// An nginx access log line, in the default `combined` format.
    static let nginxAccessLine = #"203.0.113.7 - - [09/Oct/2026:10:15:32 +0700] "GET /api/v1/signin?next=%2Fhome HTTP/1.1" 200 512 "https://shop.example.com/login" "Mozilla/5.0 (Macintosh)""#

    /// A Java log line and the first frame of its stack trace.
    static let javaLogLines = """
    2026-10-09 10:15:32,118 ERROR [main] com.example.billing.InvoiceService - Invoice 4711 failed
        at com.example.billing.InvoiceService.charge(InvoiceService.java:87)
    """
}
