import Foundation

extension Int32 {
    func asYear() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Int16 {
    func asYear() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
