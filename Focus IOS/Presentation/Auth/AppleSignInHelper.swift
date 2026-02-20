//
//  AppleSignInHelper.swift
//  Focus IOS
//

import AuthenticationServices

class AppleSignInHelper: NSObject, ASAuthorizationControllerDelegate {
    private var currentNonce: String?
    private var continuation: CheckedContinuation<(idToken: String, nonce: String), Error>?

    func signIn() async throws -> (idToken: String, nonce: String) {
        let nonce = NonceHelper.randomNonceString()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = NonceHelper.sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = currentNonce else {
            continuation?.resume(throwing: NSError(
                domain: "AppleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to get Apple ID token."]
            ))
            return
        }
        continuation?.resume(returning: (idToken: idToken, nonce: nonce))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
    }
}
