struct PDFTaggedContent {
    struct Element: Equatable {
        var id: Int
        var role: Role
        var parentID: Int?
        var kids: [Kid]
        var attributes: Attributes
    }

    struct Mark: Equatable {
        var pageIndex: Int
        var mcid: Int
        var elementID: Int
    }

    struct Attributes: Equatable {
        var alternateDescription: String?
        var tableHeaderScope: TableHeaderScope?
        var listNumbering: ListNumbering?

        init(
            alternateDescription: String? = nil,
            tableHeaderScope: TableHeaderScope? = nil,
            listNumbering: ListNumbering? = nil,
        ) {
            self.alternateDescription = alternateDescription
            self.tableHeaderScope = tableHeaderScope
            self.listNumbering = listNumbering
        }

        var pdfEntries: [PDFSyntax.Dictionary.Entry] {
            var entries: [PDFSyntax.Dictionary.Entry] = []
            if let alternateDescription {
                entries.append(.init("Alt", .pdfString(alternateDescription)))
            }
            if let tableHeaderScope {
                entries.append(
                    .init(
                        "A",
                        .pdfDictionary([
                            .init("O", .pdfName("Table")),
                            .init("Scope", .pdfName(tableHeaderScope.rawValue)),
                        ]),
                    ),
                )
            }
            if let listNumbering {
                entries.append(
                    .init(
                        "A",
                        .pdfDictionary([
                            .init("O", .pdfName("List")),
                            .init("ListNumbering", .pdfName(listNumbering.rawValue)),
                        ]),
                    ),
                )
            }
            return entries
        }
    }

    enum Kid: Equatable {
        case element(Int)
        case mark(Mark)
    }

    enum Role: String, Equatable {
        case document = "Document"
        case paragraph = "P"
        case heading1 = "H1"
        case heading2 = "H2"
        case heading3 = "H3"
        case heading4 = "H4"
        case heading5 = "H5"
        case heading6 = "H6"
        case blockQuote = "BlockQuote"
        case list = "L"
        case listItem = "LI"
        case listLabel = "Lbl"
        case listBody = "LBody"
        case table = "Table"
        case tableRow = "TR"
        case tableHeader = "TH"
        case tableCell = "TD"
        case figure = "Figure"
        case code = "Code"
        case tableOfContents = "TOC"
        case tableOfContentsItem = "TOCI"

        static func heading(level: Int) -> Role {
            switch level {
            case 1:
                .heading1
            case 2:
                .heading2
            case 3:
                .heading3
            case 4:
                .heading4
            case 5:
                .heading5
            default:
                .heading6
            }
        }
    }

    enum TableHeaderScope: String, Equatable {
        case column = "Column"
        case row = "Row"
    }

    enum ListNumbering: String, Equatable {
        case ordered = "Decimal"
        case unordered = "Unordered"
    }

    var language: String
    var elements: [Element]
    var marksByPage: [Int: [Mark]]

    var documentElementID: Int {
        0
    }

    func structParents(for pageIndex: Int) -> Int? {
        guard marksByPage[pageIndex]?.isEmpty == false else {
            return nil
        }
        return pageIndex
    }

    var usesCodeRole: Bool {
        elements.contains { $0.role == .code }
    }
}
