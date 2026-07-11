import ArtifactNativeRenderer
import ArtifactView
import CircuitArtifactRenderer
import SwiftUI

struct CircuitStudioArtifactRendererRegistry: ViewModifier {
    func body(content: Content) -> some View {
        content
            .artifactRenderer(MarkdownRenderer())
            .artifactRenderer(CodeRenderer())
            .artifactRenderer(JSONRenderer())
            .artifactRenderer(CSVRenderer())
            .artifactRenderer(SVGRenderer())
            .artifactRenderer(PDFRenderer())
            .artifactRenderer(PNGRenderer())
            .artifactRenderer(JPEGRenderer())
            .artifactRenderer(WebPRenderer())
            .artifactRenderer(GIFRenderer())
            .artifactRenderer(TIFFRenderer())
            .artifactRenderer(HEICRenderer())
            .artifactRenderer(BMPRenderer())
            .artifactRenderer(GeoJSONMapKitRenderer())
            .artifactRenderer(GLTFSceneKitRenderer())
            .artifactRenderer(USDZModel3DRenderer())
            .artifactRenderer(MermaidRenderer())
            .artifactRenderer(TurtleRenderer())
            .artifactRenderer(TriGRenderer())
            .artifactRenderer(NQuadsRenderer())
            .artifactRenderer(RDFXMLRenderer())
            .artifactRenderer(JSONLDRenderer())
            .artifactRenderer(WaveformCSVRenderer())
            .artifactRenderer(WaveformRAWRenderer())
    }
}

extension View {
    func circuitStudioArtifactRenderers() -> some View {
        modifier(CircuitStudioArtifactRendererRegistry())
    }
}
