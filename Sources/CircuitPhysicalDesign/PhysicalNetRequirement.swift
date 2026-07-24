struct PhysicalNetRequirement: Sendable, Hashable {
    let name: String
    let requiresExternalPort: Bool
}
