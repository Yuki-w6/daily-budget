import Foundation
import Testing
@testable import DailyBudgetCore

/// CloudKit には一意制約が無いため、同じキーのレコードが複数できうる。
/// その収束先を決める規則の確認（PRD §13）。
struct DuplicateResolutionTests {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    private func candidate(_ id: Int, _ offset: TimeInterval) -> DuplicateCandidate<Int> {
        DuplicateCandidate(id: id, updatedAt: base.addingTimeInterval(offset))
    }

    @Test("最終更新が新しいレコードを残す")
    func keepsMostRecentlyUpdated() {
        let candidates = [candidate(1, 0), candidate(2, 60), candidate(3, 30)]
        #expect(DuplicateResolution.survivor(among: candidates) == 2)
        #expect(DuplicateResolution.losers(among: candidates).sorted() == [1, 3])
    }

    @Test("更新時刻が同じならidの小さいほうを残す")
    func breaksTiesByIdSoEveryDeviceAgrees() {
        let candidates = [candidate(3, 0), candidate(1, 0), candidate(2, 0)]
        #expect(DuplicateResolution.survivor(among: candidates) == 1)
        // 並び順が違っても同じ結果になる。端末ごとに取得順が違っても収束する。
        #expect(DuplicateResolution.survivor(among: candidates.reversed()) == 1)
        #expect(DuplicateResolution.losers(among: candidates).sorted() == [2, 3])
    }

    @Test("候補が1件なら残して削除対象は無い")
    func singleCandidateSurvives() {
        #expect(DuplicateResolution.survivor(among: [candidate(7, 0)]) == 7)
        #expect(DuplicateResolution.losers(among: [candidate(7, 0)]).isEmpty)
    }

    @Test("候補が無ければ nil")
    func emptyCandidates() {
        let empty: [DuplicateCandidate<Int>] = []
        #expect(DuplicateResolution.survivor(among: empty) == nil)
        #expect(DuplicateResolution.losers(among: empty).isEmpty)
    }

    @Test("UUID でも同じ規則で収束する")
    func worksWithUUIDs() {
        let older = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        let newer = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let candidates = [
            DuplicateCandidate(id: older, updatedAt: base),
            DuplicateCandidate(id: newer, updatedAt: base.addingTimeInterval(1))
        ]
        #expect(DuplicateResolution.survivor(among: candidates) == newer)
    }
}
