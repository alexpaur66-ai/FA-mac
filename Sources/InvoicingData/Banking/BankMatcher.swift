import Foundation
import InvoicingCore

/// The lane of the triage window a bank line lands in (screens-flows.md §2f, v0.2 bank import).
public enum BankMatchLane: String, Sendable, CaseIterable {
    /// The line is a payment already recorded by hand: accepting links the two instead of adding a second payment.
    case alreadyRecorded
    /// Variable symbol, amount and currency match one open document within the payment tolerance.
    case matched
    /// A likely document that needs one look: the amount differs, or only the account or the amount fits.
    case suggested
    /// An incoming line with no candidate.
    case unmatched
    /// Money that went out: fees, rent, taxes, or a refund to a client.
    case outgoing
    /// Matched, linked or ignored before; nothing to do.
    case resolved
}

/// Why a document is a candidate for a bank line; the triage row shows it as its reason label.
public enum BankMatchReason: String, Sendable, CaseIterable {
    /// A payment recorded by hand on a document with the line's variable symbol, same amount, a few days apart.
    case recordedPayment
    /// Variable symbol and amount.
    case variableSymbolAndAmount
    /// Variable symbol only: the amount would make it a partial payment or an overpayment.
    case variableSymbol
    /// The payer's account was confirmed for this client at least twice before, and the amount fits.
    case knownAccount
    /// Only the amount fits, and exactly one open document has it.
    case amountOnly
}

/// One document a bank line may belong to.
public struct BankMatchCandidate: Hashable, Sendable {
    public let documentID: String
    public let reason: BankMatchReason
    /// For `recordedPayment`: the payment the line confirms.
    public let paymentID: String?

    public init(documentID: String, reason: BankMatchReason, paymentID: String? = nil) {
        self.documentID = documentID
        self.reason = reason
        self.paymentID = paymentID
    }
}

/// A bank line with its lane and its candidates, best first.
public struct BankMatchProposal: Hashable, Sendable, Identifiable {
    public let transaction: BankTransaction
    public let lane: BankMatchLane
    public let candidates: [BankMatchCandidate]

    public var id: String { transaction.id }

    public init(transaction: BankTransaction, lane: BankMatchLane, candidates: [BankMatchCandidate] = []) {
        self.transaction = transaction
        self.lane = lane
        self.candidates = candidates
    }
}

/// Sorts bank lines into the lanes of the triage window (screens-flows.md §2f). It only proposes: nothing is
/// stored until the user accepts a line. The rules, checked in this order for each incoming line:
/// 1. Already recorded: a payment typed in by hand, not linked to a bank line yet, on a document with the
///    line's variable symbol, same amount within the tolerance, at most `recordedWindowDays` apart. Each
///    payment confirms one line; the closest day wins unless that leaves another line without its payment
///    (`recordedPayments` pairs the whole statement).
/// 2. Matched: exactly one open document with the line's variable symbol whose open balance equals the amount
///    within the tolerance. The matched amount comes off that balance for the lines after it, so a second
///    identical line becomes a suggestion (an overpayment) instead of a second exact match.
/// 3. Suggested: documents with the variable symbol (partial payment or overpayment); else open documents of
///    a client whose account the payer used in at least `confirmationsForKnownAccount` matched lines, with
///    the amount; else the one open document with the amount, when there is exactly one.
/// 4. Unmatched otherwise.
/// Outgoing lines go to Outgoing, with overpaid documents whose surplus equals the amount as refund candidates.
/// Only documents in the line's currency are candidates: a EUR document paid into a CZK account needs the
/// two-amount payment form, which is not built yet.
public enum BankMatcher {
    /// How many days a hand-recorded payment and its bank line may lie apart.
    public static let recordedWindowDays = 5
    /// How often an account must have paid a client before it counts as known (Fakturoid's rule, §2f).
    public static let confirmationsForKnownAccount = 2

    /// The lanes for `transactions`, in booking order. `documents` are the states of the stored documents
    /// (drafts and documents that take no payment are skipped), `payments` their payments (only received
    /// payments without a bank line count), and `confirmedAccounts` maps a payer account
    /// (`normalizedAccount`) to the clients it paid and how often (`StatementStore.confirmedAccounts`).
    public static func propose(_ transactions: [BankTransaction], documents: [DocumentState], payments: [DocumentPayment],
                               confirmedAccounts: [String: [String: Int]] = [:]) -> [BankMatchProposal] {
        let ordered = transactions.sorted { ($0.bookedOn, $0.id) < ($1.bookedOn, $1.id) }
        var remaining: [String: Decimal] = [:]
        for document in documents { remaining[document.id] = document.outstanding.amount }
        let unlinked = payments.filter { $0.kind == .received && $0.bankTransactionID == nil }
            .sorted { ($0.paidOn, $0.id) < ($1.paidOn, $1.id) }
        let recorded = recordedPayments(ordered, documents: documents, payments: unlinked)
        var proposals: [BankMatchProposal] = []

        for transaction in ordered {
            guard transaction.matchState == .unmatched else {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .resolved))
                continue
            }
            let amount = transaction.amount
            let symbol = canonicalSymbol(transaction.variableSymbol)
            let sameCurrency = documents.filter { $0.summary.currency == amount.currency }
            let bySymbol = symbol.map { symbol in sameCurrency.filter { canonicalSymbol($0.summary.variableSymbol) == symbol } } ?? []
            /// The document's open balance after the lines matched above equals `value` within the tolerance.
            func balanceFits(_ document: DocumentState, _ value: Decimal) -> Bool {
                let left = remaining[document.id] ?? 0
                return left > 0 && PaymentTolerance.matches(Money(left, amount.currency), Money(value, amount.currency))
            }

            if amount.amount < 0 {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .outgoing,
                                                   candidates: refundCandidates(transaction, sameCurrency, bySymbol)))
                continue
            }
            guard amount.amount > 0 else {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .unmatched))
                continue
            }

            // 1. Already recorded by hand (paired for the whole statement in `recordedPayments`).
            if let payment = recorded[transaction.id] {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .alreadyRecorded,
                                                   candidates: [BankMatchCandidate(documentID: payment.documentID, reason: .recordedPayment,
                                                                                   paymentID: payment.id)]))
                continue
            }

            // 2. Exact: variable symbol and amount.
            let exact = bySymbol.filter { $0.acceptsPayment && balanceFits($0, amount.amount) }
            if exact.count == 1, let document = exact.first {
                remaining[document.id, default: 0] -= amount.amount
                proposals.append(BankMatchProposal(transaction: transaction, lane: .matched,
                                                   candidates: [BankMatchCandidate(documentID: document.id, reason: .variableSymbolAndAmount)]))
                continue
            }
            if !exact.isEmpty {
                // Two open documents with one symbol: the user picks.
                proposals.append(BankMatchProposal(transaction: transaction, lane: .suggested,
                                                   candidates: exact.map { BankMatchCandidate(documentID: $0.id, reason: .variableSymbolAndAmount) }))
                continue
            }

            // 3. Suggestions.
            let symbolOnly = bySymbol.filter(\.takesIncomingPayment)
            if !symbolOnly.isEmpty {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .suggested,
                                                   candidates: symbolOnly.map { BankMatchCandidate(documentID: $0.id, reason: .variableSymbol) }))
                continue
            }
            let open = sameCurrency.filter { $0.acceptsPayment && balanceFits($0, amount.amount) }
            if let account = normalizedAccount(transaction.counterpartyAccount), let clients = confirmedAccounts[account] {
                let known = Set(clients.filter { $0.value >= confirmationsForKnownAccount }.map(\.key))
                let fromKnown = open.filter { document in document.summary.customerID.map { known.contains($0) } ?? false }
                if !fromKnown.isEmpty {
                    proposals.append(BankMatchProposal(transaction: transaction, lane: .suggested,
                                                       candidates: fromKnown.map { BankMatchCandidate(documentID: $0.id, reason: .knownAccount) }))
                    continue
                }
            }
            if open.count == 1, let document = open.first {
                proposals.append(BankMatchProposal(transaction: transaction, lane: .suggested,
                                                   candidates: [BankMatchCandidate(documentID: document.id, reason: .amountOnly)]))
                continue
            }
            proposals.append(BankMatchProposal(transaction: transaction, lane: .unmatched))
        }
        return proposals
    }

    /// Rule 1 for the whole statement: the hand-recorded payment each incoming unmatched line confirms, by line
    /// id. A line may take a payment on a document with its variable symbol, in its currency, with its amount
    /// within the tolerance, at most `recordedWindowDays` apart. Lines take their closest payment in booking
    /// order; a line whose payments are all taken moves an earlier line to another of its payments when it can,
    /// so two instalments are both confirmed whatever order their lines come in. Each payment confirms one line.
    private static func recordedPayments(_ ordered: [BankTransaction], documents: [DocumentState],
                                         payments: [DocumentPayment]) -> [String: DocumentPayment] {
        var lineIDs: [String] = []
        // For each line in `lineIDs`, the indices of the payments it may take, closest first.
        var options: [[Int]] = []
        for transaction in ordered {
            let amount = transaction.amount
            guard transaction.matchState == .unmatched, amount.amount > 0,
                  let symbol = canonicalSymbol(transaction.variableSymbol) else { continue }
            let symbolDocuments = Set(documents
                .filter { $0.summary.currency == amount.currency && canonicalSymbol($0.summary.variableSymbol) == symbol }
                .map(\.id))
            var fitting: [(distance: Int, index: Int)] = []
            for index in payments.indices {
                let payment = payments[index]
                guard symbolDocuments.contains(payment.documentID), PaymentTolerance.matches(payment.amount, amount) else { continue }
                let distance = abs(payment.paidOn.days(since: transaction.bookedOn))
                if distance <= recordedWindowDays {
                    fitting.append((distance: distance, index: index))
                }
            }
            guard !fitting.isEmpty else { continue }
            lineIDs.append(transaction.id)
            options.append(fitting.sorted { ($0.distance, $0.index) < ($1.distance, $1.index) }.map { $0.index })
        }
        // Payment index → the line (index into `lineIDs`) that confirms it.
        var owner: [Int: Int] = [:]
        for line in options.indices {
            var visited: Set<Int> = []
            _ = assignRecordedPayment(line, options: options, owner: &owner, visited: &visited)
        }
        var byLine: [String: DocumentPayment] = [:]
        for (payment, line) in owner {
            byLine[lineIDs[line]] = payments[payment]
        }
        return byLine
    }

    /// Gives `line` one of its payments, closest first; a payment another line holds is taken over when that
    /// line can move to another of its own (an augmenting path). False when no payment can be freed.
    private static func assignRecordedPayment(_ line: Int, options: [[Int]], owner: inout [Int: Int],
                                              visited: inout Set<Int>) -> Bool {
        for payment in options[line] where !visited.contains(payment) {
            visited.insert(payment)
            if let holder = owner[payment] {
                guard assignRecordedPayment(holder, options: options, owner: &owner, visited: &visited) else { continue }
            }
            owner[payment] = line
            return true
        }
        return false
    }

    /// Overpaid documents whose surplus equals the outgoing amount: those with the line's symbol, else the
    /// only one with that surplus. An advance a final invoice deducted or settled is left out: what it holds
    /// may be the final invoice's, and the store refuses a refund of that (`refundExceedsAvailable`).
    private static func refundCandidates(_ transaction: BankTransaction, _ sameCurrency: [DocumentState],
                                         _ bySymbol: [DocumentState]) -> [BankMatchCandidate] {
        let paidOut = Money(-transaction.amount.amount, transaction.amount.currency)
        func surplusFits(_ document: DocumentState) -> Bool {
            document.acceptsRefund && !(document.summary.kind == .advanceRequest && document.deductedInFinal)
                && PaymentTolerance.matches(Money(-document.outstanding.amount, document.outstanding.currency), paidOut)
        }
        let withSymbol = bySymbol.filter(surplusFits)
        if !withSymbol.isEmpty {
            return withSymbol.map { BankMatchCandidate(documentID: $0.id, reason: .variableSymbolAndAmount) }
        }
        let byAmount = sameCurrency.filter(surplusFits)
        return byAmount.count == 1 ? byAmount.map { BankMatchCandidate(documentID: $0.id, reason: .amountOnly) } : []
    }

    /// A variable symbol as banks compare it: digits only, without leading zeros; nil when there are none.
    public static func canonicalSymbol(_ text: String?) -> String? {
        let digits = (text ?? "").filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let stripped = digits.drop { $0 == "0" }
        return stripped.isEmpty ? "0" : String(stripped)
    }

    /// One spelling per account, so a payer's IBAN and their Czech account number count as the same account:
    /// the IBAN when the text is one or a Czech account number, otherwise the text in capitals without blanks.
    public static func normalizedAccount(_ text: String?) -> String? {
        guard let text else { return nil }
        let compact = text.filter { !$0.isWhitespace }.uppercased()
        guard !compact.isEmpty else { return nil }
        if let iban = IBAN(compact) { return iban.value }
        if let account = CzechBankAccount(parsing: text.trimmingCharacters(in: .whitespaces)), let iban = IBAN.czech(account) {
            return iban.value
        }
        return compact
    }
}
