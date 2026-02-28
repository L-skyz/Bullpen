import SwiftUI

// MARK: - BlockType

enum BlockType {
    case keyword, nickname

    var navTitle: String  { self == .keyword ? "키워드 차단" : "닉네임 차단" }
    var placeholder: String { self == .keyword ? "차단할 키워드 입력" : "차단할 닉네임 입력" }
    var emptyMessage: String { self == .keyword ? "차단된 키워드가 없습니다" : "차단된 닉네임이 없습니다" }
    var hint: String {
        self == .keyword
            ? "해당 단어가 제목에 포함된 게시글을 숨깁니다"
            : "해당 닉네임의 게시글을 숨깁니다"
    }
}

// MARK: - View

struct BlockSettingsView: View {
    let type: BlockType

    @EnvironmentObject private var filter: BlockFilter
    @State private var newText = ""
    @FocusState private var inputFocused: Bool

    private var items: [String] {
        type == .keyword ? filter.blockedKeywords : filter.blockedNicknames
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
                            Image(systemName: type == .keyword ? "text.badge.xmark" : "person.slash")
                                .foregroundColor(.red)
                                .font(.subheadline)
                            Text(item)
                        }
                    }
                    .onDelete { offsets in
                        if type == .keyword { filter.removeKeyword(at: offsets) }
                        else               { filter.removeNickname(at: offsets) }
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
        if type == .keyword { filter.addKeyword(text) }
        else               { filter.addNickname(text) }
        newText = ""
        inputFocused = false
    }
}
