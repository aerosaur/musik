import SwiftNotCurses

public struct Mapping: Codable {

    public var key: String
    public var modifiers: [Input.Modifier]?
    public let action: String

    public var remap: Bool = false

    public init(_ key: String, mod: [Input.Modifier]?, action: String) {
        self.key = key
        self.modifiers = mod
        self.action = action
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decodeIfPresent(String.self, forKey: .key) ?? ""
        var modifiers: [Input.Modifier] = []
        if let strModifiers = try container.decodeIfPresent(Array<String>.self, forKey: .modifiers) {
            for strModifier in strModifiers {
                if let mod = Input.Modifier(rawValue: strModifier.lowercased()) {
                    modifiers.append(mod)
                }
            }
        }
        if !modifiers.isEmpty {
            self.modifiers = modifiers
        }
        self.action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        self.remap = try container.decodeIfPresent(Bool.self, forKey: .remap) ?? false
    }
}

public extension Mapping {
    @MainActor static let defaultMappings: [Mapping] = [
        .init("p", mod: nil, action: ":playPauseToggle<CR>"),
        .init("p", mod: [.shift], action: ":play<CR>"),
        .init("p", mod: [.ctrl], action: ":pause<CR>"),
        .init("c", mod: nil, action: ":stop<CR>"),
        .init("x", mod: nil, action: ":clearQueue<CR>"),
        .init("f", mod: nil, action: ":playNext<CR>"),
        .init("f", mod: [.ctrl], action: ":startSeekingForward<CR>"),
        .init("g", mod: nil, action: ":stopSeeking<CR>"),
        .init("b", mod: nil, action: ":playPrevious<CR>"),
        .init("b", mod: [.ctrl], action: ":startSeekingBackward<CR>"),
        .init("r", mod: nil, action: ":restartSong<CR>"),
        .init("s", mod: nil, action: ":search "),
        .init("s", mod: [.ctrl], action: ":stationFromCurrentEntry<CR>"),
        .init("q", mod: nil, action: ":quitApplication<CR>"),
        .init("e", mod: nil, action: ":repeatMode<CR>"),
        .init("h", mod: nil, action: ":shuffleMode<CR>"),
        .init("ESC", mod: nil, action: ":close<CR>"),
        .init("j", mod: nil, action: ":selectDown<CR>"),
        .init("k", mod: nil, action: ":selectUp<CR>"),
        .init("ARROW_DOWN", mod: nil, action: ":selectDown<CR>"),
        .init("ARROW_UP", mod: nil, action: ":selectUp<CR>"),
        .init("ENTER", mod: nil, action: ":addSelectedAndPlay<CR>"),
        .init("l", mod: nil, action: ":openSelected<CR>"),
        .init("ARROW_LEFT", mod: nil, action: ":selectLeft<CR>"),
        .init("ARROW_RIGHT", mod: nil, action: ":selectRight<CR>"),
        .init("0", mod: nil, action: ":playIndex 0<CR>"),
        .init("1", mod: nil, action: ":playIndex 1<CR>"),
        .init("2", mod: nil, action: ":playIndex 2<CR>"),
        .init("3", mod: nil, action: ":playIndex 3<CR>"),
        .init("4", mod: nil, action: ":playIndex 4<CR>"),
        .init("5", mod: nil, action: ":playIndex 5<CR>"),
        .init("6", mod: nil, action: ":playIndex 6<CR>"),
        .init("7", mod: nil, action: ":playIndex 7<CR>"),
        .init("8", mod: nil, action: ":playIndex 8<CR>"),
        .init("9", mod: nil, action: ":playIndex 9<CR>"),
        .init("a", mod: nil, action: ":addAllAndPlay<CR>"),
        .init("=", mod: nil, action: ":volumeUp<CR>"),
        .init("-", mod: nil, action: ":volumeDown<CR>"),
        .init("TAB", mod: nil, action: ":toggleQueueFocus<CR>"),
        .init("BACKSPACE", mod: nil, action: ":removeFromQueue<CR>"),
    ]
}
