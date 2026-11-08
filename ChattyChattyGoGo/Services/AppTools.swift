import Contacts
import EventKit
import Foundation
import SwiftData
import Vision

struct ToolApprovalRequest: Identifiable, Sendable {
    let id: String
    let title: String
    let message: String
    let confirmTitle: String
}

/// App-owned tools. These run on the device; the model only receives their
/// declared schemas and the result after the user approves any sensitive action.
@MainActor
enum AppToolRegistry {
    static func displayName(for tool: String) -> String {
        switch tool {
        case "calculator": "Calculator"
        case "convert_units": "Unit converter"
        case "current_time", "date_difference": "Date and time"
        case "search_chats": "Searching saved chats"
        case "ocr_image": "Reading image text"
        case "read_url": "Reading web page"
        case "calendar_events": "Checking calendar"
        case "create_calendar_event": "Creating calendar event"
        case "create_reminder": "Creating reminder"
        case "lookup_contacts": "Searching contacts"
        case "open_maps": "Preparing Maps link"
        default: "Using app tool"
        }
    }

    static let definitions: [FunctionToolDefinition] = [
        tool("calculator", "Evaluate an arithmetic expression exactly.", [
            "expression": string("Use numbers, parentheses, +, -, *, /, %, and ^.")
        ], required: ["expression"]),
        tool("convert_units", "Convert length, mass, volume, time, speed, or temperature units.", [
            "value": number("Value to convert."),
            "from": string("Source unit, e.g. km, lb, C, or mph."),
            "to": string("Target unit, e.g. mi, kg, F, or km/h.")
        ], required: ["value", "from", "to"]),
        tool("current_time", "Get the current date and time, optionally in an IANA time zone.", [
            "time_zone": string("Optional IANA time zone, such as Europe/Lisbon.")
        ]),
        tool("date_difference", "Calculate days between two ISO-8601 dates.", [
            "start": string("Start date or timestamp."),
            "end": string("End date or timestamp.")
        ], required: ["start", "end"]),
        tool("search_chats", "Search this device's saved conversations. Ask permission before sharing matches with the model.", [
            "query": string("Words to find in saved conversations.")
        ], required: ["query"]),
        tool("ocr_image", "Read text from an image attached to the current message using on-device OCR.", [
            "attachment_name": string("Optional image filename; omit to use the first attached image.")
        ]),
        tool("read_url", "Read one user-provided HTTPS page. Ask before fetching it; this is not general web search.", [
            "url": string("HTTPS URL to read.")
        ], required: ["url"]),
        tool("calendar_events", "Find calendar events in an ISO-8601 time range. Ask before sharing calendar details with the model.", [
            "start": string("Range start."),
            "end": string("Range end.")
        ], required: ["start", "end"]),
        tool("create_calendar_event", "Create a calendar event only after the user confirms the proposed details.", [
            "title": string("Event title."),
            "start": string("Start date/time in ISO-8601 format."),
            "end": string("End date/time in ISO-8601 format."),
            "notes": string("Optional notes."),
            "location": string("Optional location.")
        ], required: ["title", "start", "end"]),
        tool("create_reminder", "Create a reminder only after the user confirms the proposed details.", [
            "title": string("Reminder title."),
            "due_at": string("Optional due date/time in ISO-8601 format."),
            "notes": string("Optional notes.")
        ], required: ["title"]),
        tool("lookup_contacts", "Search contacts. Ask before sharing matching names and contact details with the model.", [
            "name": string("Name or part of a name to search for.")
        ], required: ["name"]),
        tool("open_maps", "Create an Apple Maps link for a place or address.", [
            "place": string("Place name or address.")
        ], required: ["place"])
    ]

    static func approval(for call: FunctionToolCall) -> ToolApprovalRequest? {
        guard let args = arguments(call.arguments) else { return nil }
        switch call.name {
        case "search_chats":
            let query = string(args, "query") ?? "the requested phrase"
            return .init(id: call.id, title: "Search saved chats?", message: "Search this device's conversation history for “\(query)” and share matching excerpts with the current model?", confirmTitle: "Search chats")
        case "read_url":
            let url = string(args, "url") ?? "the requested page"
            return .init(id: call.id, title: "Read this page?", message: "Fetch \(url) and share its extracted text with the current model?", confirmTitle: "Read page")
        case "calendar_events":
            let start = string(args, "start") ?? "the requested start"
            let end = string(args, "end") ?? "the requested end"
            return .init(id: call.id, title: "Check your calendar?", message: "Find events between \(start) and \(end), then share matching titles, times, and locations with the current model?", confirmTitle: "Check calendar")
        case "create_calendar_event":
            let title = string(args, "title") ?? "New event"
            let start = string(args, "start") ?? ""
            let end = string(args, "end") ?? ""
            let location = string(args, "location").map { " Location: \($0)." } ?? ""
            let notes = string(args, "notes").map { " Notes: \($0)" } ?? ""
            return .init(id: call.id, title: "Create calendar event?", message: "Create “\(title)” from \(start) to \(end).\(location)\(notes)", confirmTitle: "Create event")
        case "create_reminder":
            let title = string(args, "title") ?? "New reminder"
            let due = string(args, "due_at").map { " Due: \($0)." } ?? ""
            let notes = string(args, "notes").map { " Notes: \($0)" } ?? ""
            return .init(id: call.id, title: "Create reminder?", message: "Create “\(title)”.\(due)\(notes)", confirmTitle: "Create reminder")
        case "lookup_contacts":
            let name = string(args, "name") ?? "the requested name"
            return .init(id: call.id, title: "Search contacts?", message: "Look up “\(name)” and share matching names, phone numbers, and email addresses with the current model?", confirmTitle: "Search contacts")
        default:
            return nil
        }
    }

    static func deniedResult() -> String {
        encode(.object(["ok": .bool(false), "error": .string("The user declined this action.")]))
    }

    static func execute(_ call: FunctionToolCall, context: ModelContext, attachments: [Attachment]) async -> String {
        do {
            guard let args = arguments(call.arguments) else { throw ToolError.invalidArguments }
            let result: JSONValue
            switch call.name {
            case "calculator":
                let expression = try requiredString(args, "expression")
                var parser = ArithmeticParser(expression)
                let value = try parser.evaluate()
                result = .object(["value": .double(value), "formatted": .string(value.formatted(.number.precision(.significantDigits(1...10))))])
            case "convert_units":
                let value = try convert(requiredNumber(args, "value"), from: requiredString(args, "from"), to: requiredString(args, "to"))
                let targetUnit = try requiredString(args, "to")
                result = .object(["value": .double(value), "unit": .string(targetUnit)])
            case "current_time":
                result = currentTime(timeZoneID: string(args, "time_zone"))
            case "date_difference":
                let start = try parseDate(requiredString(args, "start"))
                let end = try parseDate(requiredString(args, "end"))
                let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? 0
                result = .object(["days": .int(days), "start": .string(isoString(start)), "end": .string(isoString(end))])
            case "search_chats":
                result = try searchChats(requiredString(args, "query"), context: context)
            case "ocr_image":
                result = try await recognizeImage(args, attachments: attachments)
            case "read_url":
                result = try await readURL(requiredString(args, "url"))
            case "calendar_events":
                result = try await calendarEvents(from: parseDate(requiredString(args, "start")), to: parseDate(requiredString(args, "end")))
            case "create_calendar_event":
                result = try await createCalendarEvent(
                    title: requiredString(args, "title"),
                    start: parseDate(requiredString(args, "start")),
                    end: parseDate(requiredString(args, "end")),
                    notes: string(args, "notes"),
                    location: string(args, "location")
                )
            case "create_reminder":
                result = try await createReminder(
                    title: requiredString(args, "title"),
                    dueAt: try string(args, "due_at").map(parseDate),
                    notes: string(args, "notes")
                )
            case "lookup_contacts":
                result = try await lookupContacts(requiredString(args, "name"))
            case "open_maps":
                let place = try requiredString(args, "place")
                var components = URLComponents(string: "https://maps.apple.com/")!
                components.queryItems = [URLQueryItem(name: "q", value: place)]
                result = .object(["place": .string(place), "url": .string(components.url?.absoluteString ?? "")])
            default:
                throw ToolError.unknown(call.name)
            }
            return encode(.object(["ok": .bool(true), "result": result]))
        } catch {
            return encode(.object(["ok": .bool(false), "error": .string(error.localizedDescription)]))
        }
    }

    private enum ToolError: LocalizedError {
        case invalidArguments
        case unknown(String)
        case invalidExpression
        case divisionByZero
        case unsupportedUnits(String, String)
        case invalidDate(String)
        case missingAttachment
        case noRecognizedText
        case invalidURL
        case pageTooLarge
        case httpStatus(Int)
        case permissionDenied(String)
        case missingCalendar

        var errorDescription: String? {
            switch self {
            case .invalidArguments: "The tool arguments were not valid."
            case .unknown(let name): "Unknown tool: \(name)."
            case .invalidExpression: "I could not evaluate that expression."
            case .divisionByZero: "Division by zero is not defined."
            case .unsupportedUnits(let from, let to): "Cannot convert \(from) to \(to)."
            case .invalidDate(let value): "Could not parse date: \(value). Use ISO-8601."
            case .missingAttachment: "There is no matching image attached to this message."
            case .noRecognizedText: "No readable text was found in the image."
            case .invalidURL: "Only public HTTPS pages can be read."
            case .pageTooLarge: "The page is too large to read."
            case .httpStatus(let status): "The page request failed with HTTP \(status)."
            case .permissionDenied(let kind): "Access to \(kind) was not granted."
            case .missingCalendar: "No writable calendar is available."
            }
        }
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: JSONValue], required: [String] = []) -> FunctionToolDefinition {
        FunctionToolDefinition(name: name, description: description, parameters: .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false)
        ]))
    }

    private static func string(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func number(_ description: String) -> JSONValue {
        .object(["type": .string("number"), "description": .string(description)])
    }

    private static func arguments(_ raw: String) -> [String: JSONValue]? {
        guard let data = raw.data(using: .utf8), case .object(let object) = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return object
    }

    private static func string(_ args: [String: JSONValue], _ key: String) -> String? {
        guard case .string(let value) = args[key] else { return nil }
        return value
    }

    private static func requiredString(_ args: [String: JSONValue], _ key: String) throws -> String {
        guard let value = string(args, key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { throw ToolError.invalidArguments }
        return value
    }

    private static func requiredNumber(_ args: [String: JSONValue], _ key: String) throws -> Double {
        switch args[key] {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: throw ToolError.invalidArguments
        }
    }

    private static func encode(_ value: JSONValue) -> String {
        guard let data = try? JSONValue.encode(value) else { return "{\"ok\":false,\"error\":\"Could not encode tool result\"}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func parseDate(_ value: String) throws -> Date {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: value) { return date }
        throw ToolError.invalidDate(value)
    }

    private static func isoString(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private static func currentTime(timeZoneID: String?) -> JSONValue {
        let zone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return .object(["iso8601": .string(isoString(now)), "local_time": .string(formatter.string(from: now)), "time_zone": .string(zone.identifier)])
    }

    private struct UnitSpec {
        let dimension: String
        /// base = input * scale + offset
        let scale: Double
        let offset: Double
    }

    private static let unitSpecs: [String: UnitSpec] = [
        "m": .init(dimension: "length", scale: 1, offset: 0), "meter": .init(dimension: "length", scale: 1, offset: 0),
        "km": .init(dimension: "length", scale: 1_000, offset: 0), "cm": .init(dimension: "length", scale: 0.01, offset: 0),
        "mm": .init(dimension: "length", scale: 0.001, offset: 0), "mi": .init(dimension: "length", scale: 1_609.344, offset: 0),
        "mile": .init(dimension: "length", scale: 1_609.344, offset: 0), "ft": .init(dimension: "length", scale: 0.3048, offset: 0),
        "in": .init(dimension: "length", scale: 0.0254, offset: 0), "kg": .init(dimension: "mass", scale: 1, offset: 0),
        "g": .init(dimension: "mass", scale: 0.001, offset: 0), "mg": .init(dimension: "mass", scale: 0.000001, offset: 0),
        "lb": .init(dimension: "mass", scale: 0.45359237, offset: 0), "lbs": .init(dimension: "mass", scale: 0.45359237, offset: 0),
        "oz": .init(dimension: "mass", scale: 0.028349523125, offset: 0), "l": .init(dimension: "volume", scale: 1, offset: 0),
        "liter": .init(dimension: "volume", scale: 1, offset: 0), "ml": .init(dimension: "volume", scale: 0.001, offset: 0),
        "gal": .init(dimension: "volume", scale: 3.785411784, offset: 0), "s": .init(dimension: "time", scale: 1, offset: 0),
        "sec": .init(dimension: "time", scale: 1, offset: 0), "min": .init(dimension: "time", scale: 60, offset: 0),
        "h": .init(dimension: "time", scale: 3_600, offset: 0), "hr": .init(dimension: "time", scale: 3_600, offset: 0),
        "day": .init(dimension: "time", scale: 86_400, offset: 0), "m/s": .init(dimension: "speed", scale: 1, offset: 0),
        "km/h": .init(dimension: "speed", scale: 1 / 3.6, offset: 0), "mph": .init(dimension: "speed", scale: 0.44704, offset: 0),
        "c": .init(dimension: "temperature", scale: 1, offset: 0), "°c": .init(dimension: "temperature", scale: 1, offset: 0),
        "f": .init(dimension: "temperature", scale: 5 / 9, offset: -32 * 5 / 9), "°f": .init(dimension: "temperature", scale: 5 / 9, offset: -32 * 5 / 9),
        "k": .init(dimension: "temperature", scale: 1, offset: -273.15)
    ]

    private static func convert(_ value: Double, from: String, to: String) throws -> Double {
        let sourceKey = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetKey = to.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let source = unitSpecs[sourceKey], let target = unitSpecs[targetKey], source.dimension == target.dimension else {
            throw ToolError.unsupportedUnits(from, to)
        }
        let converted = (value * source.scale + source.offset - target.offset) / target.scale
        guard converted.isFinite else { throw ToolError.invalidArguments }
        return converted
    }

    private static func searchChats(_ query: String, context: ModelContext) throws -> JSONValue {
        let messages = try context.fetch(FetchDescriptor<Message>())
            .filter { $0.role != .system && $0.content.localizedCaseInsensitiveContains(query) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(8)
        return .array(messages.map { message in
            .object([
                "chat": .string(message.conversation?.displayTitle ?? "Chat"),
                "role": .string(message.role.rawValue),
                "date": .string(isoString(message.createdAt)),
                "excerpt": .string(String(message.content.prefix(800)))
            ])
        })
    }

    private static func recognizeImage(_ args: [String: JSONValue], attachments: [Attachment]) async throws -> JSONValue {
        let name = string(args, "attachment_name")
        guard let attachment = attachments.first(where: { $0.kind == .image && (name == nil || $0.name.localizedCaseInsensitiveContains(name!)) }),
              let data = attachment.data else { throw ToolError.missingAttachment }
        let recognized = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
        }.value
        guard !recognized.isEmpty else { throw ToolError.noRecognizedText }
        return .object(["attachment": .string(attachment.name), "text": .string(String(recognized.prefix(20_000)))])
    }

    private static func readURL(_ raw: String) async throws -> JSONValue {
        guard let url = URL(string: raw), url.scheme == "https", let host = url.host,
              !host.localizedCaseInsensitiveContains("localhost"), !host.hasSuffix(".local"),
              !host.contains(":"), Int(host.split(separator: ".").first ?? "") == nil else { throw ToolError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("text/html,text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.setValue("ChattyChattyGoGo/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) else { throw ToolError.pageTooLarge }
        let text = extractPageText(html)
        return .object(["url": .string(url.absoluteString), "text": .string(String(text.prefix(16_000)))])
    }

    private static func extractPageText(_ html: String) -> String {
        var text = html
        for pattern in ["(?is)<script[^>]*>.*?</script>", "(?is)<style[^>]*>.*?</style>", "(?is)<noscript[^>]*>.*?</noscript>"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<\\s*br\\s*/?>|</(p|div|h[1-6]|li|tr|article|section)>\\s*", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            text = text.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func calendarEvents(from start: Date, to end: Date) async throws -> JSONValue {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw ToolError.permissionDenied("calendar") }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return .array(store.events(matching: predicate).prefix(25).map { event in
            .object([
                "title": .string(event.title ?? "Untitled"),
                "start": .string(isoString(event.startDate)),
                "end": .string(isoString(event.endDate)),
                "location": .string(event.location ?? "")
            ])
        })
    }

    private static func createCalendarEvent(title: String, start: Date, end: Date, notes: String?, location: String?) async throws -> JSONValue {
        guard end > start else { throw ToolError.invalidArguments }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw ToolError.permissionDenied("calendar") }
        guard let calendar = store.defaultCalendarForNewEvents else { throw ToolError.missingCalendar }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.location = location
        event.calendar = calendar
        try store.save(event, span: .thisEvent)
        return .object(["created": .bool(true), "title": .string(title), "start": .string(isoString(start)), "calendar": .string(calendar.title)])
    }

    private static func createReminder(title: String, dueAt: Date?, notes: String?) async throws -> JSONValue {
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw ToolError.permissionDenied("reminders") }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw ToolError.missingCalendar }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        if let dueAt {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueAt)
        }
        try store.save(reminder, commit: true)
        return .object(["created": .bool(true), "title": .string(title), "due_at": dueAt.map { .string(isoString($0)) } ?? .null])
    }

    private static func lookupContacts(_ query: String) async throws -> JSONValue {
        let store = CNContactStore()
        guard try await store.requestAccess(for: .contacts) else { throw ToolError.permissionDenied("contacts") }
        let keys: [CNKeyDescriptor] = [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
        let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys).prefix(8)
        return .array(contacts.map { contact in
            .object([
                "name": .string(CNContactFormatter.string(from: contact, style: .fullName) ?? query),
                "phone_numbers": .array(contact.phoneNumbers.map { .string($0.value.stringValue) }),
                "emails": .array(contact.emailAddresses.map { .string(String($0.value)) })
            ])
        })
    }

    private struct ArithmeticParser {
        private let characters: [Character]
        private var index = 0

        init(_ expression: String) { characters = Array(expression) }

        mutating func evaluate() throws -> Double {
            guard characters.count <= 512 else { throw ToolError.invalidExpression }
            let value = try expression()
            skipSpaces()
            guard index == characters.count, value.isFinite else { throw ToolError.invalidExpression }
            return value
        }

        private mutating func expression() throws -> Double {
            var value = try term()
            while true {
                skipSpaces()
                if consume("+") { value += try term() }
                else if consume("-") { value -= try term() }
                else { return value }
            }
        }

        private mutating func term() throws -> Double {
            var value = try power()
            while true {
                skipSpaces()
                if consume("*") { value *= try power() }
                else if consume("/") {
                    let divisor = try power()
                    guard divisor != 0 else { throw ToolError.divisionByZero }
                    value /= divisor
                } else if consume("%") {
                    let divisor = try power()
                    guard divisor != 0 else { throw ToolError.divisionByZero }
                    value.formTruncatingRemainder(dividingBy: divisor)
                } else { return value }
            }
        }

        private mutating func power() throws -> Double {
            let base = try unary()
            skipSpaces()
            guard consume("^") else { return base }
            return pow(base, try power())
        }

        private mutating func unary() throws -> Double {
            skipSpaces()
            if consume("+") { return try unary() }
            if consume("-") { return -(try unary()) }
            return try primary()
        }

        private mutating func primary() throws -> Double {
            skipSpaces()
            if consume("(") {
                let value = try expression()
                skipSpaces()
                guard consume(")") else { throw ToolError.invalidExpression }
                return value
            }
            let start = index
            var sawDigit = false
            while index < characters.count, characters[index].isNumber || characters[index] == "." {
                if characters[index].isNumber { sawDigit = true }
                index += 1
            }
            guard sawDigit, let value = Double(String(characters[start..<index])) else { throw ToolError.invalidExpression }
            return value
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }

        private mutating func consume(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }
    }
}
