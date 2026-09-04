import Foundation

// Keeps a non-rendered palette grouping helper source-compatible with the compact 2.0 workspace.
func == (lhs: String, rhs: StudioComponentKind) -> Bool {
    lhs == rhs.category
}
