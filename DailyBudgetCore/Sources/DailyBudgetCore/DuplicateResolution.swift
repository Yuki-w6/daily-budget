import Foundation

/// 同じキーを持つレコードの候補。
public struct DuplicateCandidate<ID: Hashable & Comparable>: Hashable, Sendable
where ID: Sendable {
    public let id: ID
    public let updatedAt: Date

    public init(id: ID, updatedAt: Date) {
        self.id = id
        self.updatedAt = updatedAt
    }
}

/// 同じキーのレコードが複数できたとき、どれを残すかを決める。
///
/// 端末内のデータベースでは一意制約で重複を防げるが、CloudKit は一意制約を
/// 持てない。2台が同時に同じ月を確定すれば、同じ `yearMonth` のレコードが
/// 2件できる。その収束先をここで決める（PRD §13 の競合解決）。
public enum DuplicateResolution {
    /// 残すレコードを選ぶ。候補が無ければ `nil`。
    ///
    /// 最終更新が新しいものを残す。最後に操作した端末の内容が勝つので、
    /// ユーザーから見て直前の操作が反映される。
    /// 更新時刻が同じ場合は `id` の小さいほうを残す。どの端末で判定しても
    /// 同じ結果になり、収束するまで取り合いにならないようにするため。
    public static func survivor<ID>(among candidates: [DuplicateCandidate<ID>]) -> ID? {
        candidates.max { lhs, rhs in
            lhs.updatedAt == rhs.updatedAt
                ? lhs.id > rhs.id
                : lhs.updatedAt < rhs.updatedAt
        }?.id
    }

    /// 残すもの以外の `id` を返す。削除対象の列挙に使う。
    public static func losers<ID>(among candidates: [DuplicateCandidate<ID>]) -> [ID] {
        guard let survivor = survivor(among: candidates) else { return [] }
        return candidates.map(\.id).filter { $0 != survivor }
    }
}
