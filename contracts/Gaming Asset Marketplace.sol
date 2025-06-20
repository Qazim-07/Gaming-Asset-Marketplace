// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    uint256 private _tokenIds;
    uint256 private _itemsSold;
    address public owner;
    
    // Marketplace fee (2.5%)
    uint256 public marketplaceFee = 25; // 25/1000 = 2.5%
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    // Asset rarity levels
    enum Rarity { COMMON, RARE, EPIC, LEGENDARY, MYTHIC }
    
    // Gaming asset structure
    struct GameAsset {
        uint256 tokenId;
        address payable owner;
        address payable seller;
        uint256 price;
        bool isListed;
        string gameId;
        Rarity rarity;
        uint256 mintedAt;
        string tokenURI;
    }
    
    // Mappings
    mapping(uint256 => GameAsset) public gameAssets;
    mapping(uint256 => address) public tokenOwners;
    mapping(string => bool) public supportedGames;
    mapping(address => uint256[]) public userAssets;
    mapping(Rarity => uint256) public rarityMultiplier;
    
    // Events
    event AssetMinted(uint256 indexed tokenId, address indexed owner, string gameId, Rarity rarity);
    event AssetListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event AssetSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event GameAdded(string gameId);
    event AssetTransferredCrossGame(uint256 indexed tokenId, string fromGame, string toGame);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier nonReentrant() {
        _;
    }
    
    constructor() {
        owner = msg.sender;
        
        // Initialize rarity multipliers for pricing
        rarityMultiplier[Rarity.COMMON] = 1;
        rarityMultiplier[Rarity.RARE] = 3;
        rarityMultiplier[Rarity.EPIC] = 7;
        rarityMultiplier[Rarity.LEGENDARY] = 15;
        rarityMultiplier[Rarity.MYTHIC] = 30;
        
        // Add some default supported games
        supportedGames["fantasy-rpg"] = true;
        supportedGames["space-shooter"] = true;
        supportedGames["medieval-quest"] = true;
    }
    
    /**
     * @dev Core Function 1: Mint Gaming Asset
     * @param gameId The game identifier
     * @param rarity The rarity level of the asset
     * @param tokenURI The metadata URI for the asset
     */
    function mintGameAsset(
        string memory gameId,
        Rarity rarity,
        string memory tokenURI
    ) public payable nonReentrant returns (uint256) {
        require(supportedGames[gameId], "Game not supported");
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");
        
        // Calculate minting fee based on rarity
        uint256 mintingFee = 0.001 ether * rarityMultiplier[rarity];
        require(msg.value >= mintingFee, "Insufficient minting fee");
        
        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        
        // Mint token to user
        tokenOwners[newTokenId] = msg.sender;
        
        // Create game asset
        gameAssets[newTokenId] = GameAsset({
            tokenId: newTokenId,
            owner: payable(msg.sender),
            seller: payable(address(0)),
            price: 0,
            isListed: false,
            gameId: gameId,
            rarity: rarity,
            mintedAt: block.timestamp,
            tokenURI: tokenURI
        });
        
        userAssets[msg.sender].push(newTokenId);
        
        emit AssetMinted(newTokenId, msg.sender, gameId, rarity);
        return newTokenId;
    }
    
    /**
     * @dev Core Function 2: List Asset for Sale
     * @param tokenId The token ID to list
     * @param price The selling price in wei
     */
    function listAssetForSale(uint256 tokenId, uint256 price) public nonReentrant {
        require(tokenOwners[tokenId] != address(0), "Token does not exist");
        require(tokenOwners[tokenId] == msg.sender, "Only owner can list asset");
        require(price > 0, "Price must be greater than zero");
        require(!gameAssets[tokenId].isListed, "Asset already listed");
        
        // Update asset details
        gameAssets[tokenId].seller = payable(msg.sender);
        gameAssets[tokenId].price = price;
        gameAssets[tokenId].isListed = true;
        
        emit AssetListed(tokenId, msg.sender, price);
    }
    
    /**
     * @dev Core Function 3: Purchase Listed Asset
     * @param tokenId The token ID to purchase
     */
    function purchaseAsset(uint256 tokenId) public payable nonReentrant {
        GameAsset storage asset = gameAssets[tokenId];
        
        require(tokenOwners[tokenId] != address(0), "Token does not exist");
        require(asset.isListed, "Asset not listed for sale");
        require(msg.value >= asset.price, "Insufficient payment");
        require(msg.sender != asset.seller, "Cannot buy your own asset");
        
        address seller = asset.seller;
        uint256 price = asset.price;
        
        // Calculate fees
        uint256 fee = (price * marketplaceFee) / FEE_DENOMINATOR;
        uint256 sellerAmount = price - fee;
        
        // Transfer ownership
        tokenOwners[tokenId] = msg.sender;
        
        // Reset asset listing status
        asset.isListed = false;
        asset.owner = payable(msg.sender);
        asset.seller = payable(address(0));
        asset.price = 0;
        
        // Update user assets
        _removeFromUserAssets(seller, tokenId);
        userAssets[msg.sender].push(tokenId);
        
        // Transfer payments
        payable(seller).transfer(sellerAmount);
        
        // Refund excess payment
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
        
        _itemsSold++;
        
        emit AssetSold(tokenId, seller, msg.sender, price);
    }
    
    /**
     * @dev Transfer asset between supported games (cross-game compatibility)
     * @param tokenId The token ID to transfer
     * @param newGameId The destination game ID
     */
    function transferAssetCrossGame(uint256 tokenId, string memory newGameId) public {
        require(tokenOwners[tokenId] != address(0), "Token does not exist");
        require(tokenOwners[tokenId] == msg.sender, "Only owner can transfer asset");
        require(supportedGames[newGameId], "Destination game not supported");
        require(!gameAssets[tokenId].isListed, "Cannot transfer listed asset");
        
        string memory oldGameId = gameAssets[tokenId].gameId;
        gameAssets[tokenId].gameId = newGameId;
        
        emit AssetTransferredCrossGame(tokenId, oldGameId, newGameId);
    }
    
    /**
     * @dev Add supported game (only owner)
     * @param gameId The game identifier to add
     */
    function addSupportedGame(string memory gameId) public onlyOwner {
        require(!supportedGames[gameId], "Game already supported");
        supportedGames[gameId] = true;
        emit GameAdded(gameId);
    }
    
    /**
     * @dev Cancel asset listing
     * @param tokenId The token ID to cancel listing
     */
    function cancelListing(uint256 tokenId) public nonReentrant {
        GameAsset storage asset = gameAssets[tokenId];
        
        require(tokenOwners[tokenId] != address(0), "Token does not exist");
        require(asset.seller == msg.sender, "Only seller can cancel listing");
        require(asset.isListed, "Asset not listed");
        
        // Reset listing status
        asset.isListed = false;
        asset.seller = payable(address(0));
        asset.price = 0;
    }
    
    /**
     * @dev Get all assets owned by a user
     * @param user The user address
     */
    function getUserAssets(address user) public view returns (uint256[] memory) {
        return userAssets[user];
    }
    
    /**
     * @dev Get marketplace statistics
     */
    function getMarketplaceStats() public view returns (uint256 totalAssets, uint256 itemsSold, uint256 activeListings) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= _tokenIds; i++) {
            if (gameAssets[i].isListed) {
                activeCount++;
            }
        }
        return (_tokenIds, _itemsSold, activeCount);
    }
    
    /**
     * @dev Withdraw marketplace fees (only owner)
     */
    function withdrawFees() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        payable(owner).transfer(balance);
    }
    
    /**
     * @dev Update marketplace fee (only owner)
     * @param newFee The new fee (in basis points, max 5%)
     */
    function updateMarketplaceFee(uint256 newFee) public onlyOwner {
        require(newFee <= 50, "Fee cannot exceed 5%"); // 50/1000 = 5%
        marketplaceFee = newFee;
    }
    
    // Internal function to remove token from user's asset list
    function _removeFromUserAssets(address user, uint256 tokenId) internal {
        uint256[] storage assets = userAssets[user];
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == tokenId) {
                assets[i] = assets[assets.length - 1];
                assets.pop();
                break;
            }
        }
    }
}
