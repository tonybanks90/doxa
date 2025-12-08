#!/bin/bash

# Exit on error
set -e

echo "Starting Full Market Test Suite..."

# Calculate timestamps (nanoseconds)
NOW=$(date +%s)
CLOSE_TIME=$(( ($NOW + 3600) * 1000000000 ))
EXPIRATION_TIME=$(( ($NOW + 7200) * 1000000000 ))

echo "------------------------------------------------"
echo "Test 1: Binary Market"
echo "------------------------------------------------"
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

echo "------------------------------------------------"
echo "Test 2: Multiple Choice Market"
echo "------------------------------------------------"
dfx canister call marketfactory createMultipleChoiceMarket "(
  record {
    title = \"Who will win the 2024 US Election?\";
    description = \"Prediction market for US Election.\";
    category = variant { Political };
    image = variant { ImageUrl = \"https://example.com/election.png\" };
    tags = vec { variant { Political } };
    outcomes = vec { \"Democrat\"; \"Republican\"; \"Independent\" };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://cnn.com\";
    resolutionDescription = \"Official election results.\";
  }
)"

echo "------------------------------------------------"
echo "Test 3: Compound Market"
echo "------------------------------------------------"
dfx canister call marketfactory createCompoundMarket "(
  record {
    title = \"Which tech stocks will grow >10% in Q4?\";
    description = \"Compound prediction for multiple stocks.\";
    category = variant { Stocks };
    image = variant { ImageUrl = \"https://example.com/stocks.png\" };
    tags = vec { variant { Technology } };
    subjects = vec { \"AAPL\"; \"GOOGL\"; \"TSLA\"; \"NVDA\" };
    bettingCloseTime = $CLOSE_TIME;
    expirationTime = $EXPIRATION_TIME;
    resolutionLink = \"https://nasdaq.com\";
    resolutionDescription = \"Nasdaq closing prices.\";
  }
)"

echo "------------------------------------------------"
echo "Full Market Test Suite Complete! ✅"
echo "------------------------------------------------"
