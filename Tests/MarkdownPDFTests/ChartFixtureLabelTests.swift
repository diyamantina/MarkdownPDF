import Foundation
@testable import MarkdownPDF
import Testing

/// Every chart of the Markdown fixtures, rendered alone on a page of its own: all of its text lies inside the page and
/// inside the chart's frame. With the artifact directory set, each chart is also written as a PDF of its own
/// (`chart-fixtures/<fixture>-<number>.pdf`), so two builds of the renderer can be compared chart by chart, byte for
/// byte.
@Suite("The charts of the fixtures keep their text inside the page and the chart's frame")
struct ChartFixtureLabelTests {
    private struct FixtureChart {
        var name: String
        var markdown: String
    }

    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    /// The chart blocks of every Markdown file under the fixtures folder, in the order of the file names.
    private static var charts: [FixtureChart] {
        let files = (FileManager.default.enumerator(at: fixturesDirectory, includingPropertiesForKeys: nil)?.allObjects ?? [])
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "md" }
            .sorted { $0.path < $1.path }
        var charts: [FixtureChart] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            var block: [String]?
            var number = 0
            for line in text.components(separatedBy: "\n") {
                if block == nil, line.hasPrefix("```chart") {
                    block = [line]
                } else if let lines = block {
                    block = lines + [line]
                    if line.hasPrefix("```") {
                        number += 1
                        let name = "\(file.deletingPathExtension().lastPathComponent)-\(number)"
                        charts.append(FixtureChart(name: name, markdown: (lines + [line]).joined(separator: "\n") + "\n"))
                        block = nil
                    }
                }
            }
        }
        return charts
    }

    @Test("each chart's text lies inside the page and the frame")
    func insideFrame() throws {
        let options = PDFOptions()
        let frame = ChartTickLabelKey.frame(
            pageWidth: options.pageSize.width,
            marginLeft: options.margins.left,
            marginRight: options.margins.right,
        )
        let charts = Self.charts
        var runCount = 0
        for chart in charts {
            let pdf = try MarkdownPDFRenderer(options: options).render(markdown: chart.markdown)
            try PDFValidation.writeArtifact(pdf, name: "chart-fixtures/\(chart.name).pdf")
            for run in try PDFDocumentReader(data: pdf).pages.flatMap(\.runs) where !run.text.trimmingCharacters(in: .whitespaces).isEmpty {
                runCount += 1
                #expect(
                    run.x >= frame.lowerBound - 0.01 && run.x + run.width <= frame.upperBound + 0.01,
                    Comment(rawValue: "\(chart.name): '\(run.text)' at \(run.x)...\(run.x + run.width) leaves the frame \(frame)"),
                )
            }
        }
        print("ChartFixtureLabelTests: \(charts.count) charts, \(runCount) text runs")
        // Measured on 2026-11-24, printed by the line above: 22 charts, 246 text runs. The floors are the measured numbers,
        // so a broken search for the fixtures, or charts that print no text, cannot pass. A new fixture chart raises both.
        #expect(charts.count >= 22)
        #expect(runCount >= 246)
    }
}
