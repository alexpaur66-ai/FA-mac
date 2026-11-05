// The sentence the user sees for a failed action (screens-flows.md §4: say what happened and how to fix
// it). DataError has no LocalizedError conformance, so the shell maps its cases here instead of showing
// the Swift case dump that String(describing:) prints.

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
        var text = String(localized: L.errorGeneric)
        if let detail = (error as? LocalizedError)?.errorDescription, !detail.isEmpty {
            text += " (" + detail + ")"
        }
        return text
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
            let language = DocumentLanguage.ui(locale)
            return L.errorValidation(issues.map { $0.message(language: language) }.joined(separator: " "))
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
        default:
            return L.errorGeneric
        }
    }
}
