import SwiftUI

struct DurationPickerView: View {
    @State private var quantity1 = 1
    @State private var unit1 = "days"
    @State private var quantity2 = 1
    @State private var unit2 = "days"
    let units = ["days", "months"]

    var body: some View {
        VStack {
            HStack {
                Picker("Quantity", selection: $quantity1) {
                    ForEach(1...365, id: \.self) { num in
                        Text("\(num)")
                    }
                }
#if os(iOS)
                .pickerStyle(.wheel)
                .frame(width: 80, height: 120)
                .clipped()
#else
                .pickerStyle(.menu)
                .frame(width: 120)
#endif

                Picker("Unit", selection: $unit1) {
                    ForEach(units, id: \.self) { unit in
                        Text(unit)
                    }
                }
#if os(iOS)
                .pickerStyle(.wheel)
                .frame(width: 100, height: 120)
                .clipped()
#else
                .pickerStyle(.menu)
                .frame(width: 140)
#endif
            }
            .padding()

            Spacer()

            // Other UI components here...

            VStack {
                Text("Another Duration Picker Group")
                HStack {
                    Picker("Quantity", selection: $quantity2) {
                        ForEach(1...365, id: \.self) { num in
                            Text("\(num)")
                        }
                    }
#if os(iOS)
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 120)
                    .clipped()
#else
                    .pickerStyle(.menu)
                    .frame(width: 120)
#endif

                    Picker("Unit", selection: $unit2) {
                        ForEach(units, id: \.self) { unit in
                            Text(unit)
                        }
                    }
#if os(iOS)
                    .pickerStyle(.wheel)
                    .frame(width: 100, height: 120)
                    .clipped()
#else
                    .pickerStyle(.menu)
                    .frame(width: 140)
#endif
                }
                .padding()
            }
        }
        .padding()
    }
}
