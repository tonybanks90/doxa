# Binary Market Resolution Test Report

Date: Thu Dec 11 06:03:20 AM EAT 2025

## Identities
- **Resolver:** `bocwt-bhiax-wdyeh-j4thh-fyvib-xa5bi-uqf7z-7t3ep-myry3-jurns-yae`
- **Trader YES:** `47ctq-vthkj-r65te-io4xo-a3t7u-2xnss-t236i-6madj-z6qai-jtwwb-bae`
- **Trader NO:** `3h5fv-fwa3i-va2wi-3jpg6-hcere-dlec2-sbmpk-dsmmk-4fyi5-me3w4-2qe`

## Market Details
- **ID:** 1
- **Title:** Will BTC hit 100k?
- **Timings:** Close +10s, Expire +20s

## Trading
- Trader YES bought 10M sats of YES
- Trader NO bought 10M sats of NO

## Resolution
- **Outcome:** YES
- **Status:** Resolved Successfully

## Redemption
- **Trader YES (Winner):** Redeemed 20 sats. (Balance: 39999980 -> 59999970)
- **Trader NO (Loser):** No payout (Expected). Response: (
  variant {
    err = "No winning position found. You do not hold tokens for the winning outcome."
  },
)
