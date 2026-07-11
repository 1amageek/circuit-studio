import Database

enum ActivityMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ActivitySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
