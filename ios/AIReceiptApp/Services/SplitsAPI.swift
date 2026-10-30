import Foundation

/// Splits and groups (docs/SPLITS.md): split a receipt with anyone, or keep a
/// running tab inside a group. Bearer only. Wire names are the backend's
/// snake_case, converted by the coders below.
extension ReceiptExtractionAPIClient {
    // MARK: - Splits

    func split(id: String) async throws -> SplitDTO {
        try await splitsCall("GET", "v1/splits/\(id)")
    }

    func createSplit(_ body: SplitWrite) async throws -> SplitDTO {
        try await splitsCall("POST", "v1/splits", body: body)
    }

    func updateSplit(id: String, _ body: SplitWrite) async throws -> SplitDTO {
        try await splitsCall("PUT", "v1/splits/\(id)", body: body)
    }

    func deleteSplit(id: String) async throws {
        try await splitsSend("DELETE", "v1/splits/\(id)")
    }

    /// One-off splits: mark someone's share paid (or not).
    func setSettled(splitID: String, participantID: String, settled: Bool) async throws -> SplitDTO {
        try await splitsCall(
            "POST", "v1/splits/\(splitID)/participants/\(participantID)/settled",
            body: ["settled": settled]
        )
    }

    // MARK: - Groups

    func groups() async throws -> [GroupSummaryDTO] {
        try await splitsCall("GET", "v1/groups")
    }

    func group(id: String) async throws -> GroupDetailDTO {
        try await splitsCall("GET", "v1/groups/\(id)")
    }

    func createGroup(name: String, currency: String, members: [String]) async throws -> GroupDetailDTO {
        try await splitsCall("POST", "v1/groups", body: GroupWrite(name: name, currency: currency, members: members))
    }

    /// Fewest payments (A owes B, B owes C → A pays C), or who owes whom directly.
    func setSimplifyDebts(groupID: String, _ on: Bool) async throws -> GroupDetailDTO {
        try await splitsCall("PATCH", "v1/groups/\(groupID)", body: ["simplify_debts": on])
    }

    func deleteGroup(id: String) async throws {
        try await splitsSend("DELETE", "v1/groups/\(id)")
    }

    func addMember(groupID: String, name: String) async throws -> GroupDetailDTO {
        try await splitsCall("POST", "v1/groups/\(groupID)/members", body: ["name": name])
    }

    func removeMember(groupID: String, memberID: String) async throws -> GroupDetailDTO {
        try await splitsCall("DELETE", "v1/groups/\(groupID)/members/\(memberID)")
    }

    /// "from paid to": records a payment between two members.
    func addSettlement(groupID: String, from: String, to: String, amount: Decimal) async throws -> GroupDetailDTO {
        try await splitsCall(
            "POST", "v1/groups/\(groupID)/settlements",
            body: SettlementWrite(fromMemberId: from, toMemberId: to, amount: amount.wireString, note: "")
        )
    }

    func deleteSettlement(groupID: String, id: String) async throws -> GroupDetailDTO {
        try await splitsCall("DELETE", "v1/groups/\(groupID)/settlements/\(id)")
    }

    // MARK: - People (split with anyone, no group)

    func people() async throws -> [PersonDTO] {
        try await splitsCall("GET", "v1/people")
    }

    func person(id: String) async throws -> PersonDetailDTO {
        try await splitsCall("GET", "v1/people/\(id)")
    }

    func createPerson(name: String, email: String?) async throws -> PersonDetailDTO {
        try await splitsCall("POST", "v1/people", body: PersonWrite(name: name, email: email))
    }

    func updatePerson(id: String, name: String? = nil, email: String? = nil) async throws -> PersonDetailDTO {
        try await splitsCall("PATCH", "v1/people/\(id)", body: PersonWrite(name: name, email: email))
    }

    /// Email them their invite link (needs an address on file).
    func invitePerson(id: String) async throws -> PersonDetailDTO {
        try await splitsCall("POST", "v1/people/\(id)/invite", body: [String: String]())
    }

    func deletePerson(id: String) async throws {
        try await splitsSend("DELETE", "v1/people/\(id)")
    }

    func addPersonPayment(personID: String, youPaid: Bool, amount: Decimal) async throws -> PersonDetailDTO {
        try await splitsCall(
            "POST", "v1/people/\(personID)/payments",
            body: PersonPaymentWrite(youPaid: youPaid, amount: amount.wireString, note: "")
        )
    }

    func deletePersonPayment(personID: String, id: String) async throws -> PersonDetailDTO {
        try await splitsCall("DELETE", "v1/people/\(personID)/payments/\(id)")
    }

    /// Anyone on an expense: change the amounts, who paid, how it's divided.
    func adjustSplit(id: String, _ body: SplitAdjustWrite) async throws -> SplitDTO {
        try await splitsCall("PATCH", "v1/splits/\(id)", body: body)
    }

    func timeline(splitID: String) async throws -> [TimelineEntryDTO] {
        try await splitsCall("GET", "v1/splits/\(splitID)/timeline")
    }

    func addComment(splitID: String, body: String) async throws -> [TimelineEntryDTO] {
        try await splitsCall("POST", "v1/splits/\(splitID)/comments", body: ["body": body])
    }

    func deleteComment(splitID: String, id: String) async throws -> [TimelineEntryDTO] {
        try await splitsCall("DELETE", "v1/splits/\(splitID)/comments/\(id)")
    }

    func remindPerson(id: String) async throws -> PersonDetailDTO {
        try await splitsCall("POST", "v1/people/\(id)/remind", body: [String: String]())
    }

    func remindMember(groupID: String, memberID: String) async throws -> GroupDetailDTO {
        try await splitsCall("POST", "v1/groups/\(groupID)/members/\(memberID)/remind", body: [String: String]())
    }

    // MARK: - Activity, settings, export

    func activity() async throws -> ActivityFeedDTO {
        try await splitsCall("GET", "v1/activity")
    }

    func unreadActivity() async throws -> Int {
        let result: [String: Int] = try await splitsCall("GET", "v1/activity/unread")
        return result["unread"] ?? 0
    }

    func markActivityRead() async throws {
        let _: [String: Int] = try await splitsCall("POST", "v1/activity/read", body: [String: String]())
    }

    func me() async throws -> MeDTO {
        try await splitsCall("GET", "v1/auth/me")
    }

    func updateMe(_ body: MeSettingsWrite) async throws -> MeDTO {
        try await splitsCall("PATCH", "v1/auth/me", body: body)
    }

    /// `receipts` or `shared`: a CSV file's bytes.
    func exportCSV(_ name: String) async throws -> Data {
        let (data, http) = try await send(try authorized("v1/export/\(name).csv", method: "GET"))
        try Self.expectOK(http, data, "Couldn't export")
        return data
    }

    // MARK: - Transport

    private static let splitsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let splitsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func splitsRequest(_ method: String, _ path: String, body: (any Encodable)?) throws -> URLRequest {
        var request = try authorized(path, method: method)
        if let body { request.httpBody = try Self.splitsEncoder.encode(body) }
        return request
    }

    private func splitsCall<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        let (data, http) = try await send(try splitsRequest(method, path, body: body))
        try Self.expectOK(http, data, "Couldn't reach Tally")
        return try Self.splitsDecoder.decode(T.self, from: data)
    }

    private func splitsSend(_ method: String, _ path: String) async throws {
        let (data, http) = try await send(try splitsRequest(method, path, body: nil))
        if method == "DELETE", http.statusCode == 404 { return }
        try Self.expectOK(http, data, "Couldn't reach Tally")
    }

    // MARK: - Wire types

    struct ParticipantWrite: Encodable {
        var isMe: Bool?
        var memberId: String?
        var personId: String?
        var name: String?
        var isPayer: Bool?
        var itemIndexes: [Int]
        var amount: String?
        var weight: String? = nil
        var paid: String? = nil
    }

    struct ParticipantAdjustWrite: Encodable {
        let id: String
        var isPayer: Bool
        var paid: String?
        var itemIndexes: [Int]
        var amount: String?
        var weight: String?
    }

    struct SplitAdjustWrite: Encodable {
        var description: String?
        var total: String?
        var date: String?
        var mode: SplitMath.Mode
        var participants: [ParticipantAdjustWrite]
    }

    struct MeSettingsWrite: Encodable {
        var emailNotifications: Bool?
        var paypalMe: String?
        var interac: String?
    }

    struct MeDTO: Decodable {
        let id: String
        let email: String
        let displayName: String
        let emailNotifications: Bool
        let paypalMe: String
        let interac: String
    }

    struct PayDetailsDTO: Decodable, Hashable {
        let paypalMe: String?
        let interac: String?
    }

    struct TimelineEntryDTO: Decodable, Identifiable, Hashable {
        let id: String
        let kind: String
        let authorName: String
        let text: String
        let at: String
        let canDelete: Bool

        var isComment: Bool { kind == "comment" }
        var date: Date { ISO8601DateFormatter.tally(at) ?? .now }
    }

    struct ActivityItemDTO: Decodable, Identifiable, Hashable {
        let id: String
        let actorName: String
        let kind: String
        let text: String
        let at: String
        let read: Bool
        let splitId: String?
        let groupId: String?
        let personId: String?

        var date: Date { ISO8601DateFormatter.tally(at) ?? .now }
    }

    struct ActivityFeedDTO: Decodable {
        let unread: Int
        let items: [ActivityItemDTO]
    }

    struct SplitWrite: Encodable {
        var receiptId: String?
        var groupId: String?
        var description: String?
        var total: String?
        var currency: String?
        var date: String?
        var mode: SplitMath.Mode
        var participants: [ParticipantWrite]
        var `repeat`: String? = nil
    }

    struct GroupWrite: Encodable {
        let name: String
        let currency: String
        let members: [String]
    }

    struct SettlementWrite: Encodable {
        let fromMemberId: String
        let toMemberId: String
        let amount: String
        let note: String
    }

    struct ItemDTO: Decodable, Hashable {
        let name: String
        let price: String
        let quantity: Int?
    }

    struct ParticipantDTO: Decodable, Identifiable, Hashable {
        let id: String
        let displayName: String
        let memberId: String?
        let personId: String?
        let isMe: Bool
        let isPayer: Bool
        let itemIndexes: [Int]
        let amount: String?
        let weight: String?
        let paid: String?
        let share: String
        let settled: Bool
        let shareUrl: String

        var shareValue: Decimal { Decimal(string: share) ?? 0 }
    }

    struct SplitDTO: Decodable, Identifiable, Hashable {
        let id: String
        let receiptId: String?
        let groupId: String?
        let description: String
        let total: String
        let currency: String
        let date: String
        let mode: SplitMath.Mode
        let items: [ItemDTO]
        let participants: [ParticipantDTO]
        let myShare: String?
        let isOwner: Bool
        let canEdit: Bool
        let `repeat`: String
        let nextAt: String?

        var totalValue: Decimal { Decimal(string: total) ?? 0 }
        var myShareValue: Decimal? { myShare.flatMap { Decimal(string: $0) } }
        var payer: ParticipantDTO? { participants.first(where: \.isPayer) }
        var payers: [ParticipantDTO] { participants.filter(\.isPayer) }
        var day: Date { ReceiptExtractionAPIClient.isoDay(date) ?? .now }
    }

    struct PersonWrite: Encodable {
        var name: String?
        var email: String?
    }

    struct PersonPaymentWrite: Encodable {
        let youPaid: Bool
        let amount: String
        let note: String
    }

    /// Someone you split with outside groups. Balance: positive = they owe you.
    struct PersonDTO: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let email: String?
        let hasAccount: Bool
        let inviteUrl: String
        let invitedAt: String?
        let balance: String
        let outsideGroups: String
        let groupBalances: [PersonGroupBalanceDTO]
        let currency: String
        let canEmail: Bool
        let payTo: PayDetailsDTO?

        var balanceValue: Decimal { Decimal(string: balance) ?? 0 }
    }

    struct PersonGroupBalanceDTO: Decodable, Hashable {
        let groupId: String
        let name: String
        let balance: String

        var balanceValue: Decimal { Decimal(string: balance) ?? 0 }
    }

    struct PersonPaymentDTO: Decodable, Identifiable, Hashable {
        let id: String
        let youPaid: Bool
        let amount: String
        let note: String
        let date: String
        let canDelete: Bool

        var amountValue: Decimal { Decimal(string: amount) ?? 0 }
    }

    struct PersonDetailDTO: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let email: String?
        let hasAccount: Bool
        let inviteUrl: String
        let invitedAt: String?
        let balance: String
        let outsideGroups: String
        let groupBalances: [PersonGroupBalanceDTO]
        let currency: String
        let canEmail: Bool
        let payTo: PayDetailsDTO?
        let splits: [SplitDTO]
        let payments: [PersonPaymentDTO]

        var balanceValue: Decimal { Decimal(string: balance) ?? 0 }
    }

    struct GroupSummaryDTO: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let currency: String
        let memberCount: Int
        let myBalance: String
        let inviteUrl: String
        let isOwner: Bool
        let simplifyDebts: Bool
    }

    struct GroupMemberDTO: Decodable, Identifiable, Hashable {
        let id: String
        let displayName: String
        let isMe: Bool
        let hasAccount: Bool
        /// Positive = is owed, negative = owes.
        let balance: String
        let payTo: PayDetailsDTO?

        var balanceValue: Decimal { Decimal(string: balance) ?? 0 }
    }

    struct PaymentDTO: Decodable, Hashable {
        let fromMemberId: String
        let toMemberId: String
        let amount: String

        var amountValue: Decimal { Decimal(string: amount) ?? 0 }
    }

    struct SettlementDTO: Decodable, Identifiable, Hashable {
        let id: String
        let fromMemberId: String
        let toMemberId: String
        let amount: String
        let note: String
        let date: String

        var amountValue: Decimal { Decimal(string: amount) ?? 0 }
    }

    struct GroupDetailDTO: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let currency: String
        let memberCount: Int
        let myBalance: String
        let inviteUrl: String
        let isOwner: Bool
        let simplifyDebts: Bool
        let members: [GroupMemberDTO]
        let payments: [PaymentDTO]
        let splits: [SplitDTO]
        let settlements: [SettlementDTO]

        var myBalanceValue: Decimal { Decimal(string: myBalance) ?? 0 }

        func memberName(_ memberID: String) -> String {
            guard let member = members.first(where: { $0.id == memberID }) else { return "Someone" }
            return member.isMe ? "You" : member.displayName
        }
    }
}

extension Decimal {
    /// "12.5" style string for the wire (money is never a float).
    var wireString: String { NSDecimalNumber(decimal: self).stringValue }
}

/// Splits and groups need an account: they're shared with other people.
enum Splits {
    @MainActor
    static func client(_ auth: AuthManager) async throws -> ReceiptExtractionAPIClient {
        guard let client = await ReceiptExtractionService.makeAuthorizedClient(auth: auth) else {
            throw ReceiptExtractionError.notConfigured
        }
        return client
    }
}


extension ISO8601DateFormatter {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole = ISO8601DateFormatter()

    /// The API's timestamps, with or without fractional seconds.
    static func tally(_ string: String) -> Date? {
        fractional.date(from: string) ?? whole.date(from: string)
    }
}
