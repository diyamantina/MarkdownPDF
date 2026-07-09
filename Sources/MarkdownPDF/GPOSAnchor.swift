import Foundation

/// An OpenType GPOS anchor point (spec: OpenType `gpos`, Anchor tables), in font
/// design units. Formats 1, 2, and 3 all carry an (x, y) coordinate; format 2 adds a
/// contour point and format 3 adds device tables, refinements this reader does not
/// apply (the plain coordinate is the placement signal used to attach marks).
struct GPOSAnchor: Equatable {
    var x: Int16
    var y: Int16
}
