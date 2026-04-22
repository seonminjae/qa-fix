import Foundation
import OSLog

enum LogCategory: String, CaseIterable {
    case subprocess, notion, git, agent, ui
}

enum AppLogger {
    private static let subsystem = "com.fanmaum.QAFixMac"
    private static var loggers: [LogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: LogCategory.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) }
    )

    static func logger(_ category: LogCategory) -> Logger {
        loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func debug(_ category: LogCategory, _ message: String) {
        logger(category).debug("\(message, privacy: .public)")
    }

    static func info(_ category: LogCategory, _ message: String) {
        logger(category).info("\(message, privacy: .public)")
    }

    static func warning(_ category: LogCategory, _ message: String) {
        logger(category).warning("\(message, privacy: .public)")
    }

    static func error(_ category: LogCategory, _ message: String) {
        logger(category).error("\(message, privacy: .public)")
    }
}
