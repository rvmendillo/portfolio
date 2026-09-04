import Foundation

extension LocalVibeModel {
    /// Backward-compatible name used by the existing Studio panels.
    /// In ReyForge 2.2 the model is installed on demand rather than bundled.
    var isBundled: Bool { isInstalled }
}
