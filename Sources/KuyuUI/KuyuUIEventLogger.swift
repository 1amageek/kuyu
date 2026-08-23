import OSLog

enum KuyuUIEventLogger {
  private static let logger = Logger(
    subsystem: "kuyu",
    category: "kuyu.ui"
  )

  static func record(
    action: String,
    task: String,
    identifier: String
  ) {
    logger.info(
      "action=\(action, privacy: .public) task=\(task, privacy: .public) id=\(identifier, privacy: .public)"
    )
  }
}
