import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Text "mo:base/Text";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Array "mo:base/Array";
import Char "mo:base/Char";
import TrieMap "mo:base/TrieMap";
import Cycles "mo:base/ExperimentalCycles";
import Float "mo:base/Float";

persistent actor TokenFactory {
  // ===== ICRC-151 TYPES =====

  public type Account = {
    owner : Principal;
    subaccount : ?Blob;
  };

  public type TokenId = Blob; // ICRC-151 uses Blob as token identifier

  // Custom Result type to match Candid's uppercase Ok/Err
  public type CandidResult<Ok, Err> = {
    #Ok : Ok;
    #Err : Err;
  };

  // ICRC-151 Ledger Interface (from the candid file)
  public type ICRC151Interface = actor {
    create_token : (
      name : Text,
      symbol : Text,
      decimals : Nat8,
      max_supply : ?Nat,
      fee : ?Nat,
      logo : ?Text,
      description : ?Text
    ) -> async CandidResult<TokenId, Text>;

    mint_tokens : (
      token_id : TokenId,
      to : Account,
      amount : Nat,
      memo : ?Blob
    ) -> async CandidResult<Nat64, Text>;

    get_balance : (
      token_id : TokenId,
      account : Account
    ) -> async CandidResult<Nat, Text>; // Note: Error type is actually QueryError in candid, but we'll treat as Text for now or need to define QueryError

    get_token_metadata : (
      token_id : TokenId
    ) -> async CandidResult<{
      name : Text;
      symbol : Text;
      decimals : Nat8;
      fee : Nat;
      total_supply : Nat;
      logo : ?Text;
      description : ?Text;
    }, Text>; // Error is QueryError

    list_tokens : () -> async [TokenId];
  };

  // ===== MARKET TYPES =====

  public type MarketId = Nat;

  public type Category = {
    #Runes;
    #Stocks;
    #Political;
    #Sports;
    #Entertainment;
    #Technology;
    #Crypto;
    #AI;
  };

  public type Tag = {
    #web2;
    #AI;
    #Sports;
    #Crypto;
    #Political;
    #Technology;
    #Entertainment;
    #Runes;
  };

  public type ImageData = {
    #ImageUrl : Text;
    #ImageBlob : Blob;
  };

  public type MarketMetadata = {
    title : Text;
    description : Text;
    category : Category;
    creator : Principal;
    image : ImageData;
    tags : [Tag];
    bettingCloseTime : Int;
    expirationTime : Int;
    resolutionLink : Text;
    resolutionDescription : Text;
    created_at : Int;
  };

  public type MarketType = {
    #Binary;
    #MultipleChoice : { outcomes : [Text] };
    #Compound : { subjects : [Text] };
  };

  // NEW: Single ledger with multiple token IDs
  public type BinaryTokens = {
    ledger : Principal; // Single ICRC-151 ledger
    yesTokenId : TokenId;
    noTokenId : TokenId;
  };

  public type MultipleChoiceTokens = {
    ledger : Principal; // Single ICRC-151 ledger
    outcomeTokens : [(Text, TokenId)];
  };

  public type CompoundTokens = {
    ledger : Principal; // Single ICRC-151 ledger
    subjectTokens : [(Text, { yesTokenId : TokenId; noTokenId : TokenId })];
  };

  public type MarketTokens = {
    #Binary : BinaryTokens;
    #MultipleChoice : MultipleChoiceTokens;
    #Compound : CompoundTokens;
  };

  public type MarketInfo = {
    id : MarketId;
    metadata : MarketMetadata;
    marketType : MarketType;
    tokens : MarketTokens;
  };

  // ===== MARKET CREATION ARGS =====

  public type CreateBinaryMarketArgs = {
    title : Text;
    description : Text;
    category : Category;
    image : ImageData;
    tags : [Tag];
    bettingCloseTime : Int;
    expirationTime : Int;
    resolutionLink : Text;
    resolutionDescription : Text;
  };

  public type CreateMultipleChoiceMarketArgs = {
    title : Text;
    description : Text;
    category : Category;
    image : ImageData;
    tags : [Tag];
    outcomes : [Text];
    bettingCloseTime : Int;
    expirationTime : Int;
    resolutionLink : Text;
    resolutionDescription : Text;
  };

  public type CreateCompoundMarketArgs = {
    title : Text;
    description : Text;
    category : Category;
    image : ImageData;
    tags : [Tag];
    subjects : [Text];
    bettingCloseTime : Int;
    expirationTime : Int;
    resolutionLink : Text;
    resolutionDescription : Text;
  };

  // ===== CONSTANTS =====

  private transient let DEFAULT_DECIMALS : Nat8 = 8;
  private transient let DEFAULT_FEE : Nat = 10_000;
  private transient let MAX_OUTCOMES : Nat = 20;
  private transient let MAX_SUBJECTS : Nat = 10;
  private transient let MAX_TITLE_LENGTH : Nat = 200;
  private transient let MIN_TITLE_LENGTH : Nat = 1;
  private transient let MAX_DESCRIPTION_LENGTH : Nat = 1000;
  private transient let MIN_DESCRIPTION_LENGTH : Nat = 1;
  private transient let MAX_TAGS : Nat = 5;

  // Cycle cost - only one canister per market now!
  private transient let CYCLES_PER_LEDGER : Nat = 850_000_000_000; // ~0.85T cycles

  // ===== STATE =====

  private stable var nextMarketId : MarketId = 1;
  private stable var icrc151_wasm : ?Blob = null;
  private stable var marketInfoEntries : [(MarketId, MarketInfo)] = [];
  private stable var createdLedgers : [Principal] = [];

  private transient var marketInfo = TrieMap.TrieMap<MarketId, MarketInfo>(
    Nat.equal,
    func(n : Nat) : Nat32 { Nat32.fromNat(n) },
  );

  // Management canister for creating ICRC-151 ledgers
  private transient let mgmt = actor "aaaaa-aa" : actor {
    create_canister : shared {
      settings : ?{ controllers : [Principal] };
    } -> async { canister_id : Principal };

    install_code : shared {
      canister_id : Principal;
      wasm_module : Blob;
      arg : Blob;
      mode : { #install; #reinstall; #upgrade };
    } -> async ();
  };

  // ===== INITIALIZATION =====

  system func preupgrade() {
    marketInfoEntries := Iter.toArray(marketInfo.entries());
  };

  system func postupgrade() {
    marketInfo := TrieMap.fromEntries(
      marketInfoEntries.vals(),
      Nat.equal,
      func(n : Nat) : Nat32 { Nat32.fromNat(n) },
    );
    marketInfoEntries := [];
  };

  // ===== VALIDATION FUNCTIONS =====

  private func fromCandidResult<Ok, Err>(res : CandidResult<Ok, Err>) : Result.Result<Ok, Err> {
    switch (res) {
      case (#Ok(ok)) #ok(ok);
      case (#Err(err)) #err(err);
    }
  };

  private func validateTitle(title : Text) : Bool {
    let length = Text.size(title);
    length >= MIN_TITLE_LENGTH and length <= MAX_TITLE_LENGTH;
  };

  private func validateDescription(description : Text) : Bool {
    let length = Text.size(description);
    length >= MIN_DESCRIPTION_LENGTH and length <= MAX_DESCRIPTION_LENGTH;
  };

  private func validateTags(tags : [Tag]) : Bool {
    tags.size() <= MAX_TAGS;
  };

  private func validateTimes(bettingCloseTime : Int, expirationTime : Int) : Bool {
    let currentTime = Time.now();
    bettingCloseTime > currentTime and expirationTime > bettingCloseTime;
  };

  private func validateOutcomeName(outcome : Text) : Bool {
    Text.size(outcome) > 0 and Text.size(outcome) <= 50
  };

  private func validateMarketArgs(
    title : Text,
    description : Text,
    tags : [Tag],
    bettingCloseTime : Int,
    expirationTime : Int,
  ) : Result.Result<(), Text> {
    if (not validateTitle(title)) {
      return #err("Title must be between " # Nat.toText(MIN_TITLE_LENGTH) # " and " # Nat.toText(MAX_TITLE_LENGTH) # " characters");
    };
    if (not validateDescription(description)) {
      return #err("Description must be between " # Nat.toText(MIN_DESCRIPTION_LENGTH) # " and " # Nat.toText(MAX_DESCRIPTION_LENGTH) # " characters");
    };
    if (not validateTags(tags)) {
      return #err("Maximum " # Nat.toText(MAX_TAGS) # " tags allowed");
    };
    if (not validateTimes(bettingCloseTime, expirationTime)) {
      return #err("Betting close time must be in the future and expiration time must be after betting close time");
    };
    #ok();
  };

  // Helper to convert text to uppercase symbol
  private func toUpperSymbol(text : Text) : Text {
    Text.map(
      text,
      func(c : Char) : Char {
        if (c == ' ') '_' else if (c >= 'a' and c <= 'z') Char.fromNat32(Char.toNat32(c) - 32) else c;
      },
    );
  };

  // ===== ADMIN FUNCTIONS =====

  // Chunked WASM upload support
  private stable var wasmChunks : [Blob] = [];

  public shared ({ caller }) func uploadIcrc151WasmChunk(chunk : Blob) : async Result.Result<Text, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can upload WASM");
    };
    wasmChunks := Array.append(wasmChunks, [chunk]);
    Debug.print("Chunk uploaded. Total chunks: " # Nat.toText(wasmChunks.size()));
    #ok("Chunk " # Nat.toText(wasmChunks.size()) # " uploaded");
  };

  public shared ({ caller }) func finalizeIcrc151WasmUpload() : async Result.Result<Text, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can finalize WASM");
    };

    if (wasmChunks.size() == 0) {
      return #err("No chunks to finalize");
    };

    // Combine all chunks
    var combined : [Nat8] = [];
    for (chunk in wasmChunks.vals()) {
      combined := Array.append(combined, Blob.toArray(chunk));
    };

    icrc151_wasm := ?Blob.fromArray(combined);
    let totalSize = combined.size();

    // Clear chunks
    wasmChunks := [];

    Debug.print("ICRC-151 WASM finalized. Total size: " # Nat.toText(totalSize) # " bytes");
    #ok("WASM finalized successfully. Size: " # Nat.toText(totalSize) # " bytes");
  };

  public shared ({ caller }) func clearWasmChunks() : async Result.Result<Text, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can clear chunks");
    };
    wasmChunks := [];
    #ok("Chunks cleared");
  };

  public shared ({ caller }) func uploadIcrc151Wasm(wasm_blob : Blob) : async Result.Result<Text, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can upload WASM");
    };
    icrc151_wasm := ?wasm_blob;
    Debug.print("ICRC-151 WASM uploaded successfully. Size: " # Nat.toText(Blob.toArray(wasm_blob).size()) # " bytes");
    #ok("ICRC-151 WASM module uploaded successfully");
  };

  public query func hasIcrc151Wasm() : async Bool {
    switch (icrc151_wasm) {
      case (null) false;
      case (?_) true;
    };
  };

  public shared ({ caller }) func clearIcrc151Wasm() : async Result.Result<Text, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can clear WASM");
    };
    icrc151_wasm := null;
    Debug.print("ICRC-151 WASM cleared");
    #ok("ICRC-151 WASM module cleared");
  };

  // ===== CYCLE MANAGEMENT =====

  public query func getCycleBalance() : async Nat {
    Cycles.balance();
  };

  public shared func acceptCycles() : async Nat {
    let amount = Cycles.accept(Cycles.available());
    Debug.print("Accepted " # Nat.toText(amount) # " cycles");
    amount;
  };

  public query func canCreateMarket() : async {
    canCreate : Bool;
    currentBalance : Nat;
    requiredCycles : Nat;
  } {
    let currentBalance = Cycles.balance();
    let requiredCycles = CYCLES_PER_LEDGER;
    {
      canCreate = currentBalance >= requiredCycles;
      currentBalance = currentBalance;
      requiredCycles = requiredCycles;
    };
  };

  // ===== HELPER FUNCTIONS =====

  // Deploy a new ICRC-151 ledger canister
  private func deployIcrc151Ledger() : async Result.Result<Principal, Text> {
    try {
      switch (icrc151_wasm) {
        case (null) {
          return #err("ICRC-151 WASM not uploaded. Use uploadIcrc151Wasm() first");
        };
        case (?wasm) {
          if (Cycles.balance() < CYCLES_PER_LEDGER) {
            return #err("Insufficient cycles. Need " # Nat.toText(CYCLES_PER_LEDGER) # " but have " # Nat.toText(Cycles.balance()));
          };

          Debug.print("Creating ICRC-151 ledger canister...");

          let createResult = await (with cycles = CYCLES_PER_LEDGER) mgmt.create_canister({
            settings = ?{
              controllers = [Principal.fromActor(TokenFactory)];
            };
          });

          let ledgerId = createResult.canister_id;
          Debug.print("ICRC-151 ledger created: " # Principal.toText(ledgerId));

          // Install ICRC-151 WASM with empty init args
          Debug.print("Installing ICRC-151 WASM...");
          await mgmt.install_code({
            canister_id = ledgerId;
            wasm_module = wasm;
            arg = Blob.fromArray([]); // Empty init args
            mode = #install;
          });

          Debug.print("ICRC-151 ledger installed successfully");

          // Add TokenFactory as controller of the ledger
          let ledger : ICRC151Interface = actor (Principal.toText(ledgerId));
          // Note: add_controller is in the candid but we'll skip for now since we're already the controller

          createdLedgers := Array.append(createdLedgers, [ledgerId]);

          #ok(ledgerId);
        };
      };
    } catch (e) {
      let errorMsg = "Failed to deploy ICRC-151 ledger: " # Error.message(e);
      Debug.print(errorMsg);
      #err(errorMsg);
    };
  };

  // Create a token within an ICRC-151 ledger
  private func createTokenInLedger(
    ledger : Principal,
    name : Text,
    symbol : Text,
    description : Text,
  ) : async Result.Result<TokenId, Text> {
    try {
      let ledgerActor : ICRC151Interface = actor (Principal.toText(ledger));

      Debug.print("Creating token: " # name # " (" # symbol # ")");

      let result = await ledgerActor.create_token(
        name,
        symbol,
        DEFAULT_DECIMALS,
        null, // max_supply (unlimited)
        ?DEFAULT_FEE,
        null, // logo
        ?description,
      );

      switch (result) {
        case (#Ok(tokenId)) {
          Debug.print("✓ Token created successfully: " # name);
          #ok(tokenId)
        };
        case (#Err(e)) {
          let errorMsg = "Failed to create token " # name # ": " # e;
          Debug.print(errorMsg);
          #err(errorMsg)
        };
      };
    } catch (e) {
      let errorMsg = "Error creating token " # name # ": " # Error.message(e);
      Debug.print(errorMsg);
      #err(errorMsg);
    };
  };

  // ===== PUBLIC API - MARKET CREATION =====

  public shared ({ caller }) func createBinaryMarket(
    args : CreateBinaryMarketArgs
  ) : async Result.Result<MarketId, Text> {

    // Validate input
    switch (validateMarketArgs(args.title, args.description, args.tags, args.bettingCloseTime, args.expirationTime)) {
      case (#err(msg)) return #err(msg);
      case (#ok()) {};
    };

    // Check cycles
    let cycleCheck = await canCreateMarket();
    if (not cycleCheck.canCreate) {
      return #err("Insufficient cycles. Need " # Nat.toText(cycleCheck.requiredCycles) # " but have " # Nat.toText(cycleCheck.currentBalance));
    };

    let marketId = nextMarketId;

    Debug.print("========================================");
    Debug.print("Creating Binary Market #" # Nat.toText(marketId));
    Debug.print("Title: " # args.title);
    Debug.print("========================================");

    // Deploy single ICRC-151 ledger for this market
    let ledgerResult = await deployIcrc151Ledger();
    let ledger = switch (ledgerResult) {
      case (#ok(l)) l;
      case (#err(e)) return #err("Failed to deploy ledger: " # e);
    };

    // Create YES token
    let yesResult = await createTokenInLedger(
      ledger,
      "YES - " # args.title,
      "YES" # Nat.toText(marketId),
      "YES token for: " # args.title,
    );
    let yesTokenId = switch (yesResult) {
      case (#ok(id)) id;
      case (#err(e)) return #err("Failed to create YES token: " # e);
    };

    // Create NO token
    let noResult = await createTokenInLedger(
      ledger,
      "NO - " # args.title,
      "NO" # Nat.toText(marketId),
      "NO token for: " # args.title,
    );
    let noTokenId = switch (noResult) {
      case (#ok(id)) id;
      case (#err(e)) return #err("Failed to create NO token: " # e);
    };

    // Create market metadata
    let metadata : MarketMetadata = {
      title = args.title;
      description = args.description;
      category = args.category;
      creator = caller;
      image = args.image;
      tags = args.tags;
      bettingCloseTime = args.bettingCloseTime;
      expirationTime = args.expirationTime;
      resolutionLink = args.resolutionLink;
      resolutionDescription = args.resolutionDescription;
      created_at = Time.now();
    };

    // Store market info
    let info : MarketInfo = {
      id = marketId;
      metadata = metadata;
      marketType = #Binary;
      tokens = #Binary({
        ledger = ledger;
        yesTokenId = yesTokenId;
        noTokenId = noTokenId;
      });
    };
    marketInfo.put(marketId, info);

    nextMarketId += 1;

    Debug.print("========================================");
    Debug.print("✓ Binary Market #" # Nat.toText(marketId) # " created successfully!");
    Debug.print("Ledger: " # Principal.toText(ledger));
    Debug.print("YES Token ID: " # debug_show (yesTokenId));
    Debug.print("NO Token ID: " # debug_show (noTokenId));
    Debug.print("Cycle cost: ~0.85T (saved 0.85T vs ICRC-2)");
    Debug.print("Remaining cycles: " # Nat.toText(Cycles.balance()));
    Debug.print("========================================");

    #ok(marketId);
  };

  public shared ({ caller }) func createMultipleChoiceMarket(
    args : CreateMultipleChoiceMarketArgs
  ) : async Result.Result<MarketId, Text> {

    // Validate input
    switch (validateMarketArgs(args.title, args.description, args.tags, args.bettingCloseTime, args.expirationTime)) {
      case (#err(msg)) return #err(msg);
      case (#ok()) {};
    };

    if (args.outcomes.size() < 2) {
      return #err("Multiple choice markets need at least 2 outcomes");
    };

    if (args.outcomes.size() > MAX_OUTCOMES) {
      return #err("Too many outcomes. Maximum is " # Nat.toText(MAX_OUTCOMES));
    };

    // Validate outcome names
    for (outcome in args.outcomes.vals()) {
      if (not validateOutcomeName(outcome)) {
        return #err("Invalid outcome name: " # outcome);
      };
    };

    let marketId = nextMarketId;

    Debug.print("========================================");
    Debug.print("Creating Multiple Choice Market #" # Nat.toText(marketId));
    Debug.print("Title: " # args.title);
    Debug.print("Outcomes: " # Nat.toText(args.outcomes.size()));
    Debug.print("========================================");

    // Deploy single ICRC-151 ledger
    let ledgerResult = await deployIcrc151Ledger();
    let ledger = switch (ledgerResult) {
      case (#ok(l)) l;
      case (#err(e)) return #err(e);
    };

    // Create token for each outcome
    var outcomeTokens : [(Text, TokenId)] = [];
    for (outcome in args.outcomes.vals()) {
      let tokenResult = await createTokenInLedger(
        ledger,
        outcome # " - " # args.title,
        toUpperSymbol(outcome) # Nat.toText(marketId),
        outcome # " token for: " # args.title,
      );

      switch (tokenResult) {
        case (#ok(tokenId)) {
          outcomeTokens := Array.append(outcomeTokens, [(outcome, tokenId)]);
        };
        case (#err(e)) {
          return #err("Failed to create " # outcome # " token: " # e);
        };
      };
    };

    let metadata : MarketMetadata = {
      title = args.title;
      description = args.description;
      category = args.category;
      creator = caller;
      image = args.image;
      tags = args.tags;
      bettingCloseTime = args.bettingCloseTime;
      expirationTime = args.expirationTime;
      resolutionLink = args.resolutionLink;
      resolutionDescription = args.resolutionDescription;
      created_at = Time.now();
    };

    let info : MarketInfo = {
      id = marketId;
      metadata = metadata;
      marketType = #MultipleChoice({ outcomes = args.outcomes });
      tokens = #MultipleChoice({
        ledger = ledger;
        outcomeTokens = outcomeTokens;
      });
    };
    marketInfo.put(marketId, info);

    nextMarketId += 1;

    Debug.print("========================================");
    Debug.print("✓ Multiple Choice Market #" # Nat.toText(marketId) # " created!");
    Debug.print("Ledger: " # Principal.toText(ledger));
    Debug.print("Outcomes: " # Nat.toText(args.outcomes.size()));
    let savedCycles = (args.outcomes.size() - 1) * CYCLES_PER_LEDGER;
    Debug.print("Cycle savings: " # Nat.toText(savedCycles));
    Debug.print("========================================");

    #ok(marketId);
  };

  public shared ({ caller }) func createCompoundMarket(
    args : CreateCompoundMarketArgs
  ) : async Result.Result<MarketId, Text> {

    // Validate input
    switch (validateMarketArgs(args.title, args.description, args.tags, args.bettingCloseTime, args.expirationTime)) {
      case (#err(msg)) return #err(msg);
      case (#ok()) {};
    };

    if (args.subjects.size() < 2) {
      return #err("Compound markets need at least 2 subjects");
    };

    if (args.subjects.size() > MAX_SUBJECTS) {
      return #err("Too many subjects. Maximum is " # Nat.toText(MAX_SUBJECTS));
    };

    // Validate subject names
    for (subject in args.subjects.vals()) {
      if (not validateOutcomeName(subject)) {
        return #err("Invalid subject name: " # subject);
      };
    };

    let marketId = nextMarketId;

    Debug.print("========================================");
    Debug.print("Creating Compound Market #" # Nat.toText(marketId));
    Debug.print("Title: " # args.title);
    Debug.print("Subjects: " # Nat.toText(args.subjects.size()));
    Debug.print("========================================");

    // Deploy single ICRC-151 ledger
    let ledgerResult = await deployIcrc151Ledger();
    let ledger = switch (ledgerResult) {
      case (#ok(l)) l;
      case (#err(e)) return #err(e);
    };

    // Create YES/NO tokens for each subject
    var subjectTokens : [(Text, { yesTokenId : TokenId; noTokenId : TokenId })] = [];

    for (subject in args.subjects.vals()) {
      // Create YES token
      let yesResult = await createTokenInLedger(
        ledger,
        subject # " YES - " # args.title,
        toUpperSymbol(subject) # "_YES" # Nat.toText(marketId),
        "YES token for " # subject,
      );

      let yesTokenId = switch (yesResult) {
        case (#ok(id)) id;
        case (#err(e)) return #err(e);
      };

      // Create NO token
      let noResult = await createTokenInLedger(
        ledger,
        subject # " NO - " # args.title,
        toUpperSymbol(subject) # "_NO" # Nat.toText(marketId),
        "NO token for " # subject,
      );

      let noTokenId = switch (noResult) {
        case (#ok(id)) id;
        case (#err(e)) return #err(e);
      };

      subjectTokens := Array.append(subjectTokens, [(subject, { yesTokenId = yesTokenId; noTokenId = noTokenId })]);
    };

    let metadata : MarketMetadata = {
      title = args.title;
      description = args.description;
      category = args.category;
      creator = caller;
      image = args.image;
      tags = args.tags;
      bettingCloseTime = args.bettingCloseTime;
      expirationTime = args.expirationTime;
      resolutionLink = args.resolutionLink;
      resolutionDescription = args.resolutionDescription;
      created_at = Time.now();
    };

    let info : MarketInfo = {
      id = marketId;
      metadata = metadata;
      marketType = #Compound({ subjects = args.subjects });
      tokens = #Compound({
        ledger = ledger;
        subjectTokens = subjectTokens;
      });
    };
    marketInfo.put(marketId, info);

    nextMarketId += 1;

    Debug.print("========================================");
    Debug.print("✓ Compound Market #" # Nat.toText(marketId) # " created!");
    Debug.print("Ledger: " # Principal.toText(ledger));
    Debug.print("Subjects: " # Nat.toText(args.subjects.size()));
    let tokenCount = args.subjects.size() * 2;
    let savedCycles = (tokenCount - 1) * CYCLES_PER_LEDGER;
    Debug.print("Cycle savings: " # Nat.toText(savedCycles));
    Debug.print("========================================");

    #ok(marketId);
  };

  // ===== QUERY FUNCTIONS =====

  public query func getMarketInfo(marketId : MarketId) : async ?MarketInfo {
    marketInfo.get(marketId);
  };

  public query func getAllMarkets() : async [MarketInfo] {
    Iter.toArray(marketInfo.vals());
  };

  public query func getActiveMarkets() : async [MarketInfo] {
    let currentTime = Time.now();
    let filtered = Array.filter<MarketInfo>(
      Iter.toArray(marketInfo.vals()),
      func(market : MarketInfo) : Bool {
        market.metadata.bettingCloseTime > currentTime;
      },
    );
    filtered;
  };

  public query func getMarketCount() : async Nat {
    nextMarketId - 1;
  };

  public query func getCreatedLedgers() : async [Principal] {
    createdLedgers;
  };

  public query func getFactoryPrincipal() : async Principal {
    Principal.fromActor(TokenFactory);
  };

  // Get all token IDs for a specific market
  public query func getMarketTokenIds(marketId : MarketId) : async ?{
    ledger : Principal;
    tokenIds : [TokenId];
  } {
    switch (marketInfo.get(marketId)) {
      case (null) null;
      case (?info) {
        switch (info.tokens) {
          case (#Binary(tokens)) {
            ?{
              ledger = tokens.ledger;
              tokenIds = [tokens.yesTokenId, tokens.noTokenId];
            };
          };
          case (#MultipleChoice(tokens)) {
            ?{
              ledger = tokens.ledger;
              tokenIds = Array.map<(Text, TokenId), TokenId>(
                tokens.outcomeTokens,
                func((_, id)) = id,
              );
            };
          };
          case (#Compound(tokens)) {
            var allTokenIds : [TokenId] = [];
            for ((_, subjectTokens) in tokens.subjectTokens.vals()) {
              allTokenIds := Array.append(
                allTokenIds,
                [subjectTokens.yesTokenId, subjectTokens.noTokenId],
              );
            };
            ?{
              ledger = tokens.ledger;
              tokenIds = allTokenIds;
            };
          };
        };
      };
    };
  };

  // Helper to get token balance (for testing)
  public func getTokenBalance(
    ledger : Principal,
    tokenId : TokenId,
    account : Account,
  ) : async Result.Result<Nat, Text> {
    try {
      let ledgerActor : ICRC151Interface = actor (Principal.toText(ledger));
      fromCandidResult(await ledgerActor.get_balance(tokenId, account));
    } catch (e) {
      #err("Failed to get balance: " # Error.message(e));
    };
  };

  // Helper to mint tokens (for testing - TokenFactory is the minter)
  public shared ({ caller }) func mintTokens(
    ledger : Principal,
    tokenId : TokenId,
    to : Account,
    amount : Nat,
  ) : async Result.Result<Nat64, Text> {
    if (not Principal.isController(caller)) {
      return #err("Only controller can mint tokens");
    };

    try {
      let ledgerActor : ICRC151Interface = actor (Principal.toText(ledger));
      fromCandidResult(await ledgerActor.mint_tokens(tokenId, to, amount, null));
    } catch (e) {
      #err("Failed to mint tokens: " # Error.message(e));
    };
  };

  // List all tokens in a ledger
  public func listTokensInLedger(ledger : Principal) : async [TokenId] {
    try {
      let ledgerActor : ICRC151Interface = actor (Principal.toText(ledger));
      await ledgerActor.list_tokens();
    } catch (e) {
      Debug.print("Failed to list tokens: " # Error.message(e));
      [];
    };
  };
};
