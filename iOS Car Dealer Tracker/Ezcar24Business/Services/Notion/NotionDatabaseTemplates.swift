import Foundation

enum NotionExportType: String, CaseIterable, Identifiable {
    case vehicles = "Vehicles"
    case leads = "Leads"
    case sales = "Sales"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .vehicles:
            return "car.fill"
        case .leads:
            return "person.2.fill"
        case .sales:
            return "dollarsign.circle.fill"
        }
    }
}

enum NotionDatabaseTemplates {
    
    static func vehicleDatabaseSchema() -> [String: NotionPropertyDefinition] {
        [
            "VIN": .title(),
            "Make": .richText(),
            "Model": .richText(),
            "Year": .number(format: "number"),
            "Purchase Price": .number(format: "dollar"),
            "Purchase Date": .date(),
            "Status": .select(options: [
                NotionSelectOption(name: "owned", color: "green"),
                NotionSelectOption(name: "sold", color: "blue")
            ]),
            "Sale Price": .number(format: "dollar"),
            "Sale Date": .date(),
            "Asking Price": .number(format: "dollar"),
            "Days in Inventory": .formula(expression: "if(empty(prop(\"Sale Date\")), dateBetween(now(), prop(\"Purchase Date\"), \"days\"), dateBetween(prop(\"Sale Date\"), prop(\"Purchase Date\"), \"days\"))"),
            "Total Expenses": .number(format: "dollar"),
            "Holding Cost": .number(format: "dollar"),
            "Holding Cost / Day": .number(format: "dollar"),
            "Total Cost": .formula(expression: "prop(\"Purchase Price\") + prop(\"Total Expenses\") + prop(\"Holding Cost\")"),
            "ROI %": .formula(expression: "((prop(\"Sale Price\") - prop(\"Total Cost\")) / prop(\"Total Cost\")) * 100"),
            "Profit": .formula(expression: "prop(\"Sale Price\") - prop(\"Total Cost\")"),
            "Aging Bucket": .select(options: [
                NotionSelectOption(name: "0-30", color: "green"),
                NotionSelectOption(name: "31-60", color: "yellow"),
                NotionSelectOption(name: "61-90", color: "orange"),
                NotionSelectOption(name: "90+", color: "red")
            ])
        ]
    }
    
    static func leadDatabaseSchema() -> [String: NotionPropertyDefinition] {
        [
            "Name": .title(),
            "Phone": .phoneNumber(),
            "Email": .email(),
            "Stage": .select(options: [
                NotionSelectOption(name: "new", color: "gray"),
                NotionSelectOption(name: "contacted", color: "blue"),
                NotionSelectOption(name: "qualified", color: "yellow"),
                NotionSelectOption(name: "negotiation", color: "orange"),
                NotionSelectOption(name: "offer", color: "purple"),
                NotionSelectOption(name: "test_drive", color: "pink"),
                NotionSelectOption(name: "closed_won", color: "green"),
                NotionSelectOption(name: "closed_lost", color: "red")
            ]),
            "Source": .select(options: [
                NotionSelectOption(name: "facebook", color: "blue"),
                NotionSelectOption(name: "dubizzle", color: "orange"),
                NotionSelectOption(name: "instagram", color: "pink"),
                NotionSelectOption(name: "referral", color: "green"),
                NotionSelectOption(name: "walk_in", color: "gray"),
                NotionSelectOption(name: "phone", color: "yellow"),
                NotionSelectOption(name: "website", color: "purple"),
                NotionSelectOption(name: "other", color: "brown")
            ]),
            "Lead Score": .number(format: "number"),
            "Priority": .select(options: [
                NotionSelectOption(name: "Low", color: "gray"),
                NotionSelectOption(name: "Medium", color: "yellow"),
                NotionSelectOption(name: "High", color: "red")
            ]),
            "Estimated Value": .number(format: "dollar"),
            "Days Since Created": .number(format: "number"),
            "Days Since Last Contact": .number(format: "number"),
            "Interaction Count": .number(format: "number"),
            "Next Follow-up": .date(),
            "Notes": .richText()
        ]
    }
    
    static func salesDatabaseSchema() -> [String: NotionPropertyDefinition] {
        [
            "Vehicle": .title(),
            "Sale Price": .number(format: "dollar"),
            "Sale Date": .date(),
            "Buyer Name": .richText(),
            "Total Cost": .number(format: "dollar"),
            "Profit": .number(format: "dollar"),
            "ROI %": .number(format: "percent"),
            "Days to Sell": .number(format: "number")
        ]
    }
    
    static func databaseName(for type: NotionExportType) -> String {
        switch type {
        case .vehicles:
            return "Vehicle Inventory"
        case .leads:
            return "Lead Management"
        case .sales:
            return "Sales History"
        }
    }
    
    static func schema(for type: NotionExportType) -> [String: NotionPropertyDefinition] {
        switch type {
        case .vehicles:
            return vehicleDatabaseSchema()
        case .leads:
            return leadDatabaseSchema()
        case .sales:
            return salesDatabaseSchema()
        }
    }
}
