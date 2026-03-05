import SwiftUI

/// The initial screen with a large green-ringed "Start" button.
struct StartView: View {
    let onStart: () -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.7

            VStack {
                Spacer()
                Button(action: onStart) {
                    ZStack {
                        Circle()
                            .stroke(Color.green, lineWidth: 8)
                            .frame(width: size, height: size)

                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: size - 16, height: size - 16)

                        Text("Start")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
    }
}

#Preview {
    StartView(onStart: {})
}
