import SwiftUI

/// A layout container with a collapsible bottom panel backed by `VSplitView`.
///
/// When expanded, the main content and the footer panel are arranged in a
/// split view with a draggable divider. When collapsed, only the header bar
/// is visible below the main content.
///
///     CollapsibleSplitView(isExpanded: $showList) {
///         CanvasView()
///     } content: {
///         ScrollView { ... }
///     } header: {
///         Label("Items", systemImage: "list.bullet")
///     }
struct CollapsibleSplitView<Main: View, Content: View, Header: View>: View {
    @Binding var isExpanded: Bool
    var minMainHeight: CGFloat = 200
    var minSectionHeight: CGFloat = 120
    @ViewBuilder var main: Main
    @ViewBuilder var content: Content
    @ViewBuilder var header: Header

    var body: some View {
        if isExpanded {
            VSplitView(minTopHeight: minMainHeight, minBottomHeight: minSectionHeight) {
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footerSection
            }
        } else {
            VStack(spacing: 0) {
                main
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                headerBar
            }
        }
    }

    private var footerSection: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
    }

    private var headerBar: some View {
        ZStack {
            Rectangle().fill(.bar)
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 8) {
                    header

                    Spacer(minLength: 8)

                    panelVisibilityButton
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 40)
        .clipped()
    }

    private var panelVisibilityButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            Image(systemName: "rectangle.bottomthird.inset.filled")
                .symbolRenderingMode(.hierarchical)
                .font(.body)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isExpanded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
        .help(isExpanded ? "Hide Section" : "Show Section")
    }
}
