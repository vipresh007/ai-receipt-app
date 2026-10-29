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
        var name: String?
        var isPayer: Bool?
        var itemIndexes: [Int]
        var amount: String?
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
        let isMe: Bool
        let isPayer: Bool
        let itemIndexes: [Int]
        let amount: String?
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

        var totalValue: Decimal { Decimal(string: total) ?? 0 }
        var myShareValue: Decimal? { myShare.flatMap { Decimal(string: $0) } }
        var payer: ParticipantDTO? { participants.first(where: \.isPayer) }
        var day: Date { ReceiptExtractionAPIClient.isoDay(date) ?? .now }
    }

    struct GroupSummaryDTO: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let currency: String
        let memberCount: Int
        let myBalance: String
        let inviteUrl: String
        let isOwner: Bool
    }

    struct GroupMemberDTO: Decodable, Identifiable, Hashable {
        let id: String
        let displayName: String
        let isMe: Bool
        let hasAccount: Bool
        /// Positive = is owed, negative = owes.
        let balance: String

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
