//
//  PriceFetcher.swift
//  IotaMonitor
//
//  SN9 alpha ("iota-2") and TAO ("bittensor") prices from CoinGecko free API.
//  A manual override can be set in Store ("price_override_alpha").
//

import Foundation

public final class PriceFetcher {
    public static let shared = PriceFetcher()

    public func fetch() -> CoinPrices? {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=iota-2,bittensor&vs_currencies=usd,cny") else {
            return nil
        }
        guard let data = try? HTTPFetcher.shared.get(url) else { return nil }
        var prices = CoinPrices.decode(from: data)

        // manual override
        let override = Store.shared.double(key: "price_override_alpha", defaultValue: 0)
        if override > 0 {
            prices = CoinPrices(
                alphaUSD: override,
                alphaCNY: override * (Store.shared.double(key: "usd_cny_rate", defaultValue: 7.2)),
                taoUSD: prices.taoUSD,
                taoCNY: prices.taoCNY
            )
        }
        return prices
    }

    /// 收益折算：IOTA = 只显示代币数量不折算；CNY 优先人民币价格，
    /// 缺失时用 USD × 汇率兜底。
    public static func format(alpha: Double, prices: CoinPrices?, currency: String) -> String {
        if currency == "IOTA" {
            return ""
        }
        let symbol = currency == "CNY" ? "¥" : "$"
        let value: Double?
        if currency == "CNY" {
            value = prices?.alphaCNY ?? (prices?.alphaUSD ?? 0) * Store.shared.double(key: "usd_cny_rate", defaultValue: 7.2)
        } else {
            value = prices?.alphaUSD
        }
        guard let v = value, v > 0 else { return "" }
        return "\(symbol)\(String(format: "%.2f", alpha * v))"
    }
}
