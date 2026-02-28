import SwiftUI

// MARK: - BlockType

enum BlockType {
    case keyword, nickname, maemuri

    var navTitle: String {
        switch self {
        case .keyword:  return "키워드 차단"
        case .nickname: return "닉네임 차단"
        case .maemuri:  return "말머리 차단"
        }
    }
    var placeholder: String {
        switch self {
        case .keyword:  return "차단할 키워드 입력"
        case .nickname: return "차단할 닉네임 입력"
        case .maemuri:  return "차단할 말머리 입력 (예: 공지, 질문)"
        }
    }
    var emptyMessage: String {
        switch self {
        case .keyword:  return "차단된 키워드가 없습니다"
        case .nickname: return "차단된 닉네임이 없습니다"
        case .maemuri:  return "차단된 말머리가 없습니다"
        }
    }
    var hint: String {
        switch self {
        case .keyword:  return "해당 단어가 제목에 포함된 게시글을 숨깁니다"
        case .nickname: return "해당 닉네임의 게시글을 숨깁니다"
        case .maemuri:  return "해당 말머리가 붙은 게시글을 숨깁니다 (정확히 일치)"
        }
    }
    var icon: String {
        switch self {
        case .keyword:  return "text.badge.xmark"
        case .nickname: return "person.slash"
        case .maemuri:  return "tag.slash"
        }
    }
}

// MARK: - View

struct BlockSettingsView: View {
    let type: BlockType

    @EnvironmentObject private var filter: BlockFilter
    @State private var newText = ""
    @FocusState private var inputFocused: Bool

    private var items: [String] {
        switch type {
        case .keyword:  return filter.blockedKeywords
        case .nickname: return filter.blockedNicknames
        case .maemuri:  return filter.blockedMaemuri
        }
    }

    var body: some View {
        List {
            // 입력 섹션
            Section {
                HStack(spacing: 8) {
                    TextField(type.placeholder, text: $newText)
                        .focused($inputFocused)
                        .onSubmit { addItem() }
                        .submitLabel(.done)
                    Button(action: addItem) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(newText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .blue)
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text(type.hint).font(.caption)
            }

            // 차단 목록
            Section {
                if items.isEmpty {
                    Text(type.emptyMessage)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(.red)
                                .font(.subheadline)
                            Text(item)
                        }
                    }
                    .onDelete { offsets in
                        switch type {
                        case .keyword:  filter.removeKeyword(at: offsets)
                        case .nickname: filter.removeNickname(at: offsets)
                        case .maemuri:  filter.removeMaemuri(at: offsets)
                        }
                    }
                }
            } header: {
                Text("차단 목록 (\(items.count))")
            }
        }
        .navigationTitle(type.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func addItem() {
        let text = newText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        switch type {
        case .keyword:  filter.addKeyword(text)
        case .nickname: filter.addNickname(text)
        case .maemuri:  filter.addMaemuri(text)
        }
        newText = ""
        inputFocused = false
    }
}
