import Foundation
import SwiftUI

// 钱包管理：多钱包、多链混加，随时增删改。
// 用 App Group 存，供 App 和小组件读同一份列表。以前写的是注释说 App Group、
// 代码却用 UserDefaults.standard，这是实打实的 bug：小组件根本读不到。
// 现在走 SharedStore.defaults（App Group，建好前回落 standard 并做一次迁移），
// 钱包 key 不变，旧数据不丢。
final class WalletStore: ObservableObject {
    @Published var wallets: [WalletAccount] = [] {
        didSet { save() }
    }

    private let key = SharedStore.walletsKey

    init() {
        SharedStore.migrateWalletsIfNeeded()
        if let data = SharedStore.defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([WalletAccount].self, from: data) {
            wallets = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(wallets) {
            SharedStore.defaults.set(data, forKey: key)
        }
    }

    // 地址格式校验（使用时的问题：贴错链、贴了合约/交易哈希、重复添加，Worker 只会回 invalid，App 却先存了脏数据）。
    // EVM：0x + 40 位十六进制；Solana：Base58（不含 0/O/I/l），32–44 位。校验不过不入库，返回 false 供界面提示。
    static func isValidAddress(chain: Chain, address: String) -> Bool {
        let t = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if chain == .solana {
            let base58 = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            return (32...44).contains(t.count) && t.unicodeScalars.allSatisfy { base58.contains($0) }
        }
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }

    @discardableResult
    func add(chain: Chain, address: String, label: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAddress(chain: chain, address: trimmed) else { return false }
        // 去重：同链同地址不重复存（Solana 区分大小写，EVM 不区分）。
        let exists = wallets.contains {
            $0.chain == chain && (chain == .solana ? $0.address == trimmed : $0.address.lowercased() == trimmed.lowercased())
        }
        guard !exists else { return false }
        wallets.append(WalletAccount(chain: chain, address: trimmed, label: label.isEmpty ? chain.displayName : label))
        return true
    }

    func remove(at offsets: IndexSet) {
        wallets.remove(atOffsets: offsets)
    }

    func remove(_ wallet: WalletAccount) {
        wallets.removeAll { $0.id == wallet.id }
    }
}
