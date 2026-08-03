//
//  LoginView.swift
//  DemoApp
//
//  Every accessibilityIdentifier here is chosen to exactly match what
//  UITests/LoginTests.swift and UITests/Helpers/LoginHelper.swift expect.
//  Valid demo credentials: username "testuser", password "password123".
//
//  Author: UnicornVault
//

import SwiftUI

struct LoginView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoggedIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Sign In")
                    .font(.title)
                    .padding(.bottom, 8)

                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("usernameField")

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("passwordField")

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }

                Button("Log In") {
                    attemptLogin()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("loginButton")

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: $isLoggedIn) {
                ItemListView()
            }
        }
    }

    private func attemptLogin() {
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter credentials"
            return
        }

        if username == "testuser" && password == "password123" {
            errorMessage = nil
            isLoggedIn = true
        } else {
            errorMessage = "Invalid credentials"
        }
    }
}

#Preview {
    LoginView()
}

