@testable import MarkdownPDF
import Testing

@Suite("Chart block")
struct ChartBlockTests {
    @Test("Parses Mermaid pie charts")
    func parsesMermaidPieCharts() {
        let result = ChartBlock.parseMermaidPie("""
        pie title Browser Share
            "Desktop" : 62
            "Mobile" : 31
            "Tablet" : 7
        """)

        guard case let .chart(chart) = result else {
            Issue.record("Expected supported Mermaid pie chart")
            return
        }

        #expect(chart.kind == .pie)
        #expect(chart.title == "Browser Share")
        #expect(chart.categories == ["Desktop", "Mobile", "Tablet"])
        #expect(chart.series.first?.points.map(\.y) == [62, 31, 7])
    }

    @Test("Parses native bar and line chart value series")
    func parsesNativeBarAndLineChartValueSeries() {
        let bar = ChartBlock.parseChartFence("""
        type: bar
        title: Quarterly Revenue
        categories: Q1, Q2, Q3
        y-label: USD
        series: Actual = 3, 5, 4
        series: Forecast = 4, 6, 5
        """)

        guard case let .chart(chart) = bar else {
            Issue.record("Expected supported bar chart")
            return
        }

        #expect(chart.kind == .bar)
        #expect(chart.title == "Quarterly Revenue")
        #expect(chart.yLabel == "USD")
        #expect(chart.categories == ["Q1", "Q2", "Q3"])
        #expect(chart.series.map(\.name) == ["Actual", "Forecast"])
        #expect(chart.series[1].points.map(\.y) == [4, 6, 5])

        let line = ChartBlock.parseChartFence("""
        type: line
        x: 2024, 2025, 2026
        series: Users = 2.5, 4.0, 5.5
        """)

        guard case let .chart(lineChart) = line else {
            Issue.record("Expected supported line chart")
            return
        }

        #expect(lineChart.kind == .line)
        #expect(lineChart.categories.isEmpty)
        #expect(lineChart.series[0].points.map(\.x) == [2024, 2025, 2026])
    }

    @Test("Parses scatter chart points and rejects dense inputs")
    func parsesScatterChartPointsAndRejectsDenseInputs() {
        let scatter = ChartBlock.parseChartFence("""
        type: scatter
        x-label: effort
        y-label: impact
        series: Trials = (1, 2), (2, 4), (4, 7)
        """)

        guard case let .chart(chart) = scatter else {
            Issue.record("Expected supported scatter chart")
            return
        }

        #expect(chart.kind == .scatter)
        #expect(chart.xLabel == "effort")
        #expect(chart.series[0].points.map(\.x) == [1, 2, 4])
        #expect(chart.series[0].points.map(\.y) == [2, 4, 7])

        let dense = ChartBlock.parseChartFence("""
        type: bar
        categories: A, B, C
        series: One = 1, 2
        """)

        guard case let .unsupported(reason) = dense else {
            Issue.record("Expected unsupported mismatched chart")
            return
        }
        #expect(reason.contains("category count must match"))

        let ignoredAxis = ChartBlock.parseChartFence("""
        type: scatter
        categories: A, B
        series: Trials = (1, 2), (2, 4)
        """)

        guard case let .unsupported(axisReason) = ignoredAxis else {
            Issue.record("Expected unsupported scatter axis fields")
            return
        }
        #expect(axisReason.contains("point pairs"))
    }
}
