//
//  PDFExport.swift
//  PanoCal
//
//  Created by Donald Edwards on 14/11/2026.
//

import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let exportRequested = Notification.Name("PanoCalExportRequested")
}

// A PDF the save dialog can write out.
struct PDFFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum PDFExport {
    // Paper size in points: A4 landscape. For US Letter, use 792 x 612.
    static let pageSize = CGSize(width: 842, height: 595)

    // Pages are laid out this much larger than the paper, then shrunk to fit, so text stays in proportion.
    static let layoutScale: CGFloat = 1.4

    static func makePDF(pages: [AnyView]) -> Data? {
        let layoutSize = CGSize(width: pageSize.width * layoutScale, height: pageSize.height * layoutScale)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for page in pages {
            let content = page
                .frame(width: layoutSize.width, height: layoutSize.height)
                .background(Color.white)
                .environment(\.colorScheme, .light)

            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(layoutSize)

            pdf.beginPDFPage(nil)
            pdf.saveGState()
            pdf.scaleBy(x: 1 / layoutScale, y: 1 / layoutScale)
            renderer.render { _, draw in
                draw(pdf)
            }
            pdf.restoreGState()
            pdf.endPDFPage()
        }

        pdf.closePDF()
        return data as Data
    }
}
