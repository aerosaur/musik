import Foundation

public let yatoroVersionCore: String = "0.3.4"

fileprivate let readyForRelease: Bool = true

public let yatoroVersion: String =
    readyForRelease ? yatoroVersionCore : "rel-\(yatoroVersionCore)-\(VersionatorVersion.commit)"
