import Foundation
import LocalAuthentication

enum UnlockResult {
    case success
    case failure(String)
}

final class UnlockHandler {
    func authenticate(requireAuth: Bool, completion: @escaping (UnlockResult) -> Void) {
        guard requireAuth else {
            completion(.success)
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            let reason = authError?.localizedDescription ?? "Authentication unavailable"
            completion(.failure("Cannot authenticate: \(reason)"))
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock BlurGuard screen protection"
        ) { success, error in
            if success {
                completion(.success)
            } else {
                let reason = error?.localizedDescription ?? "Authentication failed"
                completion(.failure(reason))
            }
        }
    }
}
