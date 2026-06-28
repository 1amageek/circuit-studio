struct IndexedUnionFind: Sendable {
    private var parents: [Int]

    init(count: Int) {
        self.parents = Array(0..<count)
    }

    mutating func find(_ value: Int) -> Int {
        let parent = parents[value]
        if parent == value {
            return value
        }
        let root = find(parent)
        parents[value] = root
        return root
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let leftRoot = find(lhs)
        let rightRoot = find(rhs)
        if leftRoot != rightRoot {
            parents[rightRoot] = leftRoot
        }
    }
}
