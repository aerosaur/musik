import ArgumentParser

struct SearchCommand: AsyncParsableCommand {

    @Flag(exclusivity: .exclusive)
    var from: SearchType?

    @Option(name: .shortAndLong)
    var type: MusicItemType = .song

    @Argument(parsing: .captureForPassthrough)
    var searchPhrase: [String] = []

    public func validate() throws {
        let searchType = from ?? .catalogSearch

        if type == .station && from == .librarySearch {
            throw ValidationError("Can't search user library for stations")
        }

        switch searchType {
        case .catalogSearch, .librarySearch:
            if searchPhrase.isEmpty {
                throw ValidationError(
                    "Search phrase is required for catalog and library searches."
                )
            }
        default: break
        }
    }

    /// Converts natural language keywords into proper argument flags.
    ///
    /// Examples:
    ///   "my playlists 2026"       → ["-l", "-t", "pl", "2026"]
    ///   "my songs bowie"          → ["-l", "-t", "so", "bowie"]
    ///   "album biffy clyro"       → ["-t", "al", "biffy", "clyro"]
    ///   "playlist rock"           → ["-t", "pl", "rock"]
    ///   "artist radiohead"        → ["-t", "ar", "radiohead"]
    ///   "biffy clyro"             → ["biffy", "clyro"]  (default: catalog songs)
    ///   "recent"                  → ["-r"]
    ///   "recommended"             → ["-s"]
    private static func preprocessKeywords(_ arguments: [String]) -> [String] {
        guard !arguments.isEmpty else { return arguments }

        // If arguments already contain flags (start with -), skip preprocessing
        if arguments.contains(where: { $0.hasPrefix("-") }) {
            return arguments
        }

        var words = arguments
        var result: [String] = []
        var consumed = 0

        // Check for "my" prefix → library search
        if words.first?.lowercased() == "my" {
            result.append("-l")
            words.removeFirst()
            consumed += 1
        }

        // Check for single-word shortcuts
        if words.count == 1 {
            switch words[0].lowercased() {
            case "recent", "recently", "recents":
                return ["-r"]
            case "recommended", "recommendations", "recs", "foryou":
                return ["-s"]
            default:
                break
            }
        }

        // Check for type keywords
        if let first = words.first {
            let keyword = first.lowercased()
            // Handle plural and singular forms
            let typeMap: [String: String] = [
                "song": "so", "songs": "so",
                "album": "al", "albums": "al",
                "artist": "ar", "artists": "ar",
                "playlist": "pl", "playlists": "pl",
                "station": "st", "stations": "st",
            ]
            if let typeArg = typeMap[keyword] {
                result.append(contentsOf: ["-t", typeArg])
                words.removeFirst()
                consumed += 1
            }
        }

        // If nothing was consumed, return original arguments unchanged
        if consumed == 0 {
            return arguments
        }

        // Remaining words are the search phrase
        result.append(contentsOf: words)
        return result
    }

    @MainActor
    static func execute(arguments: Array<String>) async {
        let processedArgs = preprocessKeywords(arguments)
        do {
            let command = try SearchCommand.parse(processedArgs)
            logger?.debug("New search command request: \(command)")
            var searchPhrase = ""
            for part in command.searchPhrase {
                searchPhrase.append("\(part) ")
            }
            if searchPhrase.count > 0 {
                searchPhrase.removeLast()
            }
            let limit = Config.shared.settings.searchItemLimit
            let searchType = command.from ?? .catalogSearch

            // If no explicit type flag was used and it's a text search,
            // do a multi-search (artists | albums | songs)
            let hasExplicitType = processedArgs.contains("-t") || processedArgs.contains("--type")

            // Intercept explicit playlist type with catalog search → dual playlist search
            if hasExplicitType && command.type == .playlist
                && searchType == .catalogSearch && !searchPhrase.isEmpty {
                Task {
                    await SearchManager.shared.newDualPlaylistSearch(
                        for: searchPhrase,
                        limit: limit
                    )
                }
            } else if !hasExplicitType && !searchPhrase.isEmpty
                && (searchType == .catalogSearch || searchType == .librarySearch) {
                Task {
                    await SearchManager.shared.newMultiSearch(
                        for: searchPhrase,
                        in: searchType,
                        limit: limit
                    )
                }
            } else {
                Task {
                    await SearchManager.shared.newSearch(
                        for: searchPhrase,
                        itemType: command.type,
                        in: searchType,
                        inPlace: true,
                        limit: limit
                    )
                }
            }
        } catch {
            if let error = error as? CommandError {
                switch error.parserError {
                case .userValidationError(let validationError):
                    let validationError = validationError as! ValidationError
                    let msg = validationError.message
                    logger?.debug("CommandParser: search: \(msg)")
                    await CommandInput.shared.setLastCommandOutput(msg)
                default:
                    let msg = "Error: wrong arguments"
                    logger?.debug("CommandParser: search: \(msg)")
                    await CommandInput.shared.setLastCommandOutput(msg)
                }
            }
        }
    }

}
