import SwiftUI

struct ClusterLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
        } icon: {
            ZStack(alignment: .bottomTrailing) {
                configuration.icon
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .shadow(radius: 0.25)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .frame(width: 27, height: 27)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: 0x3363FF), Color(hex: 0x0030CC)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
            }
        }
    }
}
