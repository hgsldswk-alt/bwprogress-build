import Foundation

enum TransferError: Error { case malformed, tooLarge, unsupported }

enum SheetCode {
    static let prefix = "BW1:"
    static let limit = 4096
    static let maxGroups = 8
    static let maxMoves = 32

    private struct Template: Codable, Equatable {
        var n: String
        var g: [Group]
    }

    private struct Group: Codable, Equatable {
        var n: String
        var m: [Move]
    }

    private struct Move: Codable, Equatable {
        var n: String
        var u: Measurement
        var h: String?
    }

    static func encode(_ sheet: TrainingSheet) throws -> String {
        let template = template(for: sheet)
        try validate(template)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(template)
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard prefix.count + payload.count <= limit else { throw TransferError.tooLarge }
        return prefix + payload
    }

    static func decode(_ raw: String) throws -> TrainingSheet {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= limit else { throw TransferError.tooLarge }
        guard code.hasPrefix(prefix) else { throw TransferError.unsupported }
        let token = code.dropFirst(prefix.count)
        let alphabet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard !token.isEmpty, token.unicodeScalars.allSatisfy(alphabet.contains) else { throw TransferError.malformed }
        var payload = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw TransferError.malformed }
        let template = try JSONDecoder().decode(Template.self, from: data)
        try validate(template)
        let groups = template.g.map { group in
            let moves = group.m.map { Movement(id: UUID().uuidString, name: $0.n, unit: $0.u, hint: $0.h ?? "") }
            return MovementGroup(id: UUID().uuidString, name: group.n, moves: moves, currentID: moves[0].id)
        }
        return TrainingSheet(id: UUID().uuidString, name: template.n, groups: groups)
    }

    static func matches(_ first: TrainingSheet, _ second: TrainingSheet) -> Bool {
        template(for: first) == template(for: second)
    }

    private static func template(for sheet: TrainingSheet) -> Template {
        Template(n: sheet.title, g: sheet.groups.map { group in
            Group(n: group.title, m: group.moves.map { move in
                Move(n: move.title, u: move.unit, h: move.instruction.isEmpty ? nil : move.instruction)
            })
        })
    }

    private static func validate(_ template: Template) throws {
        func nameOK(_ name: String) -> Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && name.count <= 60 && name.rangeOfCharacter(from: .controlCharacters) == nil
        }
        guard nameOK(template.n), (1...maxGroups).contains(template.g.count),
              template.g.reduce(0, { $0 + $1.m.count }) <= maxMoves else { throw TransferError.malformed }
        for group in template.g {
            guard nameOK(group.n), !group.m.isEmpty,
                  group.m.allSatisfy({ move in
                      nameOK(move.n) && (move.h?.count ?? 0) <= 180
                          && move.h?.rangeOfCharacter(from: .controlCharacters) == nil
                  }) else { throw TransferError.malformed }
        }
    }
}

enum TrainingCSV {
    static func escaped(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let risk = trimmed.first.map { "=+-@＝＋－＠".contains($0) } ?? false
        let protected = risk || value.hasPrefix("\t") || value.hasPrefix("\r") || value.hasPrefix("\n")
            ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func render(_ sessions: [Session]) -> String {
        let header = ["csv.date", "csv.zone", "csv.session", "csv.sheet", "csv.movement", "csv.unit",
                      "csv.value", "csv.set"]
            .map { escaped(L.t($0)) }.joined(separator: ",")
        let data = sessions.flatMap { session in
            session.entries.flatMap { entry in
                entry.sets.enumerated().map { index, set in
                    [session.day.key, session.day.zoneID, session.id.uuidString, session.title,
                     entry.movement.title, entry.movement.unit.spoken, String(set.value), String(index + 1)]
                        .map(escaped).joined(separator: ",")
                }
            }
        }
        return ([header] + data).joined(separator: "\r\n") + "\r\n"
    }
}
