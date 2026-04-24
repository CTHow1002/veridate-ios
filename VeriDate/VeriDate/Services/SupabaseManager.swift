import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://kgywzfcrtezocjonkjrf.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtneXd6ZmNydGV6b2Nqb25ranJmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMTA4NDQsImV4cCI6MjA5MjU4Njg0NH0.XBCPHT9pIwzaICBq1B3AChI5UQJIohw1a_FrJts89hs"
        )
    }
}
