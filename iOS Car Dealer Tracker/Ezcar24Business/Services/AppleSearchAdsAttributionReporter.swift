import Foundation
import RevenueCat

#if canImport(AdServices)
import AdServices
#endif

struct AppleSearchAdsAttributionMetadata: Equatable {
    private let response: [String: AnyHashable]

    init(response: [String: Any]) {
        self.response = response.reduce(into: [:]) { partialResult, item in
            if let value = item.value as? AnyHashable {
                partialResult[item.key] = value
            }
        }
    }

    var revenueCatAttributes: [String: String] {
        guard isAttributed else { return [:] }

        var attributes = [
            "$mediaSource": "Apple Search Ads"
        ]

        let campaignId = stringValue(for: ["campaignId", "iad-campaign-id"])
        let campaignName = stringValue(for: ["campaignName", "iad-campaign-name"])
        let adGroupId = stringValue(for: ["adGroupId", "adgroupId", "iad-adgroup-id"])
        let adGroupName = stringValue(for: ["adGroupName", "adgroupName", "iad-adgroup-name"])
        let adId = stringValue(for: ["adId", "iad-ad-id"])
        let adName = stringValue(for: ["adName", "iad-ad-name"])
        let keywordId = stringValue(for: ["keywordId", "iad-keyword-id"])
        let keyword = stringValue(for: ["keyword", "keywordText", "iad-keyword"])
        let countryOrRegion = stringValue(for: ["countryOrRegion", "country", "iad-country-or-region"])
        let claimType = stringValue(for: ["claimType", "iad-claim-type"])
        let orgId = stringValue(for: ["orgId", "iad-org-id"])
        let conversionType = stringValue(for: ["conversionType", "iad-conversion-type"])

        set(campaignName ?? campaignId, forKey: "$campaign", in: &attributes)
        set(adGroupName ?? adGroupId, forKey: "$adGroup", in: &attributes)
        set(adName ?? adId, forKey: "$ad", in: &attributes)
        set(keyword ?? keywordId, forKey: "$keyword", in: &attributes)

        set(campaignId, forKey: "apple_search_ads_campaign_id", in: &attributes)
        set(adGroupId, forKey: "apple_search_ads_ad_group_id", in: &attributes)
        set(adId, forKey: "apple_search_ads_ad_id", in: &attributes)
        set(keywordId, forKey: "apple_search_ads_keyword_id", in: &attributes)
        set(countryOrRegion, forKey: "apple_search_ads_country_or_region", in: &attributes)
        set(claimType, forKey: "apple_search_ads_claim_type", in: &attributes)
        set(orgId, forKey: "apple_search_ads_org_id", in: &attributes)
        set(conversionType, forKey: "apple_search_ads_conversion_type", in: &attributes)

        return attributes
    }

    private var isAttributed: Bool {
        boolValue(for: ["attribution", "iad-attribution"]) ?? hasAnyAttributionDimension
    }

    private var hasAnyAttributionDimension: Bool {
        stringValue(
            for: [
                "campaignId",
                "campaignName",
                "adGroupId",
                "adgroupId",
                "adId",
                "keywordId",
                "keyword",
                "iad-campaign-id",
                "iad-campaign-name",
                "iad-adgroup-id",
                "iad-ad-id",
                "iad-keyword-id",
                "iad-keyword"
            ]
        ) != nil
    }

    private func stringValue(for keys: [String]) -> String? {
        for key in keys {
            guard let value = response[key] else { continue }
            if let string = Self.normalizedString(value) {
                return string
            }
        }
        return nil
    }

    private func boolValue(for keys: [String]) -> Bool? {
        for key in keys {
            guard let value = response[key] else { continue }
            if let bool = value as? Bool {
                return bool
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
            if let string = value as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }

    private static func normalizedString(_ value: AnyHashable) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func set(_ value: String?, forKey key: String, in attributes: inout [String: String]) {
        guard let value, !value.isEmpty else { return }
        attributes[key] = value
    }
}

enum AppleSearchAdsAttributionReporter {
    private static let attributionEndpoint = URL(string: "https://api-adservices.apple.com/api/v1/")!

    static func reportIfAvailable() {
        guard Purchases.isConfigured else { return }

        Task.detached {
            guard let token = await adServicesAttributionToken() else { return }

            do {
                let response = try await fetchAttributionResponse(attributionToken: token)
                let attributes = AppleSearchAdsAttributionMetadata(response: response).revenueCatAttributes
                guard !attributes.isEmpty, Purchases.isConfigured else { return }
                Purchases.shared.attribution.setAttributes(attributes)
            } catch {
                #if DEBUG
                print("Apple Search Ads attribution attributes failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func fetchAttributionResponse(attributionToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: attributionEndpoint)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(attributionToken.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return dictionary
    }

    private static func adServicesAttributionToken() async -> String? {
        #if canImport(AdServices)
        guard #available(iOS 14.3, *) else { return nil }
        #if targetEnvironment(simulator)
        return nil
        #else
        return await Task.detached {
            do {
                return try AAAttribution.attributionToken()
            } catch {
                #if DEBUG
                print("Apple Search Ads attribution token failed: \(error.localizedDescription)")
                #endif
                return nil
            }
        }.value
        #endif
        #else
        return nil
        #endif
    }
}
