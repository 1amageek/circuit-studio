import Foundation

/// Diagnostic from design validation.
public struct Diagnostic: Sendable, Identifiable {
    public enum Severity: Sendable {
        case error
        case warning
        case info
    }

    public let id: UUID
    public let severity: Severity
    public let message: String
    public let componentID: UUID?

    public init(
        id: UUID = UUID(),
        severity: Severity,
        message: String,
        componentID: UUID? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.componentID = componentID
    }
}

/// Service for validating schematic documents.
public struct DesignService: Sendable {
    public let catalog: DeviceCatalog

    public init(catalog: DeviceCatalog = .standard()) {
        self.catalog = catalog
    }

    /// Validate a SchematicDocument, returning diagnostics.
    public func validate(_ document: SchematicDocument) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        if document.components.isEmpty {
            diagnostics.append(Diagnostic(
                severity: .warning,
                message: "Design has no components"
            ))
        }

        // Check for unconnected pins
        let connectedPins = Set(
            document.wires.compactMap { $0.startPin }.map { "\($0.componentID):\($0.portID)" }
            + document.wires.compactMap { $0.endPin }.map { "\($0.componentID):\($0.portID)" }
        )

        for component in document.components {
            guard let kind = catalog.device(for: component.deviceKindID) else {
                diagnostics.append(Diagnostic(
                    severity: .info,
                    message: "Unknown device type '\(component.deviceKindID)' for '\(component.name)'",
                    componentID: component.id
                ))
                continue
            }

            // Check floating pins
            for port in kind.portDefinitions {
                let key = "\(component.id):\(port.id)"
                if !connectedPins.contains(key) {
                    diagnostics.append(Diagnostic(
                        severity: .warning,
                        message: "Pin '\(port.displayName)' on '\(component.name)' is unconnected",
                        componentID: component.id
                    ))
                }
            }

            // Check required parameters
            for schema in kind.parameterSchema where schema.isRequired {
                guard let value = component.parameters[schema.id] else {
                    diagnostics.append(Diagnostic(
                        severity: .error,
                        message: "\(kind.displayName) '\(component.name)' missing \(schema.displayName) value",
                        componentID: component.id
                    ))
                    continue
                }

                // Range validation
                if let range = schema.range, !range.contains(value) {
                    diagnostics.append(Diagnostic(
                        severity: .error,
                        message: "\(kind.displayName) '\(component.name)' has \(schema.displayName) value \(value) outside valid range \(range)",
                        componentID: component.id
                    ))
                }
            }
        }

        // Check for duplicate component names
        var namesSeen: [String: UUID] = [:]
        for component in document.components {
            if let existingID = namesSeen[component.name] {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    message: "Duplicate component name '\(component.name)'",
                    componentID: component.id
                ))
                diagnostics.append(Diagnostic(
                    severity: .error,
                    message: "Duplicate component name '\(component.name)'",
                    componentID: existingID
                ))
            } else {
                namesSeen[component.name] = component.id
            }
        }

        // Check for ground reference
        let hasGround = document.components.contains { $0.deviceKindID == "ground" }
        if !hasGround && !document.components.isEmpty {
            diagnostics.append(Diagnostic(
                severity: .warning,
                message: "Design has no ground reference. A ground node is required for simulation."
            ))
        }

        return diagnostics
    }
}
