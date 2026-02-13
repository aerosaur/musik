import Foundation

public let musikVersionCore: String = "0.3.4"

fileprivate let readyForRelease: Bool = true

public let musikVersion: String =
    readyForRelease ? musikVersionCore : "rel-\(musikVersionCore)-\(VersionatorVersion.commit)"
