import os

/// Loggers shared by the app and extensions.
public enum NotimeLog {
    public static let subsystem = "art.stillh.notime"

    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let screenTime = Logger(subsystem: subsystem, category: "screen-time")
    public static let service = Logger(subsystem: subsystem, category: "service")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
