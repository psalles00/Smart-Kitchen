import SwiftUI

/// Sheet compacta para registrar peso corporal com dois wheel pickers (inteiro + decimal).
struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss

    let currentWeightKg: Double
    let useMetric: Bool
    let onSave: (Double) -> Void

    @State private var wholeNumber: Int
    @State private var decimal: Int

    init(currentWeightKg: Double, useMetric: Bool, onSave: @escaping (Double) -> Void) {
        self.currentWeightKg = currentWeightKg
        self.useMetric = useMetric
        self.onSave = onSave
        let displayValue = useMetric ? currentWeightKg : currentWeightKg * 2.20462
        let whole = Int(displayValue)
        let dec = min(9, max(0, Int((displayValue - Double(whole)) * 10 + 0.5)))
        _wholeNumber = State(initialValue: whole)
        _decimal = State(initialValue: dec)
    }

    private var selectedValue: Double {
        Double(wholeNumber) + Double(decimal) / 10.0
    }

    private var selectedKg: Double {
        useMetric ? selectedValue : selectedValue / 2.20462
    }

    private var unit: String { useMetric ? "kg" : "lbs" }
    private var wholeRange: ClosedRange<Int> { useMetric ? 20...250 : 50...500 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Registrar peso")
                        .font(.sectionTitle)
                    Text("Acompanhe sua evolução ao longo do tempo.")
                        .font(.serifBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                HStack(spacing: 0) {
                    Picker("Inteiro", selection: $wholeNumber) {
                        ForEach(wholeRange, id: \.self) { num in
                            Text("\(num)").tag(num)
                                .font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    #else
                    .pickerStyle(.menu)
                    #endif
                    .frame(width: 110)
                    .clipped()

                    Text(",")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .offset(y: -2)

                    Picker("Decimal", selection: $decimal) {
                        ForEach(0...9, id: \.self) { num in
                            Text("\(num)").tag(num)
                                .font(.system(.title2, design: .rounded, weight: .medium))
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.wheel)
                    #else
                    .pickerStyle(.menu)
                    #endif
                    .frame(width: 80)
                    .clipped()

                    Text(unit)
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }

                Button {
                    onSave(selectedKg)
                    dismiss()
                } label: {
                    Text("Salvar")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PageTheme.nutrients.accentColor, in: .capsule)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding()
            .savoriaModalBorder(theme: .nutrients)
            .modalNavigationTitle(String(localized: "Registrar peso"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
