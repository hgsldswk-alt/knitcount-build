import SwiftUI

enum Design {
    static let background = Color(red: 245/255, green: 241/255, blue: 234/255)
    static let card = Color(red: 1, green: 253/255, blue: 249/255)
    static let ink = Color(red: 42/255, green: 38/255, blue: 34/255)
    static let secondary = Color(red: 110/255, green: 101/255, blue: 92/255)
    static let muted = Color(red: 163/255, green: 154/255, blue: 143/255)
    static let line = Color(red: 232/255, green: 225/255, blue: 214/255)
    static let accent = Color(red: 181/255, green: 82/255, blue: 59/255)
}
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View { content.padding(18).background(Design.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Design.line, lineWidth: 0.5)) }
}
extension View { func knitCard() -> some View { modifier(CardModifier()) } }

struct UndoToast: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let toast = model.toast {
            HStack { Text(toast).font(.subheadline); Spacer(); Button(L.t("撤销")) { model.undoToast() }.bold().accessibilityIdentifier("globalUndo") }
                .padding(16).background(Design.ink, in: Capsule()).foregroundStyle(.white).padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}

struct ProjectThumb: View {
    var project: Project
    var store: Store?
    var body: some View {
        Group {
            if let name = project.coverFilename ?? project.photos.last ?? project.part.patternPages.first?.filename,
               let path = try? store?.file(name), let image = UIImage(contentsOfFile: path.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else { Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(Design.accent).frame(maxWidth: .infinity, maxHeight: .infinity).background(Design.line) }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: 14)).contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
