import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Cycles "mo:base/ExperimentalCycles";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import Array "mo:base/Array";

persistent actor Vault {

  // ===== TYPES =====

  public type MarketId = Nat;

  // Market type enumeration
  public type MarketType = {
    #Binary;
    #MultipleChoice;
    #Compound;
  };

  // ICRC-1 and ICRC-2 Types
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

  public type TransferError = {
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

  public type Allowance = {
    allowance : Nat;
    expires_at : ?Nat64;
  };

  public type AllowanceArgs = {
    account : Account;
    spender : Account;
  };

  // ICRC-1 Ledger Interface
  public type ICRC1Interface = actor {
    icrc1_transfer : (TransferArgs) -> async (TransferResult);
    icrc1_balance_of : (Account) -> async (Nat);
    icrc1_fee : () -> async (Nat);
    icrc2_transfer_from : (TransferFromArgs) -> async (TransferResult);
    icrc2_allowance : (AllowanceArgs) -> async (Allowance);
  };

  // Enhanced market information
  public type MarketInfo = {
    id : MarketId;
    marketType : ?MarketType;
    subaccount : [Nat8];
    balance : Nat;
    totalDeposited : Nat;
    totalWithdrawn : Nat;
    active : Bool;
    registrationTime : ?Nat64;
    deactivationTime : ?Nat64;
  };

  // Market statistics tracking
  public type MarketStats = {
    totalDeposited : Nat;
    totalWithdrawn : Nat;
    transactionCount : Nat;
    lastActivity : ?Nat64;
  };

  // Transaction record for audit trail
  public type TransactionRecord = {
    marketId : MarketId;
    operation : TransactionType;
    user : Principal;
    amount : Nat;
    blockIndex : ?Nat;
    timestamp : Nat64;
    memo : ?Text;
  };

  public type TransactionType = {
    #Deposit;
    #Withdrawal;
  };

  // ===== STATE =====

  // Market subaccounts storage
  stable var marketAccountsEntries : [(MarketId, [Nat8])] = [];
  private transient var marketAccounts : TrieMap.TrieMap<MarketId, [Nat8]> = TrieMap.TrieMap<MarketId, [Nat8]>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Market type tracking
  stable var marketTypesEntries : [(MarketId, MarketType)] = [];
  private transient var marketTypes : TrieMap.TrieMap<MarketId, MarketType> = TrieMap.TrieMap<MarketId, MarketType>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Enhanced market statistics
  stable var marketStatsEntries : [(MarketId, MarketStats)] = [];
  private transient var marketStats : TrieMap.TrieMap<MarketId, MarketStats> = TrieMap.TrieMap<MarketId, MarketStats>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Active markets tracking
  stable var activeMarketsEntries : [(MarketId, Bool)] = [];
  private transient var activeMarkets : TrieMap.TrieMap<MarketId, Bool> = TrieMap.TrieMap<MarketId, Bool>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Market registration timestamps
  stable var registrationTimesEntries : [(MarketId, Nat64)] = [];
  private transient var registrationTimes : TrieMap.TrieMap<MarketId, Nat64> = TrieMap.TrieMap<MarketId, Nat64>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Market deactivation timestamps
  stable var deactivationTimesEntries : [(MarketId, Nat64)] = [];
  private transient var deactivationTimes : TrieMap.TrieMap<MarketId, Nat64> = TrieMap.TrieMap<MarketId, Nat64>(Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

  // Configuration
  private stable var marketsCanister : ?Principal = null;
  private stable var ckbtcLedger : ?Principal = null;
  private stable var ckbtcFee : Nat = 10; // Default ckBTC fee in satoshis

  // System statistics
  private stable var totalMarketsRegistered : Nat = 0;
  private stable var totalTransactions : Nat = 0;
  private stable var totalVolumeDeposited : Nat = 0;
  private stable var totalVolumeWithdrawn : Nat = 0;

  // ===== INITIALIZATION =====

  public shared (msg) func initialize(markets : Principal, ledger : Principal) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can initialize");
    };

    marketsCanister := ?markets;
    ckbtcLedger := ?ledger;

    // Get actual fee from ledger
    try {
      let ledgerActor : ICRC1Interface = actor (Principal.toText(ledger));
      ckbtcFee := await ledgerActor.icrc1_fee();
      Debug.print("Vault initialized with ckBTC fee: " # Nat.toText(ckbtcFee));
    } catch (error) {
      Debug.print("Warning: Could not fetch fee from ledger, using default: " # Nat.toText(ckbtcFee));
    };

    Debug.print("Vault initialized - Markets: " # Principal.toText(markets) # ", Ledger: " # Principal.toText(ledger));
    #ok();
  };

  // ===== SUBACCOUNT MANAGEMENT =====

  private func deriveSubaccount(marketId : MarketId) : [Nat8] {
    // Create a 32-byte subaccount from market ID
    // Format: [0, 0, ..., marketId_bytes (big-endian)]
    let buffer = Buffer.Buffer<Nat8>(32);

    // Fill with zeros
    for (i in Iter.range(0, 27)) {
      buffer.add(0);
    };

    // Add market ID as big-endian 4-byte integer
    let marketIdNat32 = Nat32.fromNat(marketId % (2 ** 32));
    let byte0 = Nat8.fromNat(Nat32.toNat((marketIdNat32 >> 24) & 0xFF));
    let byte1 = Nat8.fromNat(Nat32.toNat((marketIdNat32 >> 16) & 0xFF));
    let byte2 = Nat8.fromNat(Nat32.toNat((marketIdNat32 >> 8) & 0xFF));
    let byte3 = Nat8.fromNat(Nat32.toNat(marketIdNat32 & 0xFF));

    buffer.add(byte0);
    buffer.add(byte1);
    buffer.add(byte2);
    buffer.add(byte3);

    Buffer.toArray(buffer);
  };

  private func getVaultAccount(subaccount : [Nat8]) : Account {
    {
      owner = Principal.fromActor(Vault);
      subaccount = ?subaccount;
    };
  };

  // ===== MARKET REGISTRATION =====

  public shared (msg) func registerMarket(marketId : MarketId, marketType : MarketType) : async Result.Result<(), Text> {
    // Only Markets canister can register
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can register markets");
        };
      };
    };

    // Check if already registered
    switch (marketAccounts.get(marketId)) {
      case (?_) { return #err("Market already registered") };
      case (null) {};
    };

    // Derive and store subaccount
    let subaccount = deriveSubaccount(marketId);
    let timestamp = Nat64.fromNat(Int.abs(Time.now()));

    marketAccounts.put(marketId, subaccount);
    marketTypes.put(marketId, marketType);
    marketStats.put(
      marketId,
      {
        totalDeposited = 0;
        totalWithdrawn = 0;
        transactionCount = 0;
        lastActivity = ?timestamp;
      },
    );
    activeMarkets.put(marketId, true);
    registrationTimes.put(marketId, timestamp);

    // Update system statistics
    totalMarketsRegistered += 1;

    Debug.print("Registered " # debug_show (marketType) # " market " # Nat.toText(marketId) # " with subaccount");
    #ok();
  };

  // Enhanced registration with validation
  public shared (msg) func registerMarketWithValidation(
    marketId : MarketId,
    marketType : MarketType,
    expectedSupply : ?Nat,
  ) : async Result.Result<{ subaccount : [Nat8]; timestamp : Nat64 }, Text> {
    // Only Markets canister can register
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can register markets");
        };
      };
    };

    // Validate market ID
    if (marketId == 0) {
      return #err("Market ID cannot be zero");
    };

    // Check if already registered
    switch (marketAccounts.get(marketId)) {
      case (?_) { return #err("Market already registered") };
      case (null) {};
    };

    // Derive and store subaccount
    let subaccount = deriveSubaccount(marketId);
    let timestamp = Nat64.fromNat(Int.abs(Time.now()));

    marketAccounts.put(marketId, subaccount);
    marketTypes.put(marketId, marketType);
    marketStats.put(
      marketId,
      {
        totalDeposited = 0;
        totalWithdrawn = 0;
        transactionCount = 0;
        lastActivity = ?timestamp;
      },
    );
    activeMarkets.put(marketId, true);
    registrationTimes.put(marketId, timestamp);

    totalMarketsRegistered += 1;

    Debug.print(
      "Registered " # debug_show (marketType) # " market " # Nat.toText(marketId) #
      " with expected supply: " # debug_show (expectedSupply)
    );

    #ok({ subaccount = subaccount; timestamp = timestamp });
  };

  // ===== ADD THIS TO YOUR VAULT.MO =====
  // Place this AFTER the "MARKET REGISTRATION" section (after line ~200)

  // Types needed (add to types section if not present)
  public type VaultSetupRequest = {
    marketId : Nat;
    marketType : MarketType;
    subjects : ?[Text];
    totalSupply : Nat64;
  };

  public type VaultSetupResponse = {
    addresses : VaultAddressConfig;
    setupTimestamp : Nat64;
    status : VaultStatus;
  };

  public type VaultAddressConfig = {
    #Binary : {
      marketVault : Principal;
    };
    #MultipleChoice : {
      marketVault : Principal;
    };
    #Compound : {
      subjectVaults : [(Text, Principal)];
    };
  };

  public type VaultStatus = {
    #Active;
    #Paused;
    #Resolved;
    #PayoutComplete;
  };

  // ===== NEW METHOD: setupMarketVault =====

  public shared (msg) func setupMarketVault(
    request : VaultSetupRequest
  ) : async Result.Result<VaultSetupResponse, Text> {

    // Only Markets canister can call this
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can setup vaults");
        };
      };
    };

    // Check if market is already registered
    switch (marketAccounts.get(request.marketId)) {
      case (?_) { return #err("Market already has vault setup") };
      case (null) {};
    };

    // Derive subaccount for this market
    let subaccount = deriveSubaccount(request.marketId);
    let timestamp = Nat64.fromNat(Int.abs(Time.now()));
    let vaultAddress = Principal.fromActor(Vault);

    // Register the market
    marketAccounts.put(request.marketId, subaccount);
    marketTypes.put(request.marketId, request.marketType);
    marketStats.put(
      request.marketId,
      {
        totalDeposited = 0;
        totalWithdrawn = 0;
        transactionCount = 0;
        lastActivity = ?timestamp;
      },
    );
    activeMarkets.put(request.marketId, true);
    registrationTimes.put(request.marketId, timestamp);

    totalMarketsRegistered += 1;

    // Build vault address configuration based on market type
    let vaultConfig : VaultAddressConfig = switch (request.marketType) {
      case (#Binary) {
        #Binary({
          marketVault = vaultAddress;
        });
      };
      case (#MultipleChoice) {
        #MultipleChoice({
          marketVault = vaultAddress;
        });
      };
      case (#Compound) {
        // For compound markets, create one vault per subject
        // In this implementation, we use the same vault but track separately
        switch (request.subjects) {
          case (null) {
            return #err("Compound markets require subjects list");
          };
          case (?subjects) {
            if (subjects.size() == 0) {
              return #err("Compound markets need at least one subject");
            };

            // Map each subject to the vault address
            let subjectVaults = Array.map<Text, (Text, Principal)>(
              subjects,
              func(subject) = (subject, vaultAddress),
            );

            #Compound({
              subjectVaults = subjectVaults;
            });
          };
        };
      };
    };

    Debug.print(
      "Setup vault for market " # Nat.toText(request.marketId) #
      " (" # debug_show (request.marketType) # ")"
    );

    let response : VaultSetupResponse = {
      addresses = vaultConfig;
      setupTimestamp = timestamp;
      status = #Active;
    };

    #ok(response);
  };

  // ===== FUND MOVEMENT =====

  public shared (msg) func pull_ckbtc(marketId : MarketId, user : Principal, amount : Nat) : async Result.Result<{ blockIndex : Nat; timestamp : Nat64 }, Text> {
    // Only Markets canister can call this
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can pull ckBTC");
        };
      };
    };

    // Check if market is registered and active
    switch (marketAccounts.get(marketId)) {
      case (null) { return #err("Market not registered") };
      case (?subaccount) {
        switch (activeMarkets.get(marketId)) {
          case (?false) { return #err("Market is not active") };
          case _ {};
        };

        // Validate amount
        if (amount == 0) {
          return #err("Amount must be greater than zero");
        };

        // Check ledger is set
        switch (ckbtcLedger) {
          case (null) { return #err("ckBTC ledger not set") };
          case (?ledger) {
            let ledgerActor : ICRC1Interface = actor (Principal.toText(ledger));
            let timestamp = Nat64.fromNat(Int.abs(Time.now()));

            // Prepare accounts
            let userAccount = { owner = user; subaccount = null };
            let vaultAccount = getVaultAccount(subaccount);

            // Check user's allowance to vault
            try {
              let allowanceArgs = {
                account = userAccount;
                spender = {
                  owner = Principal.fromActor(Vault);
                  subaccount = null;
                };
              };
              let allowance = await ledgerActor.icrc2_allowance(allowanceArgs);

              if (allowance.allowance < amount + ckbtcFee) {
                return #err("Insufficient allowance. Required: " # Nat.toText(amount + ckbtcFee) # ", Available: " # Nat.toText(allowance.allowance));
              };
            } catch (error) {
              return #err("Failed to check allowance");
            };

            // Execute transfer_from
            let transferArgs : TransferFromArgs = {
              spender_subaccount = null;
              from = userAccount;
              to = vaultAccount;
              amount = amount;
              fee = ?ckbtcFee;
              memo = ?Blob.toArray(Text.encodeUtf8("Market deposit: " # Nat.toText(marketId)));
              created_at_time = ?timestamp;
            };

            try {
              switch (await ledgerActor.icrc2_transfer_from(transferArgs)) {
                case (#Ok(blockIndex)) {
                  // Update market statistics
                  switch (marketStats.get(marketId)) {
                    case (?stats) {
                      let updatedStats = {
                        totalDeposited = stats.totalDeposited + amount;
                        totalWithdrawn = stats.totalWithdrawn;
                        transactionCount = stats.transactionCount + 1;
                        lastActivity = ?timestamp;
                      };
                      marketStats.put(marketId, updatedStats);
                    };
                    case (null) {
                      let newStats = {
                        totalDeposited = amount;
                        totalWithdrawn = 0;
                        transactionCount = 1;
                        lastActivity = ?timestamp;
                      };
                      marketStats.put(marketId, newStats);
                    };
                  };

                  // Update system statistics
                  totalTransactions += 1;
                  totalVolumeDeposited += amount;

                  Debug.print(
                    "Pulled " # Nat.toText(amount) # " ckBTC from " # Principal.toText(user) #
                    " to market " # Nat.toText(marketId) # " (block: " # Nat.toText(blockIndex) # ")"
                  );

                  #ok({ blockIndex = blockIndex; timestamp = timestamp });
                };
                case (#Err(error)) {
                  let errorMsg = switch (error) {
                    case (#InsufficientFunds(details)) {
                      "Insufficient funds: " # Nat.toText(details.balance);
                    };
                    case (#InsufficientAllowance(details)) {
                      "Insufficient allowance: " # Nat.toText(details.allowance);
                    };
                    case (#BadFee(details)) {
                      "Bad fee. Expected: " # Nat.toText(details.expected_fee);
                    };
                    case (#TooOld) { "Transaction too old" };
                    case (#CreatedInFuture(_)) {
                      "Transaction created in future";
                    };
                    case (#TemporarilyUnavailable) {
                      "Service temporarily unavailable";
                    };
                    case (#GenericError(details)) {
                      "Error " # Nat.toText(details.error_code) # ": " # details.message;
                    };
                    case (#Duplicate(details)) {
                      "Duplicate transaction: " # Nat.toText(details.duplicate_of);
                    };
                    case _ { "Unknown transfer error" };
                  };
                  #err("Transfer failed: " # errorMsg);
                };
              };
            } catch (error) {
              #err("Failed to execute transfer_from: ");
            };
          };
        };
      };
    };
  };

  public shared (msg) func pay_ckbtc(marketId : MarketId, user : Principal, amount : Nat) : async Result.Result<{ blockIndex : Nat; timestamp : Nat64 }, Text> {
    // Only Markets canister can call this
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can pay ckBTC");
        };
      };
    };

    // Check if market is registered
    switch (marketAccounts.get(marketId)) {
      case (null) { return #err("Market not registered") };
      case (?subaccount) {
        // Validate amount
        if (amount == 0) {
          return #err("Amount must be greater than zero");
        };

        // Check ledger is set
        switch (ckbtcLedger) {
          case (null) { return #err("ckBTC ledger not set") };
          case (?ledger) {
            let ledgerActor : ICRC1Interface = actor (Principal.toText(ledger));
            let timestamp = Nat64.fromNat(Int.abs(Time.now()));

            // Prepare accounts
            let userAccount = { owner = user; subaccount = null };
            let vaultAccount = getVaultAccount(subaccount);

            // Check vault balance
            try {
              let balance = await ledgerActor.icrc1_balance_of(vaultAccount);
              if (balance < amount) {
                return #err("Insufficient vault balance. Required: " # Nat.toText(amount) # ", Available: " # Nat.toText(balance));
              };
            } catch (error) {
              return #err("Failed to check vault balance: ");
            };

            if (amount <= ckbtcFee) {
              return #err("Payout amount too small to cover fees");
            };
            let netAmount = amount - ckbtcFee;

            // Execute transfer
            let transferArgs : TransferArgs = {
              from_subaccount = ?subaccount;
              to = userAccount;
              amount = netAmount;
              fee = ?ckbtcFee;
              memo = ?Blob.toArray(Text.encodeUtf8("Market payout: " # Nat.toText(marketId)));
              created_at_time = ?timestamp;
            };

            try {
              switch (await ledgerActor.icrc1_transfer(transferArgs)) {
                case (#Ok(blockIndex)) {
                  // Update market statistics
                  switch (marketStats.get(marketId)) {
                    case (?stats) {
                      let updatedStats = {
                        totalDeposited = stats.totalDeposited;
                        totalWithdrawn = stats.totalWithdrawn + amount;
                        transactionCount = stats.transactionCount + 1;
                        lastActivity = ?timestamp;
                      };
                      marketStats.put(marketId, updatedStats);
                    };
                    case (null) {
                      let newStats = {
                        totalDeposited = 0;
                        totalWithdrawn = amount;
                        transactionCount = 1;
                        lastActivity = ?timestamp;
                      };
                      marketStats.put(marketId, newStats);
                    };
                  };

                  // Update system statistics
                  totalTransactions += 1;
                  totalVolumeWithdrawn += amount;

                  Debug.print(
                    "Paid " # Nat.toText(amount) # " ckBTC from market " # Nat.toText(marketId) #
                    " to " # Principal.toText(user) # " (block: " # Nat.toText(blockIndex) # ")"
                  );

                  #ok({ blockIndex = blockIndex; timestamp = timestamp });
                };
                case (#Err(error)) {
                  let errorMsg = switch (error) {
                    case (#InsufficientFunds(details)) {
                      "Insufficient funds: " # Nat.toText(details.balance);
                    };
                    case (#BadFee(details)) {
                      "Bad fee. Expected: " # Nat.toText(details.expected_fee);
                    };
                    case (#TooOld) { "Transaction too old" };
                    case (#CreatedInFuture(_)) {
                      "Transaction created in future";
                    };
                    case (#TemporarilyUnavailable) {
                      "Service temporarily unavailable";
                    };
                    case (#GenericError(details)) {
                      "Error " # Nat.toText(details.error_code) # ": " # details.message;
                    };
                    case (#Duplicate(details)) {
                      "Duplicate transaction: " # Nat.toText(details.duplicate_of);
                    };
                    case _ { "Unknown transfer error" };
                  };
                  #err("Transfer failed: " # errorMsg);
                };
              };
            } catch (error) {
              #err("Failed to execute transfer: ");
            };
          };
        };
      };
    };
  };

  // ===== BALANCE QUERIES =====

  public query func get_balance(marketId : MarketId) : async Result.Result<Nat, Text> {
    switch (marketAccounts.get(marketId)) {
      case (null) { #err("Market not registered") };
      case (?subaccount) {
        switch (ckbtcLedger) {
          case (null) { #err("ckBTC ledger not set") };
          case (?ledger) {
            // Note: This is a query call, so we can't make async calls to other canisters
            // Return 0 for now - use get_balance_async for actual balance
            #ok(0);
          };
        };
      };
    };
  };

  public func get_balance_async(marketId : MarketId) : async Result.Result<Nat, Text> {
    switch (marketAccounts.get(marketId)) {
      case (null) { #err("Market not registered") };
      case (?subaccount) {
        switch (ckbtcLedger) {
          case (null) { #err("ckBTC ledger not set") };
          case (?ledger) {
            try {
              let ledgerActor : ICRC1Interface = actor (Principal.toText(ledger));
              let vaultAccount = getVaultAccount(subaccount);
              let balance = await ledgerActor.icrc1_balance_of(vaultAccount);
              #ok(balance);
            } catch (error) {
              #err("Failed to get balance: ");
            };
          };
        };
      };
    };
  };

  // Batch balance checking for multiple markets
  public func get_balances_batch(marketIds : [MarketId]) : async [(MarketId, Result.Result<Nat, Text>)] {
    let results = Buffer.Buffer<(MarketId, Result.Result<Nat, Text>)>(marketIds.size());

    for (marketId in marketIds.vals()) {
      let balanceResult = await get_balance_async(marketId);
      results.add((marketId, balanceResult));
    };

    Buffer.toArray(results);
  };

  // ===== MARKET MANAGEMENT =====

  public shared (msg) func deactivateMarket(marketId : MarketId) : async Result.Result<Nat64, Text> {
    // Only Markets canister can deactivate
    switch (marketsCanister) {
      case (null) { return #err("Markets canister not set") };
      case (?markets) {
        if (msg.caller != markets) {
          return #err("Only Markets canister can deactivate markets");
        };
      };
    };

    switch (activeMarkets.get(marketId)) {
      case (null) { return #err("Market not found") };
      case (?false) { return #err("Market already deactivated") };
      case (?true) {
        let timestamp = Nat64.fromNat(Int.abs(Time.now()));
        activeMarkets.put(marketId, false);
        deactivationTimes.put(marketId, timestamp);

        Debug.print("Deactivated market " # Nat.toText(marketId) # " at " # Nat64.toText(timestamp));
        #ok(timestamp);
      };
    };
  };

  public shared (msg) func reactivateMarket(marketId : MarketId) : async Result.Result<(), Text> {
    // Only controller can reactivate (emergency function)
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can reactivate markets");
    };

    switch (marketAccounts.get(marketId)) {
      case (null) { return #err("Market not registered") };
      case (?_) {
        activeMarkets.put(marketId, true);
        deactivationTimes.delete(marketId);

        Debug.print("Reactivated market " # Nat.toText(marketId));
        #ok();
      };
    };
  };

  // ===== QUERY FUNCTIONS =====

  public query func getMarketInfo(marketId : MarketId) : async Result.Result<MarketInfo, Text> {
    switch (marketAccounts.get(marketId)) {
      case (null) { #err("Market not registered") };
      case (?subaccount) {
        let stats = switch (marketStats.get(marketId)) {
          case (?s) { s };
          case (null) {
            {
              totalDeposited = 0;
              totalWithdrawn = 0;
              transactionCount = 0;
              lastActivity = null;
            };
          };
        };

        let active = switch (activeMarkets.get(marketId)) {
          case (?status) { status };
          case (null) { false };
        };

        let marketType = marketTypes.get(marketId);
        let regTime = registrationTimes.get(marketId);
        let deactivTime = deactivationTimes.get(marketId);

        #ok({
          id = marketId;
          marketType = marketType;
          subaccount = subaccount;
          balance = 0; // Would need async call to get real balance
          totalDeposited = stats.totalDeposited;
          totalWithdrawn = stats.totalWithdrawn;
          active = active;
          registrationTime = regTime;
          deactivationTime = deactivTime;
        });
      };
    };
  };

  public query func getAllMarkets() : async [MarketInfo] {
    let buffer = Buffer.Buffer<MarketInfo>(marketAccounts.size());

    for ((marketId, subaccount) in marketAccounts.entries()) {
      let stats = switch (marketStats.get(marketId)) {
        case (?s) { s };
        case (null) {
          {
            totalDeposited = 0;
            totalWithdrawn = 0;
            transactionCount = 0;
            lastActivity = null;
          };
        };
      };

      let active = switch (activeMarkets.get(marketId)) {
        case (?status) { status };
        case (null) { false };
      };

      let marketType = marketTypes.get(marketId);
      let regTime = registrationTimes.get(marketId);
      let deactivTime = deactivationTimes.get(marketId);

      buffer.add({
        id = marketId;
        marketType = marketType;
        subaccount = subaccount;
        balance = 0; // Would need async call to get real balance
        totalDeposited = stats.totalDeposited;
        totalWithdrawn = stats.totalWithdrawn;
        active = active;
        registrationTime = regTime;
        deactivationTime = deactivTime;
      });
    };

    Buffer.toArray(buffer);
  };

  // Get markets by type
  public query func getMarketsByType(marketType : MarketType) : async [MarketInfo] {
    let buffer = Buffer.Buffer<MarketInfo>(10);

    for ((marketId, mType) in marketTypes.entries()) {
      if (mType == marketType) {
        switch (getMarketInfoSync(marketId)) {
          case (?info) { buffer.add(info) };
          case (null) {};
        };
      };
    };

    Buffer.toArray(buffer);
  };

  // Get active markets only
  public query func getActiveMarkets() : async [MarketInfo] {
    let buffer = Buffer.Buffer<MarketInfo>(10);

    for ((marketId, active) in activeMarkets.entries()) {
      if (active) {
        switch (getMarketInfoSync(marketId)) {
          case (?info) { buffer.add(info) };
          case (null) {};
        };
      };
    };

    Buffer.toArray(buffer);
  };

  // Helper function for sync market info retrieval
  private func getMarketInfoSync(marketId : MarketId) : ?MarketInfo {
    switch (marketAccounts.get(marketId)) {
      case (null) { null };
      case (?subaccount) {
        let stats = switch (marketStats.get(marketId)) {
          case (?s) { s };
          case (null) {
            {
              totalDeposited = 0;
              totalWithdrawn = 0;
              transactionCount = 0;
              lastActivity = null;
            };
          };
        };

        let active = switch (activeMarkets.get(marketId)) {
          case (?status) { status };
          case (null) { false };
        };

        let marketType = marketTypes.get(marketId);
        let regTime = registrationTimes.get(marketId);
        let deactivTime = deactivationTimes.get(marketId);

        ?{
          id = marketId;
          marketType = marketType;
          subaccount = subaccount;
          balance = 0;
          totalDeposited = stats.totalDeposited;
          totalWithdrawn = stats.totalWithdrawn;
          active = active;
          registrationTime = regTime;
          deactivationTime = deactivTime;
        };
      };
    };
  };

  public query func getConfiguration() : async {
    marketsCanister : ?Principal;
    ckbtcLedger : ?Principal;
    ckbtcFee : Nat;
    totalMarkets : Nat;
    totalTransactions : Nat;
    totalVolumeDeposited : Nat;
    totalVolumeWithdrawn : Nat;
  } {
    {
      marketsCanister = marketsCanister;
      ckbtcLedger = ckbtcLedger;
      ckbtcFee = ckbtcFee;
      totalMarkets = totalMarketsRegistered;
      totalTransactions = totalTransactions;
      totalVolumeDeposited = totalVolumeDeposited;
      totalVolumeWithdrawn = totalVolumeWithdrawn;
    };
  };

  // Get system statistics
  public query func getSystemStats() : async {
    totalMarkets : Nat;
    activeMarkets : Nat;
    totalTransactions : Nat;
    totalVolumeDeposited : Nat;
    totalVolumeWithdrawn : Nat;
    marketTypeBreakdown : [(MarketType, Nat)];
  } {
    // Count active markets
    var activeCount = 0;
    for ((_, active) in activeMarkets.entries()) {
      if (active) { activeCount += 1 };
    };

    // Count markets by type
    let binaryCount = marketTypes.vals() |> Iter.filter(_, func(t : MarketType) : Bool = t == #Binary) |> Iter.size(_);
    let multipleChoiceCount = marketTypes.vals() |> Iter.filter(_, func(t : MarketType) : Bool = t == #MultipleChoice) |> Iter.size(_);
    let compoundCount = marketTypes.vals() |> Iter.filter(_, func(t : MarketType) : Bool = t == #Compound) |> Iter.size(_);

    {
      totalMarkets = totalMarketsRegistered;
      activeMarkets = activeCount;
      totalTransactions = totalTransactions;
      totalVolumeDeposited = totalVolumeDeposited;
      totalVolumeWithdrawn = totalVolumeWithdrawn;
      marketTypeBreakdown = [
        (#Binary, binaryCount),
        (#MultipleChoice, multipleChoiceCount),
        (#Compound, compoundCount),
      ];
    };
  };

  // ===== ADMIN FUNCTIONS =====

  public shared (msg) func updateConfiguration(markets : ?Principal, ledger : ?Principal) : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can update configuration");
    };

    switch (markets) {
      case (?m) {
        marketsCanister := ?m;
        Debug.print("Updated Markets canister to: " # Principal.toText(m));
      };
      case (null) {};
    };

    switch (ledger) {
      case (?l) {
        ckbtcLedger := ?l;
        Debug.print("Updated ckBTC ledger to: " # Principal.toText(l));

        // Update fee
        try {
          let ledgerActor : ICRC1Interface = actor (Principal.toText(l));
          let newFee = await ledgerActor.icrc1_fee();
          ckbtcFee := newFee;
          Debug.print("Updated ckBTC fee to: " # Nat.toText(newFee));
        } catch (error) {
          Debug.print("Warning: Could not fetch fee from new ledger");
        };
      };
      case (null) {};
    };

    #ok();
  };

  // Emergency functions for controller
  public shared (msg) func emergencyPause() : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can emergency pause");
    };

    // Deactivate all active markets
    for ((marketId, active) in activeMarkets.entries()) {
      if (active) {
        activeMarkets.put(marketId, false);
        let timestamp = Nat64.fromNat(Int.abs(Time.now()));
        deactivationTimes.put(marketId, timestamp);
      };
    };

    Debug.print("Emergency pause activated - all markets deactivated");
    #ok();
  };

  public shared (msg) func emergencyResume() : async Result.Result<(), Text> {
    if (not Principal.isController(msg.caller)) {
      return #err("Only controller can emergency resume");
    };

    // This function doesn't automatically reactivate markets
    // Markets must be manually reactivated using reactivateMarket
    Debug.print("Emergency resume called - use reactivateMarket for individual markets");
    #ok();
  };

  // Get detailed market statistics
  public query func getMarketStats(marketId : MarketId) : async Result.Result<MarketStats, Text> {
    switch (marketStats.get(marketId)) {
      case (null) { #err("Market not found") };
      case (?stats) { #ok(stats) };
    };
  };

  // Validate market exists and is accessible
  public query func validateMarket(marketId : MarketId) : async Result.Result<{ exists : Bool; active : Bool; marketType : ?MarketType; subaccount : ?[Nat8] }, Text> {
    let exists = switch (marketAccounts.get(marketId)) {
      case (null) { false };
      case (?_) { true };
    };

    if (not exists) {
      return #err("Market does not exist");
    };

    let active = switch (activeMarkets.get(marketId)) {
      case (?status) { status };
      case (null) { false };
    };

    let marketType = marketTypes.get(marketId);
    let subaccount = marketAccounts.get(marketId);

    #ok({
      exists = exists;
      active = active;
      marketType = marketType;
      subaccount = subaccount;
    });
  };

  // ===== AUDIT AND MONITORING =====

  // Get vault account for external monitoring
  public query func getMarketVaultAccount(marketId : MarketId) : async Result.Result<Account, Text> {
    switch (marketAccounts.get(marketId)) {
      case (null) { #err("Market not registered") };
      case (?subaccount) {
        #ok({
          owner = Principal.fromActor(Vault);
          subaccount = ?subaccount;
        });
      };
    };
  };

  // Check if user has sufficient allowance
  public func checkUserAllowance(user : Principal, amount : Nat) : async Result.Result<{ allowance : Nat; sufficient : Bool; required : Nat }, Text> {
    switch (ckbtcLedger) {
      case (null) { return #err("ckBTC ledger not set") };
      case (?ledger) {
        try {
          let ledgerActor : ICRC1Interface = actor (Principal.toText(ledger));
          let allowanceArgs = {
            account = { owner = user; subaccount = null };
            spender = { owner = Principal.fromActor(Vault); subaccount = null };
          };
          let allowanceResult = await ledgerActor.icrc2_allowance(allowanceArgs);
          let required = amount + ckbtcFee;

          #ok({
            allowance = allowanceResult.allowance;
            sufficient = allowanceResult.allowance >= required;
            required = required;
          });
        } catch (error) {
          #err("Failed to check allowance");
        };
      };
    };
  };

  // ===== SYSTEM FUNCTIONS =====

  system func preupgrade() {
    marketAccountsEntries := Iter.toArray(marketAccounts.entries());
    marketTypesEntries := Iter.toArray(marketTypes.entries());
    marketStatsEntries := Iter.toArray(marketStats.entries());
    activeMarketsEntries := Iter.toArray(activeMarkets.entries());
    registrationTimesEntries := Iter.toArray(registrationTimes.entries());
    deactivationTimesEntries := Iter.toArray(deactivationTimes.entries());

    Debug.print("Vault pre-upgrade: saved " # Nat.toText(marketAccountsEntries.size()) # " markets");
  };

  system func postupgrade() {
    marketAccounts := TrieMap.fromEntries(marketAccountsEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
    marketTypes := TrieMap.fromEntries(marketTypesEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
    marketStats := TrieMap.fromEntries(marketStatsEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
    activeMarkets := TrieMap.fromEntries(activeMarketsEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
    registrationTimes := TrieMap.fromEntries(registrationTimesEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });
    deactivationTimes := TrieMap.fromEntries(deactivationTimesEntries.vals(), Nat.equal, func(n : Nat) : Nat32 { Nat32.fromNat(n) });

    marketAccountsEntries := [];
    marketTypesEntries := [];
    marketStatsEntries := [];
    activeMarketsEntries := [];
    registrationTimesEntries := [];
    deactivationTimesEntries := [];

    Debug.print("Vault post-upgrade: restored " # Nat.toText(marketAccounts.size()) # " markets");
  };
};
