import SwiftUI

/// Spacing scale (multiples of 4) used across KuyuUI views.
public enum KuyuSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

/// Corner radius scale.
public enum KuyuRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 8
    public static let large: CGFloat = 10
}

/// Typical content frame hints used by Detail panels.
public enum KuyuLayout {
    public static let sidebarMin: CGFloat = 220
    public static let sidebarIdeal: CGFloat = 256
    public static let sidebarMax: CGFloat = 320
    public static let inspectorMin: CGFloat = 240
    public static let inspectorIdeal: CGFloat = 280
    public static let inspectorMax: CGFloat = 360
    public static let realityMinWidth: CGFloat = 320
    public static let chartMinHeight: CGFloat = 140
    public static let logMinHeight: CGFloat = 120
    public static let bottomDrawerIdeal: CGFloat = 220
}
