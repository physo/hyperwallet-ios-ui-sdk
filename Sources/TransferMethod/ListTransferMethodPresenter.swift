//
// Copyright 2018 - Present Hyperwallet
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
// BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import HyperwalletSDK
import UIKit

protocol ListTransferMethodView: class {
    func showLoading()
    func hideLoading()
    func showProcessing()
    func dismissProcessing(handler: @escaping () -> Void)
    func showConfirmation(handler: @escaping (() -> Void))
    func showTransferMethods()
    func notifyTransferMethodDeactivated(_ hyperwalletStatusTransition: HyperwalletStatusTransition)
    func showError(_ error: HyperwalletErrorType, _ retry: (() -> Void)?)
}

final class ListTransferMethodPresenter {
    private unowned let view: ListTransferMethodView
    var transferMethods: [HyperwalletTransferMethod]?
    private var selectedTransferMethod: HyperwalletTransferMethod?

    /// Initialize ListTransferMethodPresenter
    public init(view: ListTransferMethodView) {
        self.view = view
    }

    var numberOfCells: Int {
        return transferMethods?.count ?? 0
    }

    /// Get the list of all Activated transfer methods from core SDK
    func listTransferMethod() {
        view.showLoading()
        let pagination = HyperwalletTransferMethodPagination()
        pagination.limit = 100
        pagination.status = .activated
        Hyperwallet.shared.listTransferMethods(pagination: pagination, completion: listTransferMethodHandler())
    }

    func transferMethodExists(at index: Int) -> Bool {
        return getTransferMethod(at: index) != nil
    }

    func getTransferMethod(at index: Int) -> HyperwalletTransferMethod? {
        return transferMethods?[index]
    }

    func deactivateTransferMethod(at index: Int) {
        guard let transferMethod = getTransferMethod(at: index) else {
            return
        }
        deactivateTransferMethod(transferMethod)
    }

    /// Deactivate the selected Transfer Method
    private func deactivateTransferMethod(_ transferMethod: HyperwalletTransferMethod) {
        self.view.showProcessing()
        if let transferMethodType = transferMethod.getField(fieldName: .type)  as? String,
            let token = transferMethod.getField(fieldName: .token) as? String {
            selectedTransferMethod = transferMethod
            switch transferMethodType {
            case "BANK_ACCOUNT":
                deactivateBankAccount(token)
            case "BANK_CARD":
                deactivateBankCard(token)

            default:
                break
            }
        }
    }

    private func listTransferMethodHandler()
        -> (HyperwalletPageList<HyperwalletTransferMethod>?, HyperwalletErrorType?) -> Void {
            return { [weak self] (result, error) in
                guard let strongSelf = self else {
                    return
                }
                DispatchQueue.main.async {
                    strongSelf.view.hideLoading()
                    if let error = error {
                        strongSelf.view.showError(error, { strongSelf.listTransferMethod() })
                        return
                    }

                    strongSelf.transferMethods = result?.data
                    strongSelf.view.showTransferMethods()
                }
            }
    }

    private func deactivateBankAccount(_ token: String) {
        Hyperwallet.shared.deactivateBankAccount(transferMethodToken: token,
                                                 notes: "Deactivating the Bank Account",
                                                 completion: deactivateTransferMethodHandler())
    }

    private func deactivateBankCard(_ token: String) {
        Hyperwallet.shared.deactivateBankCard(transferMethodToken: token,
                                              notes: "Deactivating the Bank Card",
                                              completion: deactivateTransferMethodHandler())
    }

    private func deactivateTransferMethodHandler()
        -> (HyperwalletStatusTransition?, HyperwalletErrorType?) -> Void {
            return { [weak self] (result, error) in
                guard let strongSelf = self else {
                    return
                }
                DispatchQueue.main.async {
                    if let error = error {
                        let errorHandler = {
                            strongSelf.view.showError(error, {
                                strongSelf.deactivateTransferMethod(strongSelf.selectedTransferMethod!) })
                        }

                        strongSelf.view.dismissProcessing(handler: errorHandler)
                    } else if let statusTransition = result {
                        let processingHandler = {
                            () -> Void in strongSelf.listTransferMethod()
                            strongSelf.view.notifyTransferMethodDeactivated(statusTransition)
                        }
                        strongSelf.view.showConfirmation(handler: processingHandler)
                    }
                }
            }
    }

    func getCellConfiguration(for transferMethodIndex: Int) -> ListTransferMethodCellConfiguration? {
        if let transferMethod = getTransferMethod(at: transferMethodIndex),
            let country = transferMethod.getField(fieldName: .transferMethodCountry) as? String,
            let transferMethodType = transferMethod.getField(fieldName: .type) as? String,
            let lastFourDigitAccountNumber = getLastDigits(transferMethod, number: 4) {
            let transferMethodExpiryDate = String(format: "%@%@",
                                                  "transfer_method_list_item_description".localized(),
                                                  lastFourDigitAccountNumber)
            return ListTransferMethodCellConfiguration(
                transferMethodType: transferMethodType.lowercased().localized(),
                transferMethodCountry: country.localized(),
                transferMethodExpiryDate: transferMethodExpiryDate,
                transferMethodIconFont: HyperwalletIcon.of(transferMethodType).rawValue)
        }
        return nil
    }

    private func getLastDigits(_ transferMethod: HyperwalletTransferMethod, number: Int) -> String? {
        var accountId: String?
        switch transferMethod.getField(fieldName: .type) as? String {
        case "BANK_ACCOUNT", "WIRE_ACCOUNT":
            accountId = transferMethod.getField(fieldName: .bankAccountId) as? String
        case "BANK_CARD":
            accountId = transferMethod.getField(fieldName: .cardNumber) as? String

        default:
            break
        }
        return accountId?.suffix(startAt: number)
    }
}
