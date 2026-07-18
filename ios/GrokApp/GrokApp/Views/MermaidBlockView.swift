// Copyright (c) 2026 Pedro Shakour
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// Upstream mermaid affordance (`mermaid_content.rs`): `◇ mermaid` + Open Image + Copy Source.
/// PNG comes from companion `x.ai/companion/mermaid_render` (Mac `xai-grok-pager __mermaid-render`).
struct MermaidBlockView: View {
    let source: String
    let theme: GrokTheme
    var onOpenImage: ((String) async -> Data?)?

    @State private var image: UIImage?
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("◇ mermaid")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.gray)
                if onOpenImage != nil {
                    Button("[Open Image]") {
                        Task { await openImage() }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.accentSystem)
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                Button("[Copy Source]") {
                    UIPasteboard.general.string = source
                }
                .font(.caption.monospaced())
                .foregroundStyle(theme.accentSystem)
                .buttonStyle(.plain)
            }
            if busy {
                Text("Rendering…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.accentError)
            }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(theme.bgHighlight.opacity(0.5))
            } else {
                Text(source)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(theme.bgHighlight.opacity(0.5))
            }
        }
    }

    private func openImage() async {
        guard let onOpenImage else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        if let data = await onOpenImage(source), let ui = UIImage(data: data) {
            image = ui
        } else {
            errorText = "Render failed — need companion + xai-grok-pager"
        }
    }
}
