import SwiftUI
import OpenTanEngine

/// A row of steppers, one per resource, used by the discard and trade sheets.
struct ResourceCounter: View {
    let title: String
    let limits: [Resource: Int]
    @Binding var amounts: [Resource: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Resource.allCases, id: \.self) { resource in
                let limit = limits[resource] ?? 0
                HStack {
                    Text(resource.glyph)
                    Text(resource.displayName)
                    Spacer()
                    Text("\(amounts[resource] ?? 0)")
                        .monospacedDigit()
                        .frame(minWidth: 24)
                    Stepper("") {
                        if (amounts[resource] ?? 0) < limit {
                            amounts[resource, default: 0] += 1
                        }
                    } onDecrement: {
                        if (amounts[resource] ?? 0) > 0 {
                            amounts[resource, default: 0] -= 1
                        }
                    }
                    .labelsHidden()
                    .disabled(limit == 0)
                }
                .opacity(limit == 0 ? 0.4 : 1)
            }
        }
    }
}

extension Dictionary where Key == Resource, Value == Int {
    var total: Int { values.reduce(0, +) }

    var summary: String {
        let parts = Resource.allCases.compactMap { resource -> String? in
            let amount = self[resource] ?? 0
            return amount > 0 ? "\(amount)\(resource.glyph)" : nil
        }
        return parts.isEmpty ? "nothing" : parts.joined(separator: " ")
    }
}
