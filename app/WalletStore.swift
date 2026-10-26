import Foundation
import SwiftUI

// 钱包管理：多钱包、多链混加，随时增删改。
// 用 App Group 存，供 App 和小组件读同一份列表。
final class WalletStore: ObservableObject {
    @Published var wallets: [WalletAccount] = [] {
        didSet { save() }
    }

    private let key = "tugou.wallets.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WalletAccount].self, from: data) {
            wallets = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(wallets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func add(chain: Chain, address: String, label: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        wallets.append(WalletAccount(chain: chain, address: trimmed, label: label.isEmpty ? chain.displayName : label))
    }

    func remove(at offsets: IndexSet) {
        wallets.remove(atOffsets: offsets)
    }

    func remove(_ wallet: WalletAccount) {
        wallets.removeAll { $0.id == wallet.id }
    }
}
