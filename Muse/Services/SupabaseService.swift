import Foundation
import Supabase

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    private init() {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              urlString != "YOUR_SUPABASE_URL",
              let url = URL(string: urlString),
              url.host != nil,
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              anonKey != "YOUR_SUPABASE_ANON_KEY"
        else {
            client = nil
            return
        }

        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
