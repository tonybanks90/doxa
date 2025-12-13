import Debug "mo:base/Debug";
import Float "mo:base/Float";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";

persistent actor Markets {

  // ===== TYPES =====

  // Market types
  public type MarketType = {
    #Binary;
    #MultipleChoice;
    #Compound;
  };

  // Token identification system
  public type TokenIdentifier = {
    #Binary : BinaryToken; // For binary markets
    #Outcome : Text; // For multiple choice markets
    #Subject : (Text, BinaryToken); // For compound markets: (subject_name, YES/NO)
  };

  public type BinaryToken = {
    #YES;
    #NO;
  };

  // Market resolution types
  public type MarketResolution = {
    #Binary : BinaryOutcome;
    #MultipleChoice : Text; // Winning outcome name
    #Compound : [(Text, BinaryOutcome)]; // Subject name -> outcome
  };

  public type BinaryOutcome = { #Yes; #No };

  // Vault address configuration
  public type VaultAddressConfig = {
    #Binary : {
      marketVault : Principal; // Single vault for both YES/NO trading
    };
    #MultipleChoice : {
      marketVault : Principal; // Single vault for all outcomes
    };
    #Compound : {
      subjectVaults : [(Text, Principal)]; // One vault per subject
    };
  };

  // ===== BONDING CURVE TYPES =====

  public type BondingCurveParams = {
    basePrice : Nat64;
    priceSlope : Nat64;
  };

  // Bonding curve parameters for each outcome
  public type BondingCurveConfig = {
    basePrice : Nat64; // Starting price in satoshis (e.g., 1000)
    priceSlope : Nat64; // Price increase per share (e.g., 50)
    currentSupply : Nat64; // Current shares minted for this outcome
    poolBalance : Nat64; // Total satoshis in this outcome's pool
  };

  // Holder position with stake tracking for parimutuel payouts
  public type HolderPosition = {
    shares : Nat64; // Number of shares held
    totalPaid : Nat64; // Total satoshis invested
    claimed : Bool; // Whether winnings have been claimed
  };

  // Claim result type
  public type ClaimResult = {
    stakeReturned : Nat64; // Original stake returned
    winningsFromLosingPool : Nat64; // Share of losing pool
    totalPayout : Nat64; // Total amount paid out
  };

  // Market-specific configurations
  public type BinaryMarketConfig = {
    ledger : Principal;
    yesTokenId : TokenId;
    noTokenId : TokenId;
    qYes : Float; // YES inventory (legacy LMSR)
    qNo : Float; // NO inventory (legacy LMSR)
    // NEW: Bonding curve configs per outcome
    yesCurve : ?BondingCurveConfig;
    noCurve : ?BondingCurveConfig;
  };

  public type MultipleChoiceConfig = {
    ledger : Principal;
    outcomes : [(Text, TokenId)]; // outcome name -> token id
    outcomeCurves : [(Text, BondingCurveConfig)]; // outcome name -> curve
  };

  public type CompoundSubjectConfig = {
    yesTokenId : TokenId;
    noTokenId : TokenId;
    yesCurve : ?BondingCurveConfig;
    noCurve : ?BondingCurveConfig;
  };

  public type CompoundConfig = {
    ledger : Principal;
    subjects : [(Text, CompoundSubjectConfig)];
  };

  // Enhanced market state
  public type MarketState = {
    id : Nat;
    marketType : MarketType;
    question : Text;
    resolver : Principal;
    expiry : Nat64;
    ledger : Principal; // Main ledger for the market
    // b removed (LMSR)
    resolved : ?MarketResolution; // Enhanced resolution structure
    active : Bool;
    totalVolumeSatoshis : Nat64; // Total satoshi volume traded
    totalSupply : Nat64; // Total tokens that can be minted
    currentSupply : Nat64; // Currently minted tokens
    createdAt : Nat64;
    vaultConfig : ?VaultAddressConfig; // Vault addresses for this market
    vaultRegistered : Bool; // Whether vaults are set up
    // Market-specific configurations
    binaryConfig : ?BinaryMarketConfig;
    multipleChoiceConfig : ?MultipleChoiceConfig;
    compoundConfig : ?CompoundConfig;
  };

  // Registration arguments
  public type BaseRegistrationArgs = {
    question : Text;
    resolver : Principal;
    expiry : Nat64;
    bondingCurve : BondingCurveParams;
    totalSupply : Nat64; // Maximum tokens mintable
  };

  public type BinaryRegistrationArgs = {
    base : BaseRegistrationArgs;
    ledger : Principal;
    yesTokenId : TokenId;
    noTokenId : TokenId;
  };

  public type MultipleChoiceRegistrationArgs = {
    base : BaseRegistrationArgs;
    ledger : Principal;
    outcomes : [(Text, TokenId)];
  };

  public type CompoundRegistrationArgs = {
    base : BaseRegistrationArgs;
    ledger : Principal;
    subjects : [(Text, { yesTokenId : TokenId; noTokenId : TokenId })];
  };

  // Trading result types
  public type BuyResult = {
    tokensReceived : Float;
    actualCostSatoshis : Nat64;
    newPrice : Float;
  };

  public type SellResult = {
    satoshisReceived : Nat64;
    newPrice : Float;
  };

  // Registration result
  public type MarketRegistrationResult = {
    marketId : Nat;
    vaultConfig : VaultAddressConfig;
    setupComplete : Bool;
  };

  // Redemption types
  public type RedemptionResult = {
    totalSatoshisRedeemed : Nat64;
    redemptions : [TokenRedemption];
  };

  public type TokenRedemption = {
    tokenIdentifier : TokenIdentifier;
    tokensBurned : Nat64;
    satoshisReceived : Nat64;
  };

  // Transaction History Type
  public type MarketTransaction = {
    txId : Nat;
    marketId : Nat;
    user : Principal;
    operation : { #Buy; #Sell };
    tokenIdentifier : TokenIdentifier;
    amount : Float;
    price : Float;
    cost : Nat;
    timestamp : Nat64;
  };

  public type HolderBalance = {
    user : Principal;
    balance : Float;
  };

  // Extended holder info for parimutuel markets
  public type ExtendedHolderInfo = {
    user : Principal;
    outcome : TokenIdentifier;
    position : HolderPosition;
  };

  // ICRC-1 Ledger Interface (for ckBTC)
  public type ICRC1Interface = actor {
    icrc1_transfer : (TransferArgs) -> async (TransferResult);
    icrc1_balance_of : (Account) -> async (Nat);
    icrc2_transfer_from : (TransferFromArgs) -> async (TransferFromResult);
  };

  // ===== ICRC-151 TYPES =====
  public type TokenId = Blob;

  // ICRC-151 Account (uses Blob subaccount instead of [Nat8])
  public type ICRC151Account = {
    owner : Principal;
    subaccount : ?Blob;
  };

  // ICRC-151 Transfer Args
  public type Icrc151TransferArgs = {
    to : ICRC151Account;
    fee : ?Nat;
    token_id : TokenId;
    memo : ?Blob;
    from_subaccount : ?Blob;
    created_at_time : ?Nat64;
    amount : Nat;
  };

  // ICRC-151 Transfer From Args
  public type Icrc151TransferFromArgs = {
    to : ICRC151Account;
    fee : ?Nat;
    spender_subaccount : ?Blob;
    token_id : TokenId;
    from : ICRC151Account;
    memo : ?Blob;
    created_at_time : ?Nat64;
    amount : Nat;
  };

  // ICRC-151 Result types
  public type Icrc151TransferError = {
    #GenericError : { message : Text; error_code : Nat };
    #TemporarilyUnavailable;
    #BadBurn : { min_burn_amount : Nat };
    #Duplicate : { duplicate_of : Nat64 };
    #BadFee : { expected_fee : Nat };
    #CreatedInFuture : { ledger_time : Nat64 };
    #TooOld;
    #InsufficientFunds : { balance : Nat };
  };

  public type Icrc151TransferResult = {
    #Ok : Nat64;
    #Err : Icrc151TransferError;
  };

  public type Icrc151QueryError = {
    #InvalidInput : Text;
    #TokenNotFound;
    #InternalError : Text;
  };

  // ICRC-151 Ledger Interface
  public type ICRC151Interface = actor {
    // Token operations
    mint_tokens : (token_id : TokenId, to : ICRC151Account, amount : Nat, memo : ?Blob) -> async {
      #Ok : Nat64;
      #Err : Text;
    };
    burn_tokens_from : (token_id : TokenId, from : ICRC151Account, amount : Nat, memo : ?Blob) -> async {
      #Ok : Nat64;
      #Err : Text;
    };

    // Query operations
    get_balance : (token_id : TokenId, account : ICRC151Account) -> async {
      #Ok : Nat;
      #Err : Icrc151QueryError;
    };

    // Transfer operations
    transfer : (Icrc151TransferArgs) -> async Icrc151TransferResult;
    transfer_from : (Icrc151TransferFromArgs) -> async Icrc151TransferResult;
  };

  public type Account = {
    owner : Principal;
    subaccount : ?[Nat8];
  };

  public type TransferArgs = {
    from_subaccount : ?[Nat8];
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?[Nat8];
    created_at_time : ?Nat64;
  };

  public type TransferFromArgs = {
    spender_subaccount : ?[Nat8];
    from : Account;
    to : Account;
    amount : Nat;
    fee : ?Nat;
    memo : ?[Nat8];
    created_at_time : ?Nat64;
  };

  public type TransferResult = {
    #Ok : Nat;
    #Err : TransferError;
  };

  public type TransferFromResult = {
    #Ok : Nat;
    #Err : TransferFromError;
  };

  public type TransferError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #TemporarilyUnavailable;
    #Duplicate : { duplicate_of : Nat };
    #GenericError : { error_code : Nat; message : Text };
  };

  public type TransferFromError = {
    #BadFee : { expected_fee : Nat };
    #BadBurn : { min_burn_amount : Nat };
    #InsufficientFunds : { balance : Nat };
    #InsufficientAllowance : { allowance : Nat };
    #TooOld;
    #CreatedInFuture : { ledger_time : Nat64 };
    #TemporarilyUnavailable;
    #Duplicate : { duplicate_of : Nat };
    #GenericError : { error_code : Nat; message : Text };
  };

  // Vault Interface
  public type VaultInterface = actor {
    setupMarketVault : (VaultSetupRequest) -> async (Result.Result<VaultSetupResponse, Text>);
    pull_ckbtc : (marketId : Nat, user : Principal, amount : Nat) -> async (Result.Result<{ blockIndex : Nat; timestamp : Nat64 }, Text>);
    pay_ckbtc : (marketId : Nat, user : Principal, amount : Nat) -> async (Result.Result<{ blockIndex : Nat; timestamp : Nat64 }, Text>);
    get_balance_async : (Nat) -> async (Result.Result<Nat, Text>);
    registerMarket : (Nat, MarketType) -> async (Result.Result<(), Text>);
  };

  public type VaultSetupRequest = {
    marketId : Nat;
    marketType : MarketType;
    subjects : ?[Text]; // For compound markets
    totalSupply : Nat64; // Expected maximum volume
  };

  public type VaultSetupResponse = {
    addresses : VaultAddressConfig; // Generated vault addresses
    setupTimestamp : Nat64;
    status : VaultStatus;
  };

  public type VaultStatus = {
    #Active;
    #Paused;
    #Resolved;
    #PayoutComplete;
  };

  public type VaultTradingRequest = {
    marketId : Nat;
    vaultAddress : Principal; // Specific vault to use
    user : Principal;
    amount : Nat64;
    operation : VaultOperation;
    tokenIdentifier : TokenIdentifier; // For vault routing decisions
  };

  public type VaultOperation = {
    #Pull; // Take ckBTC from user
    #Pay; // Send ckBTC to user
  };

  public type VaultResolutionRequest = {
    marketId : Nat;
    resolution : MarketResolution;
    vaultAddresses : [Principal]; // All vaults for this market
    winningTokens : [WinningToken]; // Tokens eligible for 1:1 payout
  };

  public type WinningToken = {
    tokenIdentifier : TokenIdentifier;
    payoutRatio : Float; // Usually 1.0 (1:1 payout)
  };

  public type VaultPayoutRequest = {
    marketId : Nat;
    vaultAddress : Principal;
    user : Principal;
    amount : Nat64;
    tokenIdentifier : TokenIdentifier;
  };

  public type PayoutResult = {
    amountPaid : Nat64;
    transactionId : ?Text;
  };

  public type MarketConfigResponse = {
    marketId : Nat;
    config : MarketConfigType;
  };

  public type MarketConfigType = {
    #Binary : BinaryMarketConfig;
    #MultipleChoice : MultipleChoiceConfig;
    #Compound : CompoundConfig;
  };

  // TRANSIENT DECLARATIONS FIX - Lines 298-349
  // Replace the ===== STATE ===== section with this:

  // ===== STATE =====

  stable var marketsEntries : [(Nat, MarketState)] = [];
  private transient var markets : TrieMap.TrieMap<Nat, MarketState> = TrieMap.TrieMap<Nat, MarketState>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Transaction History State
  stable var marketTransactionsEntries : [(Nat, [MarketTransaction])] = [];
  private transient var marketTransactions : TrieMap.TrieMap<Nat, Buffer.Buffer<MarketTransaction>> = TrieMap.TrieMap<Nat, Buffer.Buffer<MarketTransaction>>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
  stable var nextTxId : Nat = 1;

  // Holder State (MarketId -> Principal -> Balance) - Legacy
  stable var marketHoldersEntries : [(Nat, Principal, Float)] = [];
  private transient var marketHolders : TrieMap.TrieMap<Nat, TrieMap.TrieMap<Principal, Float>> = TrieMap.TrieMap<Nat, TrieMap.TrieMap<Principal, Float>>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // NEW: Holder Positions with stake tracking (MarketId -> "YES"/"NO" -> Principal -> HolderPosition)
  // Using Text key for outcome: "YES" or "NO"
  stable var holderPositionsEntries : [(Nat, Text, Principal, HolderPosition)] = [];
  private transient var holderPositions : TrieMap.TrieMap<Nat, TrieMap.TrieMap<Text, TrieMap.TrieMap<Principal, HolderPosition>>> = TrieMap.TrieMap<Nat, TrieMap.TrieMap<Text, TrieMap.TrieMap<Principal, HolderPosition>>>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  stable var nextMarketId : Nat = 1;

  // Configuration
  private stable var tokenFactoryCanister : ?Principal = null;
  private stable var vaultCanister : ?Principal = null;

  // ===== HELPER FUNCTIONS =====
  // ===== HELPER FUNCTIONS SECTION (Lines 315-440) =====
  // REPLACE THIS ENTIRE SECTION

  // Convert between satoshis and float for LMSR calculations
  private func satoshisToFloat(satoshis : Nat64) : Float {
    Float.fromInt64(Int64.fromNat64(satoshis));
  };

  private func floatToSatoshis(amount : Float) : Nat64 {
    let rounded = Float.toInt(Float.nearest(amount));
    Nat64.fromNat(Int.abs(rounded));
  };

  // ✅ CHANGED: Removed broken generic isUniqueArray function
  // ✅ ADDED: Specific functions for each type

  // Check if Text array has unique elements
  private func isUniqueTexts(arr : [Text]) : Bool {
    let size = arr.size();
    for (i in Iter.range(0, size - 1)) {
      for (j in Iter.range(i + 1, size - 1)) {
        if (arr[i] == arr[j]) {
          return false;
        };
      };
    };
    true;
  };

  // Check if Principal array has unique elements
  private func isUniquePrincipals(arr : [Principal]) : Bool {
    let size = arr.size();
    for (i in Iter.range(0, size - 1)) {
      for (j in Iter.range(i + 1, size - 1)) {
        if (Principal.equal(arr[i], arr[j])) {
          return false;
        };
      };
    };
    true;
  };

  // Validate base registration arguments
  private func validateBaseArgs(args : BaseRegistrationArgs) : Result.Result<(), Text> {
    if (Text.size(args.question) == 0) {
      return #err("Question cannot be empty");
    };

    if (args.expiry <= Nat64.fromNat(Int.abs(Time.now()))) {
      return #err("Expiry must be in the future");
    };

    if (args.bondingCurve.basePrice == 0) {
      return #err("Base price must be positive");
    };

    if (args.bondingCurve.priceSlope == 0) {
      return #err("Price slope must be positive");
    };

    if (args.totalSupply == 0) {
      return #err("Total supply must be greater than 0");
    };

    #ok();
  };

  // Get inventory for specific outcome in multiple choice
  private func getInventoryForOutcome(inventories : [(Text, Float)], targetOutcome : Text) : Float {
    switch (Array.find<(Text, Float)>(inventories, func((name, _)) = name == targetOutcome)) {
      case (null) { 0.0 };
      case (?(_, inventory)) { inventory };
    };
  };

  // Update inventory for specific outcome
  private func updateInventory(inventories : [(Text, Float)], targetOutcome : Text, change : Float) : [(Text, Float)] {
    Array.map<(Text, Float), (Text, Float)>(
      inventories,
      func((name, inventory)) = if (name == targetOutcome) {
        (name, inventory + change);
      } else { (name, inventory) },
    );
  };

  // Get token ID for specific outcome
  private func getTokenIdForOutcome(outcomes : [(Text, TokenId)], targetOutcome : Text) : ?TokenId {
    switch (Array.find<(Text, TokenId)>(outcomes, func((name, _)) = name == targetOutcome)) {
      case (null) { null };
      case (?(_, tokenId)) { ?tokenId };
    };
  };

  // Get subject configuration from compound market
  private func getSubjectConfig(subjects : [(Text, CompoundSubjectConfig)], targetSubject : Text) : ?CompoundSubjectConfig {
    switch (Array.find<(Text, CompoundSubjectConfig)>(subjects, func((name, _)) = name == targetSubject)) {
      case (null) { null };
      case (?(_, config)) { ?config };
    };
  };

  // Update subject in compound market
  private func updateSubjectInCompound(subjects : [(Text, CompoundSubjectConfig)], targetSubject : Text, newConfig : CompoundSubjectConfig) : [(Text, CompoundSubjectConfig)] {
    Array.map<(Text, CompoundSubjectConfig), (Text, CompoundSubjectConfig)>(
      subjects,
      func((name, config)) = if (name == targetSubject) { (name, newConfig) } else {
        (name, config);
      },
    );
  };

  // Extract vault addresses from config
  private func extractVaultAddresses(vaultConfig : VaultAddressConfig) : [Principal] {
    switch (vaultConfig) {
      case (#Binary(config)) { [config.marketVault] };
      case (#MultipleChoice(config)) { [config.marketVault] };
      case (#Compound(config)) {
        Array.map<(Text, Principal), Principal>(config.subjectVaults, func((_, vault)) = vault);
      };
    };
  };

  // Calculate winning tokens based on market resolution
  private func calculateWinningTokens(
    marketType : MarketType,
    resolution : MarketResolution,
  ) : [WinningToken] {
    switch (marketType, resolution) {
      case (#Binary, #Binary(outcome)) {
        let tokenType = switch (outcome) {
          case (#Yes) { #Binary(#YES) };
          case (#No) { #Binary(#NO) };
        };
        [{ tokenIdentifier = tokenType; payoutRatio = 1.0 }];
      };

      case (#MultipleChoice, #MultipleChoice(winningOutcome)) {
        [{ tokenIdentifier = #Outcome(winningOutcome); payoutRatio = 1.0 }];
      };

      case (#Compound, #Compound(subjectResults)) {
        Array.map<(Text, BinaryOutcome), WinningToken>(
          subjectResults,
          func((subject, outcome)) {
            let tokenType = switch (outcome) {
              case (#Yes) { #Subject((subject, #YES)) };
              case (#No) { #Subject((subject, #NO)) };
            };
            { tokenIdentifier = tokenType; payoutRatio = 1.0 };
          },
        );
      };

      case (_, _) { [] };
    };
  };

  // Get token ID for token identifier
  private func getTokenIdForIdentifier(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
  ) : ?TokenId {
    switch (market.marketType, tokenIdentifier) {
      case (#Binary, #Binary(binaryToken)) {
        switch (market.binaryConfig) {
          case (null) { null };
          case (?config) {
            switch (binaryToken) {
              case (#YES) { ?config.yesTokenId };
              case (#NO) { ?config.noTokenId };
            };
          };
        };
      };

      case (#MultipleChoice, #Outcome(outcomeName)) {
        switch (market.multipleChoiceConfig) {
          case (null) { null };
          case (?config) { getTokenIdForOutcome(config.outcomes, outcomeName) };
        };
      };

      case (#Compound, #Subject((subjectName, binaryToken))) {
        switch (market.compoundConfig) {
          case (null) { null };
          case (?config) {
            switch (getSubjectConfig(config.subjects, subjectName)) {
              case (null) { null };
              case (?subjectConfig) {
                switch (binaryToken) {
                  case (#YES) { ?subjectConfig.yesTokenId };
                  case (#NO) { ?subjectConfig.noTokenId };
                };
              };
            };
          };
        };
      };

      case (_, _) { null };
    };
  };

  // Select vault address for trading
  private func selectVaultAddress(
    marketType : MarketType,
    vaultConfig : VaultAddressConfig,
    tokenIdentifier : TokenIdentifier,
  ) : Principal {
    switch (marketType, vaultConfig, tokenIdentifier) {
      case (#Binary, #Binary(config), _) {
        config.marketVault;
      };

      case (#MultipleChoice, #MultipleChoice(config), _) {
        config.marketVault;
      };

      case (#Compound, #Compound(config), #Subject((subjectName, _))) {
        switch (
          Array.find<(Text, Principal)>(
            config.subjectVaults,
            func((name, _)) = name == subjectName,
          )
        ) {
          case (null) {
            Debug.trap("Subject vault not found: " # subjectName);
          };
          case (?(_, vaultAddress)) { vaultAddress };
        };
      };

      case (_, _, _) {
        Debug.trap("Invalid market type/vault config/token combination");
      };
    };
  };

  // ===== END OF HELPER FUNCTIONS =====

  // ===== BONDING CURVE MATH =====
  // Linear bonding curve: Price = basePrice + (priceSlope × currentSupply)
  // Cost for n shares = n × (basePrice + priceSlope × (currentSupply + n/2))

  // Calculate current price on bonding curve
  private func calculateBondingCurvePrice(curve : BondingCurveConfig) : Nat64 {
    curve.basePrice + (curve.priceSlope * curve.currentSupply);
  };

  // Calculate how many shares can be bought for a given amount of satoshis
  // Using quadratic formula: cost = n * (basePrice + slope * (supply + n/2))
  // Rearranged: slope/2 * n² + (basePrice + slope*supply) * n - cost = 0
  private func calculateBondingCurveShares(curve : BondingCurveConfig, amountSatoshis : Nat64) : Nat64 {
    let base = curve.basePrice;
    let slope = curve.priceSlope;
    let supply = curve.currentSupply;
    let cost = amountSatoshis;

    // For very small slope, use simple linear approximation
    if (slope == 0) {
      if (base == 0) { return 0 };
      return cost / base;
    };

    // Quadratic formula: n = (-b + sqrt(b² + 2*a*c)) / a
    // where a = slope, b = basePrice + slope*supply, c = cost
    let a = Nat64.toNat(slope);
    let b = Nat64.toNat(base + slope * supply);
    let c = Nat64.toNat(cost);

    // Calculate discriminant: b² + 2*a*c
    let bSquared = b * b;
    let twoAC = 2 * a * c;
    let discriminant = bSquared + twoAC;

    // Integer square root approximation
    let sqrtDisc = natSqrt(discriminant);

    // n = (-b + sqrt) / a  (taking positive root)
    if (sqrtDisc <= b) { return 0 };
    let result = (sqrtDisc - b) / a;

    Nat64.fromNat(result);
  };

  // Calculate cost for a specific number of shares
  private func calculateBondingCurveCost(curve : BondingCurveConfig, shares : Nat64) : Nat64 {
    let base = curve.basePrice;
    let slope = curve.priceSlope;
    let supply = curve.currentSupply;

    // Cost = shares × (basePrice + slope × (currentSupply + shares/2))
    let avgPriceComponent = base + slope * supply + (slope * shares) / 2;
    shares * avgPriceComponent;
  };

  // Integer square root using Newton's method
  private func natSqrt(n : Nat) : Nat {
    if (n == 0) { return 0 };
    var x = n;
    var y = (x + 1) / 2;
    while (y < x) {
      x := y;
      y := (x + n / x) / 2;
    };
    x;
  };

  // Get or create holder position for a market/outcome/user
  private func getOrCreateHolderPosition(marketId : Nat, outcomeKey : Text, user : Principal) : HolderPosition {
    switch (holderPositions.get(marketId)) {
      case (null) {
        { shares = 0; totalPaid = 0; claimed = false };
      };
      case (?outcomeMap) {
        switch (outcomeMap.get(outcomeKey)) {
          case (null) {
            { shares = 0; totalPaid = 0; claimed = false };
          };
          case (?userMap) {
            switch (userMap.get(user)) {
              case (null) { { shares = 0; totalPaid = 0; claimed = false } };
              case (?pos) { pos };
            };
          };
        };
      };
    };
  };

  // Update holder position
  private func updateHolderPosition(marketId : Nat, outcomeKey : Text, user : Principal, newPosition : HolderPosition) {
    let outcomeMap = switch (holderPositions.get(marketId)) {
      case (null) {
        let m = TrieMap.TrieMap<Text, TrieMap.TrieMap<Principal, HolderPosition>>(Text.equal, Text.hash);
        holderPositions.put(marketId, m);
        m;
      };
      case (?m) { m };
    };

    let userMap = switch (outcomeMap.get(outcomeKey)) {
      case (null) {
        let m = TrieMap.TrieMap<Principal, HolderPosition>(Principal.equal, Principal.hash);
        outcomeMap.put(outcomeKey, m);
        m;
      };
      case (?m) { m };
    };

    userMap.put(user, newPosition);
  };

  // ===== LMSR MATH (Legacy) =====

  // Now the LMSR Math section continues normally...

  // Binary market LMSR functions
  private func costFunction(qYes : Float, qNo : Float, b : Float) : Float {
    let expYes = Float.exp(qYes / b);
    let expNo = Float.exp(qNo / b);
    b * Float.log(expYes + expNo);
  };

  private func calculatePrice(qYes : Float, qNo : Float, b : Float, outcome : BinaryToken) : Float {
    let expYes = Float.exp(qYes / b);
    let expNo = Float.exp(qNo / b);
    let sum = expYes + expNo;

    switch (outcome) {
      case (#YES) { expYes / sum };
      case (#NO) { expNo / sum };
    };
  };

  private func calculateTokensForCost(
    qYes : Float,
    qNo : Float,
    b : Float,
    outcome : BinaryToken,
    costInSatoshis : Float,
  ) : Float {
    let currentCost = costFunction(qYes, qNo, b);
    let targetCost = currentCost + costInSatoshis;

    var low : Float = 0.0;
    var high : Float = costInSatoshis * 2.0;
    var iterations = 0;

    while (iterations < 50 and (high - low) > 0.000001) {
      let mid = (low + high) / 2.0;
      let testCost = switch (outcome) {
        case (#YES) { costFunction(qYes + mid, qNo, b) };
        case (#NO) { costFunction(qYes, qNo + mid, b) };
      };

      if (testCost < targetCost) {
        low := mid;
      } else {
        high := mid;
      };
      iterations += 1;
    };

    (low + high) / 2.0;
  };

  private func calculateCostForTokens(
    qYes : Float,
    qNo : Float,
    b : Float,
    outcome : BinaryToken,
    tokens : Float,
  ) : Float {
    let currentCost = costFunction(qYes, qNo, b);
    let newCost = switch (outcome) {
      case (#YES) { costFunction(qYes + tokens, qNo, b) };
      case (#NO) { costFunction(qYes, qNo + tokens, b) };
    };
    newCost - currentCost;
  };

  // Multiple choice LMSR functions
  private func calculateMultipleChoicePrice(
    inventories : [(Text, Float)],
    b : Float,
    targetOutcome : Text,
  ) : Float {
    let targetInventory = getInventoryForOutcome(inventories, targetOutcome);
    let expTarget = Float.exp(targetInventory / b);

    var sumExp : Float = 0.0;
    for ((_, inventory) in inventories.vals()) {
      sumExp += Float.exp(inventory / b);
    };

    expTarget / sumExp;
  };

  private func calculateMultipleChoiceCost(inventories : [(Text, Float)], b : Float) : Float {
    var sumExp : Float = 0.0;
    for ((_, inventory) in inventories.vals()) {
      sumExp += Float.exp(inventory / b);
    };
    b * Float.log(sumExp);
  };

  private func calculateMultipleChoiceTokensForCost(
    inventories : [(Text, Float)],
    b : Float,
    targetOutcome : Text,
    costInSatoshis : Float,
  ) : Float {
    let currentCost = calculateMultipleChoiceCost(inventories, b);
    let targetCost = currentCost + costInSatoshis;

    var low : Float = 0.0;
    var high : Float = costInSatoshis * 2.0;
    var iterations = 0;

    while (iterations < 50 and (high - low) > 0.000001) {
      let mid = (low + high) / 2.0;
      let testInventories = updateInventory(inventories, targetOutcome, mid);
      let testCost = calculateMultipleChoiceCost(testInventories, b);

      if (testCost < targetCost) {
        low := mid;
      } else {
        high := mid;
      };
      iterations += 1;
    };

    (low + high) / 2.0;
  };

  // ===== VAULT INTEGRATION =====

  private func pullSatoshisFromMarketVault(
    marketId : Nat,
    user : Principal,
    amount : Nat64,
    tokenIdentifier : TokenIdentifier,
  ) : async Result.Result<(), Text> {

    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        switch (market.vaultConfig) {
          case (null) { return #err("Vault not configured for market") };
          case (?vaultConfig) {
            let vaultAddress = selectVaultAddress(market.marketType, vaultConfig, tokenIdentifier);

            switch (vaultCanister) {
              case (null) { return #err("Vault canister not set") };
              case (?vault) {
                let vaultActor : VaultInterface = actor (Principal.toText(vault));

                let tradingRequest : VaultTradingRequest = {
                  marketId = marketId;
                  vaultAddress = vaultAddress;
                  user = user;
                  amount = amount;
                  operation = #Pull;
                  tokenIdentifier = tokenIdentifier;
                };

                // Pull ckBTC from user to vault
                let pullResult = await vaultActor.pull_ckbtc(
                  marketId,
                  user,
                  Nat64.toNat(amount),
                );

                switch (pullResult) {
                  case (#err(e)) { return #err("Failed to pull ckBTC: " # e) };
                  case (#ok(_)) { #ok() };
                };
              };
            };
          };
        };
      };
    };
  };

  private func paySatoshisFromMarketVault(
    marketId : Nat,
    user : Principal,
    amount : Nat64,
    tokenIdentifier : TokenIdentifier,
  ) : async Result.Result<(), Text> {

    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        switch (market.vaultConfig) {
          case (null) { return #err("Vault not configured for market") };
          case (?vaultConfig) {
            let vaultAddress = selectVaultAddress(market.marketType, vaultConfig, tokenIdentifier);

            switch (vaultCanister) {
              case (null) { return #err("Vault canister not set") };
              case (?vault) {
                let vaultActor : VaultInterface = actor (Principal.toText(vault));

                let tradingRequest : VaultTradingRequest = {
                  marketId = marketId;
                  vaultAddress = vaultAddress;
                  user = user;
                  amount = amount;
                  operation = #Pay;
                  tokenIdentifier = tokenIdentifier;
                };

                // Pay ckBTC from vault to user
                let payResult = await vaultActor.pay_ckbtc(
                  marketId,
                  user,
                  Nat64.toNat(amount),
                );

                switch (payResult) {
                  case (#err(e)) { return #err("Failed to pay ckBTC: " # e) };
                  case (#ok(_)) { #ok() };
                };
              };
            };
          };
        };
      };
    };
  };

  // ===== TOKEN OPERATIONS (ICRC-151) =====

  private func mintTokens(ledgerPrincipal : Principal, tokenId : TokenId, user : Principal, amount : Nat64) : async Result.Result<(), Text> {
    let ledger : ICRC151Interface = actor (Principal.toText(ledgerPrincipal));
    let account : ICRC151Account = { owner = user; subaccount = null };

    switch (await ledger.mint_tokens(tokenId, account, Nat64.toNat(amount), null)) {
      case (#Ok(_)) { #ok() };
      case (#Err(error)) {
        #err("Failed to mint tokens: " # error);
      };
    };
  };

  private func burnTokens(ledgerPrincipal : Principal, tokenId : TokenId, user : Principal, amount : Nat64) : async Result.Result<(), Text> {
    let ledger : ICRC151Interface = actor (Principal.toText(ledgerPrincipal));
    let account : ICRC151Account = { owner = user; subaccount = null };

    switch (await ledger.burn_tokens_from(tokenId, account, Nat64.toNat(amount), null)) {
      case (#Ok(_)) { #ok() };
      case (#Err(error)) {
        #err("Failed to burn tokens: " # error);
      };
    };
  };

  private func getTokenBalance(ledgerPrincipal : Principal, tokenId : TokenId, user : Principal) : async Result.Result<Nat64, Text> {
    let ledger : ICRC151Interface = actor (Principal.toText(ledgerPrincipal));
    let account : ICRC151Account = { owner = user; subaccount = null };

    switch (await ledger.get_balance(tokenId, account)) {
      case (#Ok(balance)) { #ok(Nat64.fromNat(balance)) };
      case (#Err(_)) { #err("Failed to get token balance") };
    };
  };

  // ===== INITIALIZATION =====

  public shared (msg) func setTokenFactory(canister : Principal) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can set TokenFactory canister");
    };
    tokenFactoryCanister := ?canister;
    #ok();
  };

  public shared (msg) func setVaultCanister(canister : Principal) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can set Vault canister");
    };
    vaultCanister := ?canister;
    #ok();
  };

  // ===== MARKET REGISTRATION =====

  public shared (msg) func registerBinaryMarketWithVault(
    args : BinaryRegistrationArgs
  ) : async Result.Result<MarketRegistrationResult, Text> {

    // Validate caller is TokenFactory
    switch (tokenFactoryCanister) {
      case (null) {
        Debug.print("Error: TokenFactory canister not set");
        return #err("TokenFactory canister not set");
      };
      case (?factory) {
        if (not Principal.equal(msg.caller, factory)) {
          return #err("Only TokenFactory can register markets");
        };
      };
    };

    Debug.print("Registering Binary Market with Vault...");

    // Validate arguments
    let baseValidation = validateBaseArgs(args.base);
    switch (baseValidation) {
      case (#err(error)) { return #err(error) };
      case (#ok()) {};
    };

    if (args.yesTokenId == args.noTokenId) {
      return #err("YES and NO token IDs must be different");
    };

    let marketId = nextMarketId;
    nextMarketId += 1;

    let binaryConfig : BinaryMarketConfig = {
      ledger = args.ledger;
      yesTokenId = args.yesTokenId;
      noTokenId = args.noTokenId;
      qYes = 0.0;
      qNo = 0.0;
      // Initialize bonding curves with parameters for reasonable slippage
      // basePrice: 100 sats (starting price per share)
      // priceSlope: 5 sats per share (gradual ~5% price increase per 100 shares)
      yesCurve = ?{
        basePrice = args.base.bondingCurve.basePrice;
        priceSlope = args.base.bondingCurve.priceSlope;
        currentSupply = 0 : Nat64;
        poolBalance = 0 : Nat64;
      };
      noCurve = ?{
        basePrice = args.base.bondingCurve.basePrice;
        priceSlope = args.base.bondingCurve.priceSlope;
        currentSupply = 0 : Nat64;
        poolBalance = 0 : Nat64;
      };
    };

    let market : MarketState = {
      id = marketId;
      marketType = #Binary;
      question = args.base.question;
      resolver = args.base.resolver;
      expiry = args.base.expiry;
      ledger = args.ledger;
      resolved = null;
      active = true;
      totalVolumeSatoshis = 0;
      totalSupply = args.base.totalSupply;
      currentSupply = 0;
      createdAt = Nat64.fromNat(Int.abs(Time.now()));
      vaultConfig = null;
      vaultRegistered = false;
      binaryConfig = ?binaryConfig;
      multipleChoiceConfig = null;
      compoundConfig = null;
    };

    markets.put(marketId, market);

    // Request vault address from Vault Canister
    switch (vaultCanister) {
      case (null) {
        // Cleanup: remove market if vault setup fails
        markets.delete(marketId);
        return #err("Vault canister not configured");
      };
      case (?vault) {
        let vaultActor : VaultInterface = actor (Principal.toText(vault));

        let vaultRequest : VaultSetupRequest = {
          marketId = marketId;
          marketType = #Binary;
          subjects = null;
          totalSupply = args.base.totalSupply;
        };

        switch (await vaultActor.setupMarketVault(vaultRequest)) {
          case (#err(error)) {
            markets.delete(marketId);
            return #err("Vault setup failed: " # error);
          };
          case (#ok(vaultResponse)) {
            let updatedMarket = {
              market with
              vaultConfig = ?vaultResponse.addresses;
              vaultRegistered = true;
            };
            markets.put(marketId, updatedMarket);

            #ok({
              marketId = marketId;
              vaultConfig = vaultResponse.addresses;
              setupComplete = true;
            });
          };
        };
      };
    };
  };

  // ===== MULTIPLE CHOICE REGISTRATION (Lines 820-920) =====
  // ✅ CHANGES IN THIS FUNCTION

  public shared (msg) func registerMultipleChoiceMarketWithVault(
    args : MultipleChoiceRegistrationArgs
  ) : async Result.Result<MarketRegistrationResult, Text> {

    // Validate caller
    switch (tokenFactoryCanister) {
      case (null) { return #err("TokenFactory canister not set") };
      case (?factory) {
        if (msg.caller != factory) {
          return #err("Only TokenFactory can register markets");
        };
      };
    };

    // Validate base arguments
    let baseValidation = validateBaseArgs(args.base);
    switch (baseValidation) {
      case (#err(error)) { return #err(error) };
      case (#ok()) {};
    };

    // Validate outcomes
    if (args.outcomes.size() < 2) {
      return #err("Multiple choice market must have at least 2 outcomes");
    };

    if (args.outcomes.size() > 50) {
      return #err("Too many outcomes (maximum 50)");
    };

    // Check for duplicate outcome names
    let outcomeNames = Array.map<(Text, TokenId), Text>(args.outcomes, func((name, _)) = name);
    if (not isUniqueTexts(outcomeNames)) {
      return #err("Outcome names must be unique");
    };

    let marketId = nextMarketId;
    nextMarketId += 1;

    // Initialize bonding curves
    let outcomeCurves = Array.map<(Text, TokenId), (Text, BondingCurveConfig)>(
      args.outcomes,
      func((name, _)) = (
        name,
        {
          basePrice = args.base.bondingCurve.basePrice;
          priceSlope = args.base.bondingCurve.priceSlope;
          currentSupply = 0;
          poolBalance = 0;
        },
      ),
    );

    let multipleChoiceConfig : MultipleChoiceConfig = {
      ledger = args.ledger;
      outcomes = args.outcomes;
      outcomeCurves = outcomeCurves;
    };

    let market : MarketState = {
      id = marketId;
      marketType = #MultipleChoice;
      question = args.base.question;
      resolver = args.base.resolver;
      expiry = args.base.expiry;
      ledger = args.ledger;
      resolved = null;
      active = true;
      totalVolumeSatoshis = 0;
      totalSupply = args.base.totalSupply;
      currentSupply = 0;
      createdAt = Nat64.fromNat(Int.abs(Time.now()));
      vaultConfig = null;
      vaultRegistered = false;
      binaryConfig = null;
      multipleChoiceConfig = ?multipleChoiceConfig;
      compoundConfig = null;
    };

    markets.put(marketId, market);

    // Request vault address from Vault Canister
    switch (vaultCanister) {
      case (null) {
        markets.delete(marketId);
        return #err("Vault canister not configured");
      };
      case (?vault) {
        let vaultActor : VaultInterface = actor (Principal.toText(vault));

        let vaultRequest : VaultSetupRequest = {
          marketId = marketId;
          marketType = #MultipleChoice;
          subjects = null;
          totalSupply = args.base.totalSupply;
        };

        switch (await vaultActor.setupMarketVault(vaultRequest)) {
          case (#err(error)) {
            markets.delete(marketId);
            return #err("Vault setup failed: " # error);
          };
          case (#ok(vaultResponse)) {
            let updatedMarket = {
              market with
              vaultConfig = ?vaultResponse.addresses;
              vaultRegistered = true;
            };
            markets.put(marketId, updatedMarket);

            #ok({
              marketId = marketId;
              vaultConfig = vaultResponse.addresses;
              setupComplete = true;
            });
          };
        };
      };
    };
  };

  // ===== COMPOUND MARKET REGISTRATION (Lines 922-1050) =====
  // ✅ CHANGES IN THIS FUNCTION

  public shared (msg) func registerCompoundMarketWithVault(
    args : CompoundRegistrationArgs
  ) : async Result.Result<MarketRegistrationResult, Text> {

    // Validate caller
    switch (tokenFactoryCanister) {
      case (null) { return #err("TokenFactory canister not set") };
      case (?factory) {
        if (msg.caller != factory) {
          return #err("Only TokenFactory can register markets");
        };
      };
    };

    // Validate base arguments
    let baseValidation = validateBaseArgs(args.base);
    switch (baseValidation) {
      case (#err(error)) { return #err(error) };
      case (#ok()) {};
    };

    // Validate subjects
    if (args.subjects.size() < 2) {
      return #err("Compound market must have at least 2 subjects");
    };

    if (args.subjects.size() > 20) {
      return #err("Too many subjects (maximum 20)");
    };

    // Check for duplicate subject names
    let subjectNames = Array.map<(Text, { yesTokenId : TokenId; noTokenId : TokenId }), Text>(args.subjects, func((name, _)) = name);
    if (not isUniqueTexts(subjectNames)) {
      return #err("Subject names must be unique");
    };

    // Validate token IDs are different for each subject
    for ((name, tokens) in args.subjects.vals()) {
      if (tokens.yesTokenId == tokens.noTokenId) {
        return #err("YES and NO token IDs must be different for subject: " # name);
      };
    };

    let marketId = nextMarketId;
    nextMarketId += 1;

    // Create subject configs for each subject
    let subjectConfigs = Array.map<(Text, { yesTokenId : TokenId; noTokenId : TokenId }), (Text, CompoundSubjectConfig)>(
      args.subjects,
      func((name, tokens)) = (
        name,
        {
          yesTokenId = tokens.yesTokenId;
          noTokenId = tokens.noTokenId;
          yesCurve = ?{
            basePrice = args.base.bondingCurve.basePrice;
            priceSlope = args.base.bondingCurve.priceSlope;
            currentSupply = 0;
            poolBalance = 0;
          };
          noCurve = ?{
            basePrice = args.base.bondingCurve.basePrice;
            priceSlope = args.base.bondingCurve.priceSlope;
            currentSupply = 0;
            poolBalance = 0;
          };
        },
      ),
    );

    let compoundConfig : CompoundConfig = {
      ledger = args.ledger;
      subjects = subjectConfigs;
    };

    let market : MarketState = {
      id = marketId;
      marketType = #Compound;
      question = args.base.question;
      resolver = args.base.resolver;
      expiry = args.base.expiry;
      ledger = args.ledger;
      resolved = null;
      active = true;
      totalVolumeSatoshis = 0;
      totalSupply = args.base.totalSupply;
      currentSupply = 0;
      createdAt = Nat64.fromNat(Int.abs(Time.now()));
      vaultConfig = null;
      vaultRegistered = false;
      binaryConfig = null;
      multipleChoiceConfig = null;
      compoundConfig = ?compoundConfig;
    };

    markets.put(marketId, market);

    // Request vault addresses from Vault Canister
    switch (vaultCanister) {
      case (null) {
        markets.delete(marketId);
        return #err("Vault canister not configured");
      };
      case (?vault) {
        let vaultActor : VaultInterface = actor (Principal.toText(vault));

        let vaultRequest : VaultSetupRequest = {
          marketId = marketId;
          marketType = #Compound;
          subjects = ?subjectNames;
          totalSupply = args.base.totalSupply;
        };

        switch (await vaultActor.setupMarketVault(vaultRequest)) {
          case (#err(error)) {
            markets.delete(marketId);
            return #err("Vault setup failed: " # error);
          };
          case (#ok(vaultResponse)) {
            let updatedMarket = {
              market with
              vaultConfig = ?vaultResponse.addresses;
              vaultRegistered = true;
            };
            markets.put(marketId, updatedMarket);

            #ok({
              marketId = marketId;
              vaultConfig = vaultResponse.addresses;
              setupComplete = true;
            });
          };
        };
      };
    };
  };

  // ===== TRADING OPERATIONS =====

  // Universal buy function for all market types
  public shared (msg) func buyTokens(
    marketId : Nat,
    tokenIdentifier : TokenIdentifier,
    amountSatoshis : Nat64,
    maxSlippage : Float,
  ) : async Result.Result<BuyResult, Text> {

    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        // Common validations
        if (not market.active) { return #err("Market not active") };
        if (market.resolved != null) { return #err("Market resolved") };
        if (Nat64.fromNat(Int.abs(Time.now())) >= market.expiry) {
          return #err("Market expired");
        };
        if (not market.vaultRegistered) { return #err("Vault not registered") };
        if (amountSatoshis == 0) {
          return #err("Amount must be greater than 0");
        };

        // Route to appropriate handler
        switch (market.marketType) {
          case (#Binary) {
            await buyBinaryTokens(market, tokenIdentifier, amountSatoshis, maxSlippage, msg.caller);
          };
          case (#MultipleChoice) {
            await buyMultipleChoiceTokens(market, tokenIdentifier, amountSatoshis, maxSlippage, msg.caller);
          };
          case (#Compound) {
            await buyCompoundTokens(market, tokenIdentifier, amountSatoshis, maxSlippage, msg.caller);
          };
        };
      };
    };
  };

  // Universal sell function - DISABLED for bonding curve parimutuel markets
  // Per target spec: "Selling is not supported in bonding curve markets.
  //   Positions are locked until market resolution.
  //   Please wait for market resolution to claim your winnings."
  public shared (msg) func sellTokens(
    marketId : Nat,
    tokenIdentifier : TokenIdentifier,
    amountTokens : Nat64,
    minPrice : Nat64,
  ) : async Result.Result<SellResult, Text> {
    #err("Selling is not supported in bonding curve markets. Positions are locked until market resolution. Please wait for market resolution to claim your winnings.");
  };

  // ===== BINARY MARKET TRADING =====

  private func buyBinaryTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountSatoshis : Nat64,
    maxSlippage : Float,
    caller : Principal,
  ) : async Result.Result<BuyResult, Text> {

    let binaryToken = switch (tokenIdentifier) {
      case (#Binary(token)) { token };
      case (_) { return #err("Invalid token identifier for binary market") };
    };

    let binaryConfig = switch (market.binaryConfig) {
      case (null) { return #err("Binary configuration missing") };
      case (?config) { config };
    };

    // Get the appropriate bonding curve and outcome key
    let (curve, outcomeKey, tokenId) = switch (binaryToken) {
      case (#YES) {
        let c = switch (binaryConfig.yesCurve) {
          case (null) { return #err("YES bonding curve not configured") };
          case (?c) { c };
        };
        (c, "YES", binaryConfig.yesTokenId);
      };
      case (#NO) {
        let c = switch (binaryConfig.noCurve) {
          case (null) { return #err("NO bonding curve not configured") };
          case (?c) { c };
        };
        (c, "NO", binaryConfig.noTokenId);
      };
    };

    // Calculate shares using bonding curve
    let sharesToReceive = calculateBondingCurveShares(curve, amountSatoshis);

    if (sharesToReceive == 0) {
      return #err("Amount too small to receive any shares");
    };

    // Calculate actual cost
    let actualCost = calculateBondingCurveCost(curve, sharesToReceive);

    // Slippage protection for bonding curves:
    // Compare expected shares (based on current supply) vs actual shares received
    // If someone front-runs, supply increases and we get fewer shares
    // maxSlippage is the max % decrease in shares we're willing to accept
    // E.g., 0.1 = 10% slippage tolerance = accept up to 10% fewer shares than quoted

    // Calculate expected average price per share
    let newSupply = curve.currentSupply + sharesToReceive;
    let newCurve = { curve with currentSupply = newSupply };
    let newPrice = calculateBondingCurvePrice(newCurve);

    // Slippage Check (Limit Price)
    if (satoshisToFloat(newPrice) > maxSlippage) {
      return #err("Price slippage too high");
    };

    // Execute financial operations - pull satoshis from user
    switch (await pullSatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier)) {
      case (#err(error)) { return #err("Failed to pull satoshis: " # error) };
      case (#ok()) {};
    };

    // Mint tokens using ICRC-151
    switch (await mintTokens(binaryConfig.ledger, tokenId, caller, sharesToReceive)) {
      case (#err(error)) {
        // Rollback: refund satoshis
        ignore await paySatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier);
        return #err("Failed to mint tokens: " # error);
      };
      case (#ok()) {};
    };

    // Update bonding curve state
    let updatedCurve : BondingCurveConfig = {
      basePrice = curve.basePrice;
      priceSlope = curve.priceSlope;
      currentSupply = newSupply;
      poolBalance = curve.poolBalance + amountSatoshis;
    };

    let updatedBinaryConfig = switch (binaryToken) {
      case (#YES) { { binaryConfig with yesCurve = ?updatedCurve } };
      case (#NO) { { binaryConfig with noCurve = ?updatedCurve } };
    };

    let updatedMarket = {
      market with
      binaryConfig = ?updatedBinaryConfig;
      totalVolumeSatoshis = market.totalVolumeSatoshis + amountSatoshis;
      currentSupply = market.currentSupply + sharesToReceive;
    };

    markets.put(market.id, updatedMarket);

    // Record Transaction
    let txId = nextTxId;
    nextTxId += 1;

    let tx : MarketTransaction = {
      txId = txId;
      marketId = market.id;
      user = caller;
      operation = #Buy;
      tokenIdentifier = tokenIdentifier;
      amount = satoshisToFloat(sharesToReceive);
      price = satoshisToFloat(newPrice);
      cost = Nat64.toNat(amountSatoshis);
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
    };

    let txList = switch (marketTransactions.get(market.id)) {
      case (null) {
        let b = Buffer.Buffer<MarketTransaction>(50);
        marketTransactions.put(market.id, b);
        b;
      };
      case (?b) { b };
    };
    txList.add(tx);

    // Update legacy holder balance for backward compatibility
    let userMap = switch (marketHolders.get(market.id)) {
      case (null) {
        let m = TrieMap.TrieMap<Principal, Float>(Principal.equal, Principal.hash);
        marketHolders.put(market.id, m);
        m;
      };
      case (?m) { m };
    };
    let currentBal = Option.get(userMap.get(caller), 0.0);
    userMap.put(caller, currentBal + satoshisToFloat(sharesToReceive));

    // NEW: Update holder position with stake tracking for parimutuel payouts
    let currentPosition = getOrCreateHolderPosition(market.id, outcomeKey, caller);
    let updatedPosition : HolderPosition = {
      shares = currentPosition.shares + sharesToReceive;
      totalPaid = currentPosition.totalPaid + amountSatoshis;
      claimed = false;
    };
    updateHolderPosition(market.id, outcomeKey, caller, updatedPosition);

    Debug.print("User " # Principal.toText(caller) # " bought " # Nat64.toText(sharesToReceive) # " " # outcomeKey # " shares for " # Nat64.toText(amountSatoshis) # " sats");

    #ok({
      tokensReceived = satoshisToFloat(sharesToReceive);
      actualCostSatoshis = amountSatoshis;
      newPrice = satoshisToFloat(newPrice);
    });
  };

  // Add this function after the buyBinaryTokens function (around line 1400)

  private func sellBinaryTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountTokens : Nat64,
    minPrice : Nat64,
    caller : Principal,
  ) : async Result.Result<SellResult, Text> {
    #err("Selling not supported. Please await market resolution.");
  };

  // ===== MULTIPLE CHOICE MARKET TRADING =====

  private func buyMultipleChoiceTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountSatoshis : Nat64,
    maxSlippage : Float,
    caller : Principal,
  ) : async Result.Result<BuyResult, Text> {

    let outcomeName = switch (tokenIdentifier) {
      case (#Outcome(name)) { name };
      case (_) {
        return #err("Invalid token identifier for multiple choice market");
      };
    };

    let config = switch (market.multipleChoiceConfig) {
      case (null) { return #err("Multiple choice configuration missing") };
      case (?config) { config };
    };

    // Find curve
    let curve = switch (Array.find<(Text, BondingCurveConfig)>(config.outcomeCurves, func((n, _)) = n == outcomeName)) {
      case (null) { return #err("Curve not found for outcome: " # outcomeName) };
      case (?(_, c)) { c };
    };

    // Calculate shares using bonding curve
    let shares = calculateBondingCurveShares(curve, amountSatoshis);
    if (shares == 0) return #err("Amount too small");

    // Calculate slippage & new price
    let currentPrice = calculateBondingCurvePrice(curve);
    let newSupply = curve.currentSupply + shares;
    let newCurve = { curve with currentSupply = newSupply };
    let newPrice = calculateBondingCurvePrice(newCurve);

    // Slippage Check (Limit Price)
    if (satoshisToFloat(newPrice) > maxSlippage) {
      return #err("Price slippage too high");
    };

    // Financials
    switch (await pullSatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier)) {
      case (#err(e)) { return #err("Failed to pull satoshis: " # e) };
      case (#ok()) {};
    };

    let tokenId = switch (getTokenIdForOutcome(config.outcomes, outcomeName)) {
      case (null) { return #err("Token ID not found") };
      case (?id) { id };
    };

    switch (await mintTokens(config.ledger, tokenId, caller, shares)) {
      case (#err(e)) {
        ignore await paySatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier);
        return #err("Failed to mint: " # e);
      };
      case (#ok()) {};
    };

    // Update State
    let updatedCurve : BondingCurveConfig = {
      curve with
      currentSupply = newSupply;
      poolBalance = curve.poolBalance + amountSatoshis;
    };

    let updatedCurves = Array.map<(Text, BondingCurveConfig), (Text, BondingCurveConfig)>(
      config.outcomeCurves,
      func((n, c)) = if (n == outcomeName) (n, updatedCurve) else (n, c),
    );

    let updatedConfig = { config with outcomeCurves = updatedCurves };
    let updatedMarket = {
      market with
      multipleChoiceConfig = ?updatedConfig;
      totalVolumeSatoshis = market.totalVolumeSatoshis + amountSatoshis;
      currentSupply = market.currentSupply + shares;
    };
    markets.put(market.id, updatedMarket);

    // Record Tx & Parimutuel Position
    recordBuyTransaction(updatedMarket, caller, tokenIdentifier, shares, amountSatoshis, newPrice);
    updateParimutuelPosition(market.id, outcomeName, caller, shares, amountSatoshis);

    #ok({
      tokensReceived = satoshisToFloat(shares);
      actualCostSatoshis = amountSatoshis;
      newPrice = satoshisToFloat(newPrice);
    });
  };

  private func sellMultipleChoiceTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountTokens : Nat64,
    minPrice : Nat64,
    caller : Principal,
  ) : async Result.Result<SellResult, Text> {
    #err("Selling not supported");
  };

  // ===== COMPOUND MARKET TRADING =====

  private func buyCompoundTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountSatoshis : Nat64,
    maxSlippage : Float,
    caller : Principal,
  ) : async Result.Result<BuyResult, Text> {

    let (subjectName, binaryToken) = switch (tokenIdentifier) {
      case (#Subject(subject, token)) { (subject, token) };
      case (_) { return #err("Invalid token identifier") };
    };

    let config = switch (market.compoundConfig) {
      case (null) { return #err("Config missing") };
      case (?c) { c };
    };

    let subjectConfig = switch (getSubjectConfig(config.subjects, subjectName)) {
      case (null) { return #err("Subject not found") };
      case (?c) { c };
    };

    // Select curve
    let curve = switch (binaryToken) {
      case (#YES) {
        switch (subjectConfig.yesCurve) {
          case (null) { return #err("YES curve missing") };
          case (?c) { c };
        };
      };
      case (#NO) {
        switch (subjectConfig.noCurve) {
          case (null) { return #err("NO curve missing") };
          case (?c) { c };
        };
      };
    };

    // Bonding Curve Calculations
    let shares = calculateBondingCurveShares(curve, amountSatoshis);
    if (shares == 0) return #err("Amount too small");

    let newSupply = curve.currentSupply + shares;
    let newCurve = { curve with currentSupply = newSupply };
    let newPrice = calculateBondingCurvePrice(newCurve);

    if (satoshisToFloat(newPrice) > maxSlippage) {
      return #err("Price slippage too high");
    };

    // Financials
    switch (await pullSatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier)) {
      case (#err(e)) { return #err("Failed to pull satoshis: " # e) };
      case (#ok()) {};
    };

    let tokenId = switch (binaryToken) {
      case (#YES) { subjectConfig.yesTokenId };
      case (#NO) { subjectConfig.noTokenId };
    };

    switch (await mintTokens(config.ledger, tokenId, caller, shares)) {
      case (#err(e)) {
        ignore await paySatoshisFromMarketVault(market.id, caller, amountSatoshis, tokenIdentifier);
        return #err("Failed to mint: " # e);
      };
      case (#ok()) {};
    };

    // Update State
    let updatedCurve : BondingCurveConfig = {
      curve with
      currentSupply = newSupply;
      poolBalance = curve.poolBalance + amountSatoshis;
    };

    let updatedSubjectConfig = switch (binaryToken) {
      case (#YES) { { subjectConfig with yesCurve = ?updatedCurve } };
      case (#NO) { { subjectConfig with noCurve = ?updatedCurve } };
    };

    let updatedSubjects = updateSubjectInCompound(config.subjects, subjectName, updatedSubjectConfig);
    let updatedConfig = { config with subjects = updatedSubjects };
    let updatedMarket = {
      market with
      compoundConfig = ?updatedConfig;
      totalVolumeSatoshis = market.totalVolumeSatoshis + amountSatoshis;
      currentSupply = market.currentSupply + shares;
    };
    markets.put(market.id, updatedMarket);

    // Record Tx & Position
    recordBuyTransaction(updatedMarket, caller, tokenIdentifier, shares, amountSatoshis, newPrice);
    updateParimutuelPosition(market.id, subjectName # "-" # (switch (binaryToken) { case (#YES) "YES"; case (#NO) "NO" }), caller, shares, amountSatoshis);

    #ok({
      tokensReceived = satoshisToFloat(shares);
      actualCostSatoshis = amountSatoshis;
      newPrice = satoshisToFloat(newPrice);
    });
  };

  private func sellCompoundTokens(
    market : MarketState,
    tokenIdentifier : TokenIdentifier,
    amountTokens : Nat64,
    minPrice : Nat64,
    caller : Principal,
  ) : async Result.Result<SellResult, Text> {
    #err("Selling not supported");
  };

  // Helper function to validate compound market token identifier
  private func validateCompoundTokenIdentifier(
    config : CompoundConfig,
    tokenIdentifier : TokenIdentifier,
  ) : Result.Result<(Text, BinaryToken), Text> {
    switch (tokenIdentifier) {
      case (#Subject((subjectName, binaryToken))) {
        // Check if subject exists in this compound market
        switch (getSubjectConfig(config.subjects, subjectName)) {
          case (null) {
            #err("Subject '" # subjectName # "' not found in this compound market");
          };
          case (?_) { #ok((subjectName, binaryToken)) };
        };
      };
      case (_) {
        #err("Token identifier must be #Subject for compound markets");
      };
    };
  };

  // Helper function to get subject price information
  private func getCompoundSubjectPrice(
    market : MarketState,
    subjectName : Text,
    binaryToken : BinaryToken,
  ) : Result.Result<Float, Text> {
    switch (market.compoundConfig) {
      case (null) { #err("Compound configuration missing") };
      case (?config) {
        switch (getSubjectConfig(config.subjects, subjectName)) {
          case (null) { #err("Subject not found: " # subjectName) };
          case (?subjectConfig) {
            let curve = switch (binaryToken) {
              case (#YES) {
                switch (subjectConfig.yesCurve) {
                  case (?c) c;
                  case (null) return #err("YES curve missing");
                };
              };
              case (#NO) {
                switch (subjectConfig.noCurve) {
                  case (?c) c;
                  case (null) return #err("NO curve missing");
                };
              };
            };
            let priceSatoshis = calculateBondingCurvePrice(curve);
            #ok(satoshisToFloat(priceSatoshis));
          };
        };
      };
    };
  };

  // Helper function to get all subject prices for a compound market
  private func getAllCompoundPrices(market : MarketState) : [(Text, Float, Float)] {
    switch (market.compoundConfig) {
      case (null) { [] };
      case (?config) {
        let defaultCurve : BondingCurveConfig = {
          basePrice = 1000;
          priceSlope = 1;
          currentSupply = 0;
          poolBalance = 0;
        };
        Array.map<(Text, CompoundSubjectConfig), (Text, Float, Float)>(
          config.subjects,
          func((subjectName, subjectConfig)) {
            let yesCurve = switch (subjectConfig.yesCurve) {
              case (?c) c;
              case (null) defaultCurve;
            };
            let noCurve = switch (subjectConfig.noCurve) {
              case (?c) c;
              case (null) defaultCurve;
            };

            let yesPrice = satoshisToFloat(calculateBondingCurvePrice(yesCurve));
            let noPrice = satoshisToFloat(calculateBondingCurvePrice(noCurve));
            (subjectName, yesPrice, noPrice);
          },
        );
      };
    };
  };

  // ===== MARKET RESOLUTION & PAYOUTS =====

  // Resolve market - only callable by designated resolver
  public shared (msg) func resolveMarket(
    marketId : Nat,
    winningOutcome : MarketResolution,
  ) : async Result.Result<(), Text> {
    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        // Validate caller is resolver
        if (not Principal.equal(msg.caller, market.resolver)) {
          return #err("Only the designated resolver can resolve this market");
        };

        // Check market has expired
        let now = Nat64.fromNat(Int.abs(Time.now()));
        if (now < market.expiry) {
          return #err("Market has not expired yet. Cannot resolve before expiry.");
        };

        // Check not already resolved
        if (market.resolved != null) {
          return #err("Market is already resolved");
        };

        // Validate resolution matches market type
        switch (market.marketType, winningOutcome) {
          case (#Binary, #Binary(_)) { /* OK */ };
          case (#MultipleChoice, #MultipleChoice(_)) { /* OK */ };
          case (#Compound, #Compound(_)) { /* OK */ };
          case (_, _) {
            return #err("Resolution type does not match market type");
          };
        };

        // Update market state
        let updatedMarket = {
          market with
          resolved = ?winningOutcome;
          active = false;
        };
        markets.put(marketId, updatedMarket);

        Debug.print("Market " # Nat.toText(marketId) # " resolved with outcome: " # debug_show (winningOutcome));

        #ok();
      };
    };
  };

  // Claim winnings - for winners after resolution
  // Payout = stake returned + (user's share % × losing pool)
  public shared (msg) func claimWinnings(
    marketId : Nat
  ) : async Result.Result<ClaimResult, Text> {
    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        // Check market is resolved
        let resolution = switch (market.resolved) {
          case (null) { return #err("Market not yet resolved") };
          case (?r) { r };
        };

        // Only handle binary markets for now
        switch (market.marketType, resolution) {
          case (#Binary, #Binary(outcome)) {
            let binaryConfig = switch (market.binaryConfig) {
              case (null) { return #err("Binary config missing") };
              case (?c) { c };
            };

            // Determine winning and losing outcome keys
            let (winningKey, losingKey) = switch (outcome) {
              case (#Yes) { ("YES", "NO") };
              case (#No) { ("NO", "YES") };
            };

            // Get user's position in winning outcome
            let userPosition = getOrCreateHolderPosition(marketId, winningKey, msg.caller);

            if (userPosition.shares == 0) {
              return #err("No winning position found. You do not hold tokens for the winning outcome.");
            };

            if (userPosition.claimed) {
              return #err("Winnings already claimed");
            };

            // Get pool balances from curves
            let winningPool = switch (binaryConfig.yesCurve, binaryConfig.noCurve, outcome) {
              case (?yesCurve, _, #Yes) { yesCurve.poolBalance };
              case (_, ?noCurve, #No) { noCurve.poolBalance };
              case (_, _, _) { return #err("Bonding curve config missing") };
            };

            let losingPool = switch (binaryConfig.yesCurve, binaryConfig.noCurve, outcome) {
              case (_, ?noCurve, #Yes) { noCurve.poolBalance };
              case (?yesCurve, _, #No) { yesCurve.poolBalance };
              case (_, _, _) { return #err("Bonding curve config missing") };
            };

            // Get total winning shares
            let totalWinningShares = switch (binaryConfig.yesCurve, binaryConfig.noCurve, outcome) {
              case (?yesCurve, _, #Yes) { yesCurve.currentSupply };
              case (_, ?noCurve, #No) { noCurve.currentSupply };
              case (_, _, _) { return #err("Bonding curve config missing") };
            };

            if (totalWinningShares == 0) {
              return #err("No winning shares exist");
            };

            // Calculate payout:
            // 1. Return user's stake (totalPaid)
            // 2. Add proportional share of losing pool
            let stakeReturned = userPosition.totalPaid;

            // winningsFromLosingPool = (userShares / totalWinningShares) × losingPool
            let userShareRatio = Nat64.toNat(userPosition.shares);
            let totalRatio = Nat64.toNat(totalWinningShares);
            let losingPoolNat = Nat64.toNat(losingPool);

            let winningsFromLosingPool = Nat64.fromNat((userShareRatio * losingPoolNat) / totalRatio);
            let totalPayout = stakeReturned + winningsFromLosingPool;

            // Burn user's tokens
            let tokenId = switch (outcome) {
              case (#Yes) { binaryConfig.yesTokenId };
              case (#No) { binaryConfig.noTokenId };
            };

            switch (await burnTokens(binaryConfig.ledger, tokenId, msg.caller, userPosition.shares)) {
              case (#err(e)) { return #err("Failed to burn tokens: " # e) };
              case (#ok()) {};
            };

            // Pay user from vault
            switch (await paySatoshisFromMarketVault(marketId, msg.caller, totalPayout, #Binary(switch (outcome) { case (#Yes) #YES; case (#No) #NO }))) {
              case (#err(e)) {
                // Rollback: re-mint tokens
                ignore await mintTokens(binaryConfig.ledger, tokenId, msg.caller, userPosition.shares);
                return #err("Failed to pay winnings: " # e);
              };
              case (#ok()) {};
            };

            // Mark position as claimed
            let updatedPosition = {
              userPosition with
              claimed = true;
              shares = 0 : Nat64;
            };
            updateHolderPosition(marketId, winningKey, msg.caller, updatedPosition);

            Debug.print("User " # Principal.toText(msg.caller) # " claimed " # Nat64.toText(totalPayout) # " sats from market " # Nat.toText(marketId));

            #ok({
              stakeReturned = stakeReturned;
              winningsFromLosingPool = winningsFromLosingPool;
              totalPayout = totalPayout;
            });
          };

          case (#MultipleChoice, #MultipleChoice(winningOutcome)) {
            let mcConfig = switch (market.multipleChoiceConfig) {
              case (null) { return #err("Multiple choice config missing") };
              case (?c) { c };
            };

            // Get user's position in winning outcome
            let userPosition = getOrCreateHolderPosition(marketId, winningOutcome, msg.caller);

            if (userPosition.shares == 0) {
              return #err("No winning position found. You do not hold tokens for the winning outcome: " # winningOutcome);
            };

            if (userPosition.claimed) {
              return #err("Winnings already claimed");
            };

            // Get winning pool and total winning shares
            let winningCurve = switch (Array.find<(Text, BondingCurveConfig)>(mcConfig.outcomeCurves, func((n, _)) = n == winningOutcome)) {
              case (null) { return #err("Winning curve not found") };
              case (?(_, c)) { c };
            };

            let winningPool = winningCurve.poolBalance;
            let totalWinningShares = winningCurve.currentSupply;

            // Calculate losing pool (sum of all other outcomes' pools)
            var losingPool : Nat64 = 0;
            for ((name, curve) in mcConfig.outcomeCurves.vals()) {
              if (name != winningOutcome) {
                losingPool += curve.poolBalance;
              };
            };

            if (totalWinningShares == 0) {
              return #err("No winning shares exist");
            };

            // Calculate payout
            let stakeReturned = userPosition.totalPaid;
            let userShareRatio = Nat64.toNat(userPosition.shares);
            let totalRatio = Nat64.toNat(totalWinningShares);
            let losingPoolNat = Nat64.toNat(losingPool);

            let winningsFromLosingPool = Nat64.fromNat((userShareRatio * losingPoolNat) / totalRatio);
            let totalPayout = stakeReturned + winningsFromLosingPool;

            // Burn user's tokens
            let tokenId = switch (getTokenIdForOutcome(mcConfig.outcomes, winningOutcome)) {
              case (null) { return #err("Token ID not found") };
              case (?id) { id };
            };

            switch (await burnTokens(mcConfig.ledger, tokenId, msg.caller, userPosition.shares)) {
              case (#err(e)) { return #err("Failed to burn tokens: " # e) };
              case (#ok()) {};
            };

            // Pay user from vault
            switch (await paySatoshisFromMarketVault(marketId, msg.caller, totalPayout, #Outcome(winningOutcome))) {
              case (#err(e)) {
                ignore await mintTokens(mcConfig.ledger, tokenId, msg.caller, userPosition.shares);
                return #err("Failed to pay winnings: " # e);
              };
              case (#ok()) {};
            };

            // Mark position as claimed
            let updatedPosition = {
              userPosition with
              claimed = true;
              shares = 0 : Nat64;
            };
            updateHolderPosition(marketId, winningOutcome, msg.caller, updatedPosition);

            Debug.print("User " # Principal.toText(msg.caller) # " claimed " # Nat64.toText(totalPayout) # " sats from MC market " # Nat.toText(marketId));

            #ok({
              stakeReturned = stakeReturned;
              winningsFromLosingPool = winningsFromLosingPool;
              totalPayout = totalPayout;
            });
          };

          case (#Compound, #Compound(subjectResults)) {
            let compoundConfig = switch (market.compoundConfig) {
              case (null) { return #err("Compound config missing") };
              case (?c) { c };
            };

            // For compound markets, we need to check each subject independently
            // User can claim winnings from each subject they bet correctly on
            var totalStakeReturned : Nat64 = 0;
            var totalWinningsFromLosingPool : Nat64 = 0;

            for ((subjectName, outcome) in subjectResults.vals()) {
              label subjectLoop {
                let winningKey = subjectName # "-" # (switch (outcome) { case (#Yes) "YES"; case (#No) "NO" });

                let userPosition = getOrCreateHolderPosition(marketId, winningKey, msg.caller);

                if (userPosition.shares == 0 or userPosition.claimed) {
                  // Skip this subject
                } else {
                  // Get subject config
                  switch (getSubjectConfig(compoundConfig.subjects, subjectName)) {
                    case (null) { /* skip */ };
                    case (?subjectConfig) {
                      // Get curves based on outcome
                      let curveData : ?(BondingCurveConfig, BondingCurveConfig, TokenId) = switch (outcome) {
                        case (#Yes) {
                          switch (subjectConfig.yesCurve, subjectConfig.noCurve) {
                            case (?wc, ?lc) {
                              ?(wc, lc, subjectConfig.yesTokenId);
                            };
                            case (_, _) { null };
                          };
                        };
                        case (#No) {
                          switch (subjectConfig.noCurve, subjectConfig.yesCurve) {
                            case (?wc, ?lc) {
                              ?(wc, lc, subjectConfig.noTokenId);
                            };
                            case (_, _) { null };
                          };
                        };
                      };

                      switch (curveData) {
                        case (null) { /* skip */ };
                        case (?(winningCurve, losingCurve, tokenId)) {
                          let totalWinningShares = winningCurve.currentSupply;
                          let losingPool = losingCurve.poolBalance;

                          if (totalWinningShares > 0) {
                            let stakeReturned = userPosition.totalPaid;
                            let userShareRatio = Nat64.toNat(userPosition.shares);
                            let totalRatio = Nat64.toNat(totalWinningShares);
                            let losingPoolNat = Nat64.toNat(losingPool);

                            let winningsFromLosingPool = Nat64.fromNat((userShareRatio * losingPoolNat) / totalRatio);
                            let subjectPayout = stakeReturned + winningsFromLosingPool;

                            // Burn tokens
                            let burnResult = await burnTokens(compoundConfig.ledger, tokenId, msg.caller, userPosition.shares);
                            switch (burnResult) {
                              case (#err(e)) { /* skip to next subject */ };
                              case (#ok()) {
                                // Pay user
                                let payTokenId = #Subject((subjectName, switch (outcome) { case (#Yes) #YES; case (#No) #NO }));
                                let payResult = await paySatoshisFromMarketVault(marketId, msg.caller, subjectPayout, payTokenId);
                                switch (payResult) {
                                  case (#err(e)) {
                                    ignore await mintTokens(compoundConfig.ledger, tokenId, msg.caller, userPosition.shares);
                                  };
                                  case (#ok()) {
                                    // Mark claimed
                                    let updatedPosition = {
                                      userPosition with
                                      claimed = true;
                                      shares = 0 : Nat64;
                                    };
                                    updateHolderPosition(marketId, winningKey, msg.caller, updatedPosition);

                                    totalStakeReturned += stakeReturned;
                                    totalWinningsFromLosingPool += winningsFromLosingPool;
                                  };
                                };
                              };
                            };
                          };
                        };
                      };
                    };
                  };
                };
              };
            };

            if (totalStakeReturned == 0 and totalWinningsFromLosingPool == 0) {
              return #err("No winning positions found for any resolved subjects");
            };

            let totalPayout = totalStakeReturned + totalWinningsFromLosingPool;
            Debug.print("User " # Principal.toText(msg.caller) # " claimed " # Nat64.toText(totalPayout) # " sats from Compound market " # Nat.toText(marketId));

            #ok({
              stakeReturned = totalStakeReturned;
              winningsFromLosingPool = totalWinningsFromLosingPool;
              totalPayout = totalPayout;
            });
          };

          case (_, _) {
            return #err("Resolution type mismatch");
          };
        };
      };
    };
  };

  // ===== QUERY FUNCTIONS =====

  public query func getMarket(marketId : Nat) : async Result.Result<MarketState, Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) { #ok(market) };
    };
  };

  public query func getAllMarkets() : async [MarketState] {
    Iter.toArray(markets.vals());
  };

  public query func getMarketsByType(marketType : MarketType) : async [MarketState] {
    let allMarkets = Iter.toArray(markets.vals());
    Array.filter<MarketState>(allMarkets, func(market) = market.marketType == marketType);
  };

  public query func getMarketPrice(marketId : Nat, tokenIdentifier : TokenIdentifier) : async Result.Result<Float, Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) {
        switch (market.marketType, tokenIdentifier) {
          case (#Binary, #Binary(binaryToken)) {
            switch (market.binaryConfig) {
              case (null) { #err("Binary config missing") };
              case (?config) {
                let curve = switch (binaryToken) {
                  case (#YES) {
                    switch (config.yesCurve) {
                      case (?c) c;
                      case (_) return #err("Curve missing");
                    };
                  };
                  case (#NO) {
                    switch (config.noCurve) {
                      case (?c) c;
                      case (_) return #err("Curve missing");
                    };
                  };
                };
                let price = satoshisToFloat(calculateBondingCurvePrice(curve));
                #ok(price);
              };
            };
          };
          case (#MultipleChoice, #Outcome(outcomeName)) {
            switch (market.multipleChoiceConfig) {
              case (null) { #err("Multiple choice config missing") };
              case (?config) {
                switch (getTokenIdForOutcome(config.outcomes, outcomeName)) {
                  case (null) return #err("Outcome not found");
                  case (_) {};
                };
                let curve = switch (Array.find<(Text, BondingCurveConfig)>(config.outcomeCurves, func((n, _)) = n == outcomeName)) {
                  case (?(_, c)) c;
                  case (null) return #err("Curve missing");
                };
                let price = satoshisToFloat(calculateBondingCurvePrice(curve));
                #ok(price);
              };
            };
          };
          case (#Compound, #Subject((subjectName, binaryToken))) {
            switch (market.compoundConfig) {
              case (null) { #err("Compound config missing") };
              case (?config) {
                switch (getSubjectConfig(config.subjects, subjectName)) {
                  case (null) { #err("Subject not found") };
                  case (?subjectConfig) {
                    let curve = switch (binaryToken) {
                      case (#YES) {
                        switch (subjectConfig.yesCurve) {
                          case (?c) c;
                          case (_) return #err("Curve missing");
                        };
                      };
                      case (#NO) {
                        switch (subjectConfig.noCurve) {
                          case (?c) c;
                          case (_) return #err("Curve missing");
                        };
                      };
                    };
                    let price = satoshisToFloat(calculateBondingCurvePrice(curve));
                    #ok(price);
                  };
                };
              };
            };
          };
          case (_, _) { #err("Token identifier does not match market type") };
        };
      };
    };
  };

  public query func getMarketLedgers(marketId : Nat) : async Result.Result<[Principal], Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) { #ok([market.ledger]) };
    };
  };

  public query func getMarketConfig(marketId : Nat) : async Result.Result<MarketConfigResponse, Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) {
        let config = switch (market.marketType) {
          case (#Binary) {
            switch (market.binaryConfig) {
              case (null) { return #err("Binary config missing") };
              case (?config) { #Binary(config) };
            };
          };
          case (#MultipleChoice) {
            switch (market.multipleChoiceConfig) {
              case (null) { return #err("Multiple choice config missing") };
              case (?config) { #MultipleChoice(config) };
            };
          };
          case (#Compound) {
            switch (market.compoundConfig) {
              case (null) { return #err("Compound config missing") };
              case (?config) { #Compound(config) };
            };
          };
        };
        #ok({ marketId = marketId; config = config });
      };
    };
  };

  public query func getVaultAddresses(marketId : Nat) : async Result.Result<VaultAddressConfig, Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) {
        switch (market.vaultConfig) {
          case (null) { #err("Vault addresses not configured") };
          case (?config) { #ok(config) };
        };
      };
    };
  };

  // Get all prices for a market (useful for market overview)
  public query func getMarketPrices(marketId : Nat) : async Result.Result<[(TokenIdentifier, Float)], Text> {
    switch (markets.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?market) {
        let prices = Buffer.Buffer<(TokenIdentifier, Float)>(10);
        let defaultCurve : BondingCurveConfig = {
          basePrice = 1000;
          priceSlope = 1;
          currentSupply = 0;
          poolBalance = 0;
        };

        switch (market.marketType) {
          case (#Binary) {
            switch (market.binaryConfig) {
              case (null) { return #err("Binary config missing") };
              case (?config) {
                let yesCurve = switch (config.yesCurve) {
                  case (?c) c;
                  case (_) defaultCurve;
                };
                let noCurve = switch (config.noCurve) {
                  case (?c) c;
                  case (_) defaultCurve;
                };

                prices.add((#Binary(#YES), satoshisToFloat(calculateBondingCurvePrice(yesCurve))));
                prices.add((#Binary(#NO), satoshisToFloat(calculateBondingCurvePrice(noCurve))));
              };
            };
          };
          case (#MultipleChoice) {
            switch (market.multipleChoiceConfig) {
              case (null) { return #err("Multiple choice config missing") };
              case (?config) {
                for ((outcomeName, _) in config.outcomes.vals()) {
                  let curve = switch (Array.find<(Text, BondingCurveConfig)>(config.outcomeCurves, func((n, _)) = n == outcomeName)) {
                    case (?(_, c)) c;
                    case (null) defaultCurve;
                  };
                  let price = satoshisToFloat(calculateBondingCurvePrice(curve));
                  prices.add((#Outcome(outcomeName), price));
                };
              };
            };
          };
          case (#Compound) {
            switch (market.compoundConfig) {
              case (null) { return #err("Compound config missing") };
              case (?config) {
                for ((subjectName, subjectConfig) in config.subjects.vals()) {
                  let yesCurve = switch (subjectConfig.yesCurve) {
                    case (?c) c;
                    case (_) defaultCurve;
                  };
                  let noCurve = switch (subjectConfig.noCurve) {
                    case (?c) c;
                    case (_) defaultCurve;
                  };

                  prices.add((#Subject((subjectName, #YES)), satoshisToFloat(calculateBondingCurvePrice(yesCurve))));
                  prices.add((#Subject((subjectName, #NO)), satoshisToFloat(calculateBondingCurvePrice(noCurve))));
                };
              };
            };
          };
        };

        #ok(Buffer.toArray(prices));
      };
    };
  };

  // ===== ADMIN FUNCTIONS =====

  public shared (msg) func deactivateMarket(marketId : Nat) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can deactivate markets");
    };

    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        let deactivatedMarket = { market with active = false };
        markets.put(marketId, deactivatedMarket);
        #ok();
      };
    };
  };

  public shared (msg) func updateMarketExpiry(marketId : Nat, newExpiry : Nat64) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can update market expiry");
    };

    switch (markets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?market) {
        if (market.resolved != null) {
          return #err("Cannot update expiry of resolved market");
        };

        if (newExpiry <= Nat64.fromNat(Int.abs(Time.now()))) {
          return #err("New expiry must be in the future");
        };

        let updatedMarket = { market with expiry = newExpiry };
        markets.put(marketId, updatedMarket);
        #ok();
      };
    };
  };

  // ===== MARKET ACTIVITY QUERIES =====

  public query func getMarketActivity(marketId : Nat) : async Result.Result<[MarketTransaction], Text> {
    switch (marketTransactions.get(marketId)) {
      case (null) { #ok([]) };
      case (?buffer) {
        // Return reversed list (newest first)
        let arr = Buffer.toArray(buffer);
        let size = arr.size();
        if (size == 0) {
          return #ok([]);
        };
        // Safe reverse using Array.tabulate
        let reversed = Array.tabulate<MarketTransaction>(
          size,
          func(i : Nat) : MarketTransaction {
            arr[size - 1 - i];
          },
        );
        #ok(reversed);
      };
    };
  };

  public query func getMarketHolders(marketId : Nat) : async Result.Result<[HolderBalance], Text> {
    switch (marketHolders.get(marketId)) {
      case (null) { #ok([]) };
      case (?userMap) {
        let holders = Buffer.Buffer<HolderBalance>(20);
        for ((user, bal) in userMap.entries()) {
          holders.add({ user = user; balance = bal });
        };

        // Sort logic omitted for speed in query, frontend should sort
        #ok(Buffer.toArray(holders));
      };
    };
  };

  // ===== PERSISTENCE =====

  system func preupgrade() {
    // Markets
    marketsEntries := Iter.toArray(markets.entries());

    // Transactions
    // Convert Buffer to Array
    var tempTxEntries : [(Nat, [MarketTransaction])] = [];
    for ((k, v) in marketTransactions.entries()) {
      tempTxEntries := Array.append(tempTxEntries, [(k, Buffer.toArray(v))]);
    };
    marketTransactionsEntries := tempTxEntries;

    // Holders
    // Flatten to [(Nat, Principal, Float)]
    var tempHolderEntries : [(Nat, Principal, Float)] = [];
    for ((mId, pMap) in marketHolders.entries()) {
      for ((p, bal) in pMap.entries()) {
        tempHolderEntries := Array.append(tempHolderEntries, [(mId, p, bal)]);
      };
    };
    marketHoldersEntries := tempHolderEntries;
  };

  system func postupgrade() {
    // Markets
    for ((k, v) in marketsEntries.vals()) {
      markets.put(k, v);
    };
    marketsEntries := [];

    // Transactions
    for ((k, v) in marketTransactionsEntries.vals()) {
      let buf = Buffer.fromArray<MarketTransaction>(v);
      marketTransactions.put(k, buf);
    };
    marketTransactionsEntries := [];

    // Holders
    for ((mId, p, bal) in marketHoldersEntries.vals()) {
      let pMap = switch (marketHolders.get(mId)) {
        case (null) {
          let m = TrieMap.TrieMap<Principal, Float>(Principal.equal, Principal.hash);
          marketHolders.put(mId, m);
          m;
        };
        case (?m) { m };
      };
      pMap.put(p, bal);
    };
    marketHoldersEntries := [];
  };

  // Helper to record buy transaction
  private func recordBuyTransaction(
    market : MarketState,
    caller : Principal,
    tokenIdentifier : TokenIdentifier,
    shares : Nat64,
    amountSatoshis : Nat64,
    newPrice : Nat64,
  ) {
    let txId = nextTxId;
    nextTxId += 1;

    let tx : MarketTransaction = {
      txId = txId;
      marketId = market.id;
      user = caller;
      operation = #Buy;
      tokenIdentifier = tokenIdentifier;
      amount = satoshisToFloat(shares);
      price = satoshisToFloat(newPrice);
      cost = Nat64.toNat(amountSatoshis);
      timestamp = Nat64.fromNat(Int.abs(Time.now()));
    };

    let txList = switch (marketTransactions.get(market.id)) {
      case (null) {
        let b = Buffer.Buffer<MarketTransaction>(50);
        marketTransactions.put(market.id, b);
        b;
      };
      case (?b) { b };
    };
    txList.add(tx);

    // Update legacy holder balance
    let userMap = switch (marketHolders.get(market.id)) {
      case (null) {
        let m = TrieMap.TrieMap<Principal, Float>(Principal.equal, Principal.hash);
        marketHolders.put(market.id, m);
        m;
      };
      case (?m) { m };
    };
    let currentBal = Option.get(userMap.get(caller), 0.0);
    userMap.put(caller, currentBal + satoshisToFloat(shares));
  };

  // Helper to update parimutuel position
  private func updateParimutuelPosition(
    marketId : Nat,
    outcomeKey : Text,
    caller : Principal,
    shares : Nat64,
    amountSatoshis : Nat64,
  ) {
    let currentPosition = getOrCreateHolderPosition(marketId, outcomeKey, caller);
    let updatedPosition : HolderPosition = {
      shares = currentPosition.shares + shares;
      totalPaid = currentPosition.totalPaid + amountSatoshis;
      claimed = false;
    };
    updateHolderPosition(marketId, outcomeKey, caller, updatedPosition);
  };
};
