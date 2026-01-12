import Foundation

extension Part {
    
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Part" : trimmed
    }

    var activeBatches: [PartBatch] {
        let set = batches as? Set<PartBatch> ?? []
        return set.filter { $0.deletedAt == nil }
    }

    var quantityOnHand: Decimal {
        activeBatches.reduce(Decimal(0)) { total, batch in
            total + (batch.quantityRemaining?.decimalValue ?? 0)
        }
    }

    var inventoryValue: Decimal {
        activeBatches.reduce(Decimal(0)) { total, batch in
            let remaining = batch.quantityRemaining?.decimalValue ?? 0
            let unitCost = batch.unitCost?.decimalValue ?? 0
            return total + (remaining * unitCost)
        }
    }
}
