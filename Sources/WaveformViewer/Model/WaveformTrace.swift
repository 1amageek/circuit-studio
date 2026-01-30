import SwiftUI
import CoreSpiceWaveform

/// A single trace displayed in the waveform chart.
public struct WaveformTrace: Identifiable, Sendable {
    public let id: UUID
    public var variableName: String
    public var displayName: String
    public var color: Color
    public var isVisible: Bool
    public var yAxis: YAxisBinding

    public init(
        id: UUID = UUID(),
        variableName: String,
        displayName: String? = nil,
        color: Color = .blue,
        isVisible: Bool = true,
        yAxis: YAxisBinding = .left
    ) {
        self.id = id
        self.variableName = variableName
        self.displayName = displayName ?? variableName
        self.color = color
        self.isVisible = isVisible
        self.yAxis = yAxis
    }

    public enum YAxisBinding: Sendable {
        case left
        case right
    }
}
