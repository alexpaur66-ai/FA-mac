// The sentence the user sees for a failed action (screens-flows.md §4: say what happened and how to fix
// it). DataError has no LocalizedError conformance, so the shell maps its cases here instead of showing
// the Swift case dump that String(describing:) prints; the same for the numbering errors of the core.

import Foundation
import InvoicingCore
import InvoicingData

enum ErrorText {
    /// A short English sentence for `error`; amounts are formatted for `locale`.
    static func message(_ error: Error, locale: Locale = .current) -> String {
        if let dataError = error as? DataError {
            return String(localized: resource(dataError, locale: locale))
        }
        if let parseError = error as? CNBRateFile.ParseError {
            switch parseError {
            case .malformedLine(let lineNumber, _):
                return String(localized: L.rateImportFailedAtLine(lineNumber))
            case .malformedHeader, .unknownDate:
                return String(localized: L.rateImportBadHeader)
            case .empty:
                return String(localized: L.rateImportFailed)
            }
        }
        if let patternError = error as? DocumentNumberPattern.PatternError {
            return String(localized: resource(patternError))
        }
        if let numbering = error as? DocumentNumberSeries.NumberingError {
            return String(localized: resource(numbering))
        }
        var text = String(localized: L.errorGeneric)
        if let detail = (error as? LocalizedError)?.errorDescription, !detail.isEmpty {
            text += " (" + detail + ")"
        }
        return text
    }

    /// The number pattern's problems (screens-flows.md §2i), each saying how to fix it.
    private static func resource(_ error: DocumentNumberPattern.PatternError) -> LocalizedStringResource {
        switch error {
        case .missingCounter: L.errorPatternMissingCounter
        case .multipleCounters: L.errorPatternMultipleCounters
        case .unknownToken(let token): L.errorPatternUnknownToken(token)
        case .unterminatedToken: L.errorPatternUnterminated
        }
    }

    private static func resource(_ error: DocumentNumberSeries.NumberingError) -> LocalizedStringResource {
        switch error {
        case .dayBeforeSeriesYear(_, let seriesYear): L.errorDayBeforeSeriesYear(String(seriesYear))
        case .resettingSeriesRequiresYearInPattern: L.errorSeriesNeedsYear
        case .invalidState: L.errorSeriesInvalidState
        case .invalidVariableSymbolPrefix(let prefix): L.errorInvalidVSPrefix(prefix)
        }
    }

    private static func resource(_ error: DataError, locale: Locale) -> LocalizedStringResource {
        func amount(_ money: Money) -> String {
            MoneyText.format(money.amount, currency: money.currency.code, locale: locale)
        }
        switch error {
        case .documentNotFound, .customerNotFound, .seriesNotFound, .statementNotFound, .transactionNotFound,
             .paymentNotFound:
            return L.errorNotFound
        case .paymentLocked, .relatedPaymentLocked:
            return L.paymentLocked
        case .documentIsFrozen, .documentAlreadyIssued:
            return L.errorFrozen
        case .documentNotIssued:
            return L.errorNotIssued
        case .customerHasDocuments:
            return L.errorCustomerHasDocuments
        case .validationFailed(let issues):
            // The UI is English (decision of 5 Nov 2026); the Czech texts stay on the printed documents.
            return L.errorValidation(issues.map { $0.message(language: .english) }.joined(separator: " "))
        case .amountOutOfRange:
            return L.errorAmountOutOfRange
        case .currencyMismatch(let expected, _):
            return L.errorCurrencyMismatch(expected.code)
        case .seriesDoesNotNumber:
            return L.errorSeriesKind
        case .invalidPaymentAmount:
            return L.errorAmountNotPositive
        case .creditNotAvailable(_, let available, _):
            return L.errorCreditAvailable(amount(available))
        case .creditExceedsOutstanding(_, let outstanding, _):
            return L.errorCreditOutstanding(amount(outstanding))
        case .documentHasPayments:
            return L.errorHasPayments
        case .documentIsDeducted:
            return L.errorDeducted
        case .documentAlreadyClosed:
            return L.errorAlreadyClosed
        case .documentNotClosed:
            return L.errorNotClosed
        case .closureNotApplicable:
            return L.errorClosureNotApplicable
        case .reasonRequired:
            return L.errorReasonRequired
        case .refundExceedsAvailable(_, let available, _):
            return L.errorRefundExceeds(amount(available))
        case .documentNotPayable:
            return L.errorNotPayable
        case .duplicateStatement:
            return L.errorDuplicateStatement
        case .corruptRecord:
            return L.errorCorruptRecord
        case .advanceAlreadyDeducted:
            return L.errorAdvanceDeducted
        case .creditCustomerMismatch:
            return L.errorCreditCustomer
        case .receiptMismatch:
            return L.errorReceiptMismatch
        default:
            return L.errorGeneric
        }
    }
}
