import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthService
    @State private var id = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("아이디", text: $id)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("비밀번호", text: $password)
                    .textContentType(.password)
            }

            if let err = errorMessage {
                Section {
                    Text(err).foregroundColor(.red).font(.caption)
                }
            }

            Section {
                Button {
                    Task { await login() }
                } label: {
                    if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text("로그인")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(id.isEmpty || password.isEmpty || isLoading)
            }
        }
        .navigationTitle("로그인")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func login() async {
        isLoading = true; errorMessage = nil
        do {
            try await auth.login(id: id, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
