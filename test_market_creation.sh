#!/bin/bash

# Exit on error
set -e

echo "Testing market creation..."

# Calculate timestamps (nanoseconds)
# Close time: +1 hour
# Expiration time: +2 hours
NOW=$(date +%s)
CLOSE_TIME=$(( ($NOW + 3600) * 1000000000 ))
EXPIRATION_TIME=$(( ($NOW + 7200) * 1000000000 ))

echo "Close Time: $CLOSE_TIME"
echo "Expiration Time: $EXPIRATION_TIME"

# Call createBinaryMarket
# Note: category and tags are variants.
# category: #Crypto
# tags: [#Crypto, #Technology]
# image: #ImageUrl "https://example.com/image.png"

echo "Calling createBinaryMarket..."

dfx canister call marketfactory createBinaryMarket "(
  record {
    title = \"Will Bitcoin hit \$100k by 2025?\";
    description = \"Prediction market for Bitcoin price.\";
    category = variant { Crypto };
    image = variant { ImageUrl = \"https://cryptologos.cc/logos/bitcoin-btc-logo.png\" };
    tags = vec { variant { Crypto }; variant { Technology } };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://coingecko.com\";
    resolutionDescription = \"Price on CoinGecko at expiration.\";
  }
)"

echo "Market creation test complete!"
