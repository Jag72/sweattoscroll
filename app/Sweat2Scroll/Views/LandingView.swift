// Views/LandingView.swift
// Landing page → unified Sign in with Apple (mode is chosen after auth).

import SwiftUI

// MARK: - Landing Page
struct LandingView: View {
    @State private var showSignIn = false
    @State private var appeared = false
    #if DEBUG
    @State private var devUsernameField = ""
    @State private var devPasswordField = ""
    #endif

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            // Ambient blobs — same as DashboardView
            Circle()
                .fill(Color.electricOrange.opacity(0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: 140, y: -260)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Circle()
                .fill(Color.deepTeal.opacity(0.07))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: -160, y: 200)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                        .padding(.top, 64)
                        .padding(.bottom, 40)

                    pathSection
                        .padding(.bottom, 36)

                    featuresSection
                        .padding(.bottom, 40)

                    loginFooter
                        .padding(.bottom, 52)
                }
                .padding(.horizontal, 24)
            }
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInView()
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.15)) {
                appeared = true
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: Hero
    private var heroSection: some View {
        VStack(spacing: 22) {
            ZStack {
                // Soft warm aura behind the logo to lift it off the cream paper
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.electricOrange.opacity(0.22),
                                Color.electricOrange.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 130
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 14)
                    .opacity(appeared ? 1 : 0)

                Sweat2ScrollLogo(size: 96, animated: true)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
            }

            VStack(spacing: 14) {
                Sweat2ScrollWordmark(size: 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)

                VStack(spacing: 6) {
                    Text("Earn your scroll time.")
                        .font(.system(size: 28, weight: .black, design: .serif))
                        .italic()
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.center)
                    Text("Apps stay locked until your body earns the access.\nEvery. Single. Day.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
        }
    }

    // MARK: Role Path Cards
    private var pathSection: some View {
        VStack(spacing: 14) {
            Text("GET STARTED")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.5)
                .foregroundColor(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appeared ? 1 : 0)

            // User path
            PathCard(
                icon: "figure.run",
                role: "I Want to Earn My Screen Time",
                description: "Set a daily fitness goal. Social apps stay locked until you hit it.",
                accentColor: .electricOrange,
                delay: 0.1
            ) { showSignIn = true }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)

            // Partner path
            PathCard(
                icon: "person.2.fill",
                role: "I'm an Accountability Partner",
                description: "Help someone stay on track. You hold the override code and monitor their progress.",
                accentColor: .deepTeal,
                delay: 0.2
            ) { showSignIn = true }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
    }

    // MARK: Features
    private var featuresSection: some View {
        VStack(spacing: 14) {
            Text("HOW IT WORKS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.5)
                .foregroundColor(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                FeatureStep(number: 1, title: "Set Your Goal",
                            detail: "Calories or steps — pick what fits your lifestyle",
                            color: .electricOrange, isLast: false)
                FeatureStep(number: 2, title: "Pick Your Apps",
                            detail: "Choose up to 10 social apps to put behind the shield",
                            color: Color(hex: "#A855F7"), isLast: false)
                FeatureStep(number: 3, title: "Move Your Body",
                            detail: "Apple Watch + iPhone track everything automatically",
                            color: .deepTeal, isLast: false)
                FeatureStep(number: 4, title: "Apps Unlock",
                            detail: "Hit your goal → shield drops → scroll freely",
                            color: Color.emeraldGreen, isLast: true)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            )
        }
    }

    // MARK: Login Footer
    private var loginFooter: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(.subheadline)
                    .foregroundColor(.muted)
                Button("Sign In") { showSignIn = true }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.electricOrange)
            }
            #if DEBUG
            VStack(alignment: .leading, spacing: 8) {
                Text("Simulator credentials (PRD)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.muted)
                TextField("Username", text: $devUsernameField)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $devPasswordField)
                    .textFieldStyle(.roundedBorder)
                Button("Dev sign-in → Solo dashboard") {
                    guard AppSession.isDevCredentialMatch(username: devUsernameField, password: devPasswordField) else { return }
                    AuthManager.shared.devSignIn(as: .solo)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.deepTeal)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.ink.opacity(0.04)))
            #endif
        }
    }
}

// MARK: - Role Path Card
private struct PathCard: View {
    let icon: String
    let role: String
    let description: String
    let accentColor: Color
    var delay: Double = 0
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(accentColor)
                        .frame(width: 52, height: 52)
                        .shadow(color: accentColor.opacity(0.35), radius: 10, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(role)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.ink)
                        .multilineTextAlignment(.leading)
                    Text(description)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(accentColor.opacity(0.25), lineWidth: 1.5)
                    )
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 100, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.12)) { pressed = pressing }
        }, perform: {})
    }
}

// MARK: - Feature Step
private struct FeatureStep: View {
    let number: Int
    let title: String
    let detail: String
    let color: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                }
                if !isLast {
                    Rectangle()
                        .fill(color.opacity(0.15))
                        .frame(width: 2, height: 32)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.ink)
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

#Preview {
    LandingView()
}
