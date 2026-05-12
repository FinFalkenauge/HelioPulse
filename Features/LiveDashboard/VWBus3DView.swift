import SwiftUI

struct VWBus3DView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.02), Color.white.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.14, green: 0.31, blue: 0.65), Color(red: 0.09, green: 0.21, blue: 0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 170, height: 42)
                        .offset(y: 8)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                        .frame(width: 150, height: 30)
                        .offset(y: -2)

                    Rectangle()
                        .fill(Color(red: 0.99, green: 0.72, blue: 0.24))
                        .frame(width: 4, height: 48)
                        .offset(x: 28, y: 5)

                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.85))
                            .frame(width: 36, height: 13)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.85))
                            .frame(width: 44, height: 13)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(red: 0.72, green: 0.88, blue: 1.0).opacity(0.85))
                            .frame(width: 26, height: 13)
                    }
                    .offset(y: -6)
                }

                HStack(spacing: 95) {
                    wheel
                    wheel
                }
                .offset(y: -2)
            }
            .scaleEffect(0.98)

            Circle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 150, height: 10)
                .offset(y: 30)
                .blur(radius: 2.5)
        }
        .frame(height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var wheel: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.9))
                .frame(width: 22, height: 22)
            Circle()
                .fill(Color.gray.opacity(0.7))
                .frame(width: 9, height: 9)
        }
    }
}
