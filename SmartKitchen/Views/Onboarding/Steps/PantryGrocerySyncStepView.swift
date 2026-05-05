import SwiftUI

/// Phase 1 — Step 7. Tela dividida Despensa | Mercado, com itens deslizando
/// nos dois sentidos. Reforça que despensa e lista do mercado estão sempre
/// em sincronia.
struct PantryGrocerySyncStepView: View {
    let onContinue: () -> Void

    @State private var pantryItems: [SyncItemMock] = []
    @State private var groceryItems: [SyncItemMock] = []
    @State private var movingItem: MovingItem? = nil
    @State private var showBadge: Bool = false
    @State private var showHero = false
    @State private var showHeader = false
    @State private var showButton = false
    @State private var entranceTask: Task<Void, Never>? = nil
    @State private var loopTask: Task<Void, Never>? = nil

    private let initialPantry: [SyncItemMock] = [
        .init(id: "milk",   name: String(localized: "Leite"),  icon: "🥛", color: Color(red: 0.55, green: 0.78, blue: 0.96), badge: nil),
        .init(id: "rice",   name: String(localized: "Arroz"),  icon: "🍚", color: Color(red: 0.96, green: 0.85, blue: 0.55), badge: String(localized: "Validade 30 dias")),
        .init(id: "tomato", name: String(localized: "Tomate"), icon: "🍅", color: Color(red: 0.96, green: 0.55, blue: 0.55), badge: nil),
    ]

    private let initialGrocery: [SyncItemMock] = [
        .init(id: "bread",  name: String(localized: "Pão"),    icon: "🍞", color: Color(red: 0.96, green: 0.78, blue: 0.55), badge: nil),
        .init(id: "eggs",   name: String(localized: "Ovos"),   icon: "🥚", color: Color(red: 0.98, green: 0.92, blue: 0.62), badge: nil),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            stage
                .padding(.horizontal, 18)
                .frame(height: 360)
                .opacity(showHero ? 1 : 0)
                .scaleEffect(showHero ? 1 : 0.94)
                .animation(.spring(response: 0.85, dampingFraction: 0.84), value: showHero)

            VStack(spacing: 0) {
            VStack(spacing: 12) {
                OnboardingFeatureChip(
                    icon: "arrow.left.arrow.right",
                    title: String(localized: "Despensa & Mercado"),
                    tint: Color(red: 0.98, green: 0.72, blue: 0.34)
                )
                .opacity(showHeader ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)

                OnboardingHeader(
                    title: String(localized: "Despensa e mercado, sempre em sincronia"),
                    subtitle: String(localized: "Acabou? Vai pro mercado. Comprou? Volta pra despensa.")
                )
                .opacity(showHeader ? 1 : 0)
                .offset(y: showHeader ? 0 : 14)
                .animation(.spring(response: 0.7, dampingFraction: 0.86), value: showHeader)
            }

                Spacer(minLength: 14)

                OnboardingPrimaryButton(
                    title: String(localized: "Continuar"),
                    action: onContinue
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 18)
                .animation(.spring(response: 0.74, dampingFraction: 0.86), value: showButton)
            }
        }
        .onAppear { beginEntrance() }
        .onDisappear {
            entranceTask?.cancel(); entranceTask = nil
            loopTask?.cancel(); loopTask = nil
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(neutralSurfaceColor)
                .shadow(color: .black.opacity(0.05), radius: 16, y: 8)

            GeometryReader { proxy in
                let halfWidth = (proxy.size.width - 16) / 2

                ZStack {
                    // Two columns
                    HStack(spacing: 16) {
                        column(
                            title: String(localized: "Despensa"),
                            icon: "cabinet.fill",
                            tint: Color(red: 0.42, green: 0.78, blue: 0.55),
                            items: pantryItems,
                            width: halfWidth
                        )
                        column(
                            title: String(localized: "Mercado"),
                            icon: "cart.fill",
                            tint: Color(red: 0.98, green: 0.72, blue: 0.34),
                            items: groceryItems,
                            width: halfWidth
                        )
                    }
                    .padding(14)

                    // Sync arrows in middle
                    syncArrows
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                    // Moving item overlay
                    if let moving = movingItem {
                        MovingChip(item: moving.item)
                            .position(
                                x: moving.position == .start ? moving.startX : moving.endX,
                                y: proxy.size.height / 2
                            )
                            .animation(.spring(response: 0.7, dampingFraction: 0.8), value: moving.position)
                    }

                    // Bottom badge
                    if showBadge {
                        VStack {
                            Spacer()
                            syncBadge
                                .padding(.bottom, 14)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
        }
    }

    private func column(title: String, icon: String, tint: Color, items: [SyncItemMock], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(tint.opacity(0.85)).frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(items) { item in
                    SyncItemChip(item: item)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale).combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            Spacer()
        }
        .frame(width: width, alignment: .leading)
    }

    private var syncArrows: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(Circle().fill(Color.primary.opacity(0.06)))
    }

    private var syncBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
            Text(String(localized: "Sempre em sincronia"))
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.78, blue: 0.55), Color(red: 0.98, green: 0.72, blue: 0.34)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
        )
    }

    // MARK: - Loop

    private func beginEntrance() {
        entranceTask?.cancel()
        showHero = false; showHeader = false; showButton = false
        pantryItems = initialPantry
        groceryItems = initialGrocery
        movingItem = nil
        showBadge = false

        entranceTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 0.35)) { showHero = true }
            await wait(150)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { showHeader = true }
            await wait(150)
            withAnimation(.spring(response: 0.74, dampingFraction: 0.86)) { showButton = true }
            await wait(300)
            await runLoop()
        }
    }

    @MainActor
    private func runLoop() async {
        // Stage proxy: we'll use approximate positions instead of geometry reader values.
        // The MovingChip uses startX/endX values that match the approximate column centers.
        let leftCenter: CGFloat = 70
        let rightCenter: CGFloat = 250

        while !Task.isCancelled {
            // Reset
            withAnimation(.easeOut(duration: 0.25)) {
                pantryItems = initialPantry
                groceryItems = initialGrocery
                movingItem = nil
                showBadge = false
            }
            await wait(700)

            // 1) Pantry → Grocery: Leite acabou
            HapticManager.impact(style: .light)
            let milk = initialPantry[0]
            withAnimation(.easeInOut(duration: 0.3)) {
                pantryItems.removeAll { $0.id == milk.id }
            }
            movingItem = MovingItem(item: milk, startX: leftCenter, endX: rightCenter, position: .start)
            await wait(80)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                movingItem?.position = .end
            }
            await wait(700)
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                groceryItems.insert(milk, at: 0)
                movingItem = nil
            }
            await wait(900)

            // 2) Grocery → Pantry: Pão comprado, com validade
            HapticManager.impact(style: .light)
            var bread = initialGrocery[0]
            bread = SyncItemMock(id: bread.id, name: bread.name, icon: bread.icon, color: bread.color, badge: String(localized: "Validade 5 dias"))
            withAnimation(.easeInOut(duration: 0.3)) {
                groceryItems.removeAll { $0.id == bread.id }
            }
            movingItem = MovingItem(item: bread, startX: rightCenter, endX: leftCenter, position: .start)
            await wait(80)
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) {
                movingItem?.position = .end
            }
            await wait(700)
            HapticManager.impact(style: .medium)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                pantryItems.insert(bread, at: 0)
                movingItem = nil
            }
            await wait(900)

            // Show badge
            HapticManager.impact(style: .light)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showBadge = true
            }
            await wait(1800)
        }
    }

    private func wait(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}

// MARK: - Models & Subviews

private struct SyncItemMock: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let badge: String?
}

private struct MovingItem {
    enum Position { case start, end }
    let item: SyncItemMock
    let startX: CGFloat
    let endX: CGFloat
    var position: Position
}

private struct SyncItemChip: View {
    let item: SyncItemMock

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(item.color.opacity(0.25)).frame(width: 26, height: 26)
                Text(item.icon).font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                if let badge = item.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct MovingChip: View {
    let item: SyncItemMock

    var body: some View {
        HStack(spacing: 6) {
            Text(item.icon).font(.system(size: 16))
            Text(item.name)
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(item.color.opacity(0.95))
        )
        .foregroundStyle(.white)
        .shadow(color: item.color.opacity(0.5), radius: 8, y: 3)
    }
}
