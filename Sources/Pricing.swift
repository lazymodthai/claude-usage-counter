import Foundation

private struct ModelPricing {
    let inputPerM: Double
    let outputPerM: Double
    let cacheWritePerM: Double
    let cacheReadPerM: Double
}

private let pricingTable: [(key: String, price: ModelPricing)] = [
    ("claude-opus",   ModelPricing(inputPerM: 15.00, outputPerM: 75.00, cacheWritePerM: 18.75, cacheReadPerM: 1.50)),
    ("claude-sonnet", ModelPricing(inputPerM:  3.00, outputPerM: 15.00, cacheWritePerM:  3.75, cacheReadPerM: 0.30)),
    ("claude-haiku",  ModelPricing(inputPerM:  0.80, outputPerM:  4.00, cacheWritePerM:  1.00, cacheReadPerM: 0.08)),
]

private let defaultPricing = ModelPricing(inputPerM: 3.00, outputPerM: 15.00, cacheWritePerM: 3.75, cacheReadPerM: 0.30)

private func pricing(for model: String) -> ModelPricing {
    let lower = model.lowercased()
    return pricingTable.first { lower.contains($0.key) }?.price ?? defaultPricing
}

func calcCost(model: String, usage: TokenUsage) -> Double {
    let p = pricing(for: model)
    return Double(usage.input) * p.inputPerM / 1_000_000
        + Double(usage.output) * p.outputPerM / 1_000_000
        + Double(usage.cacheWrite) * p.cacheWritePerM / 1_000_000
        + Double(usage.cacheRead) * p.cacheReadPerM / 1_000_000
}
