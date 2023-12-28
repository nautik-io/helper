import Foundation

struct DateFormatter {
    static let `default`: DateComponentsFormatter = {
        var dateFormatter = DateComponentsFormatter()
        
        dateFormatter.maximumUnitCount = 2
        dateFormatter.unitsStyle = .abbreviated
        dateFormatter.zeroFormattingBehavior = .dropAll
        
        return dateFormatter
    }()
}
