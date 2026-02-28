import Foundation

/// 키워드/닉네임 차단 필터 (로컬 UserDefaults 저장)
@MainActor
class BlockFilter: ObservableObject {
    static let shared = BlockFilter()

    @Published var blockedKeywords: [String] = []
    @Published var blockedNicknames: [String] = []

    private init() { load() }

    // MARK: - 키워드

    func addKeyword(_ kw: String) {
        let kw = kw.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty, !blockedKeywords.contains(kw) else { return }
        blockedKeywords.append(kw)
        save()
    }

    func removeKeyword(at offsets: IndexSet) {
        blockedKeywords.remove(atOffsets: offsets)
        save()
    }

    // MARK: - 닉네임

    func addNickname(_ nick: String) {
        let nick = nick.trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty, !blockedNicknames.contains(nick) else { return }
        blockedNicknames.append(nick)
        save()
    }

    func removeNickname(at offsets: IndexSet) {
        blockedNicknames.remove(atOffsets: offsets)
        save()
    }

    // MARK: - 판별

    func isBlocked(_ post: Post) -> Bool {
        if blockedNicknames.contains(post.author) { return true }
        for kw in blockedKeywords where !kw.isEmpty {
            if post.title.localizedCaseInsensitiveContains(kw) { return true }
        }
        return false
    }

    // MARK: - 저장/로드

    private func save() {
        UserDefaults.standard.set(blockedKeywords, forKey: "blockedKeywords")
        UserDefaults.standard.set(blockedNicknames, forKey: "blockedNicknames")
    }

    private func load() {
        blockedKeywords  = UserDefaults.standard.stringArray(forKey: "blockedKeywords")  ?? []
        blockedNicknames = UserDefaults.standard.stringArray(forKey: "blockedNicknames") ?? []
    }
}
