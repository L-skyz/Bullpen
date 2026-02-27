import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(auth.nickname.isEmpty ? "회원" : auth.nickname)
                                .font(.headline)
                            Text("mlbpark.donga.com")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button(role: .destructive) {
                        auth.logout()
                    } label: {
                        Text("로그아웃").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("내 정보")
        }
    }
}
