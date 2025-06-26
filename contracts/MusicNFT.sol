// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC721Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract MusicNFTPlatform {
    string private _name;
    string private _symbol;
    address private _owner;
    uint256 private _tokenIds;
    
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    
    modifier onlyOwner() {
        require(msg.sender == _owner, "Not the owner");
        _;
    }
    
    modifier nonReentrant() {
        _;
    }
    
    struct MusicNFT {
        string title;
        string artist;
        string ipfsHash;
        uint256 price;
        uint256 royaltyPercentage; // Basis points (e.g., 1000 = 10%)
        uint256 totalStreams;
        uint256 totalRoyalties;
        address creator;
        bool isActive;
    }
    
    struct StreamingData {
        uint256 streamCount;
        uint256 lastStreamTime;
        uint256 totalPaid;
    }
    
    mapping(uint256 => MusicNFT) public musicNFTs;
    mapping(uint256 => mapping(address => StreamingData)) public userStreams;
    mapping(address => uint256) public pendingRoyalties;
    
    uint256 public constant STREAMING_FEE = 0.001 ether; // Fee per stream
    uint256 public constant PLATFORM_FEE = 500; // 5% platform fee in basis points
    uint256 public constant MAX_ROYALTY = 5000; // Maximum 50% royalty
    
    event MusicNFTMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string title,
        string artist,
        uint256 price
    );
    
    event MusicStreamed(
        uint256 indexed tokenId,
        address indexed listener,
        uint256 royaltyPaid,
        uint256 streamCount
    );
    
    event RoyaltiesWithdrawn(
        address indexed recipient,
        uint256 amount
    );
    
    constructor() {
        _name = "MusicNFT";
        _symbol = "MNFT";
        _owner = msg.sender;
    }
    
    function name() public view returns (string memory) {
        return _name;
    }
    
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    
    function owner() public view returns (address) {
        return _owner;
    }
    
    function balanceOf(address owner_) public view returns (uint256) {
        require(owner_ != address(0), "ERC721: balance query for the zero address");
        return _balances[owner_];
    }
    
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner_ = _owners[tokenId];
        require(owner_ != address(0), "ERC721: owner query for nonexistent token");
        return owner_;
    }
    
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }
    
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");
        
        _balances[to] += 1;
        _owners[tokenId] = to;
    }
    
    function _safeMint(address to, uint256 tokenId) internal {
        _mint(to, tokenId);
    }
    
    /**
     * @dev Mint a new Music NFT
     * @param title The title of the music track
     * @param artist The artist name
     * @param ipfsHash IPFS hash of the music file
     * @param price Price to purchase the NFT
     * @param royaltyPercentage Royalty percentage in basis points
     */
    function mintMusicNFT(
        string memory title,
        string memory artist,
        string memory ipfsHash,
        uint256 price,
        uint256 royaltyPercentage
    ) external returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");
        require(bytes(artist).length > 0, "Artist cannot be empty");
        require(bytes(ipfsHash).length > 0, "IPFS hash cannot be empty");
        require(price > 0, "Price must be greater than 0");
        require(royaltyPercentage <= MAX_ROYALTY, "Royalty percentage too high");
        
        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        
        _safeMint(msg.sender, newTokenId);
        
        musicNFTs[newTokenId] = MusicNFT({
            title: title,
            artist: artist,
            ipfsHash: ipfsHash,
            price: price,
            royaltyPercentage: royaltyPercentage,
            totalStreams: 0,
            totalRoyalties: 0,
            creator: msg.sender,
            isActive: true
        });
        
        emit MusicNFTMinted(newTokenId, msg.sender, title, artist, price);
        
        return newTokenId;
    }
    
    /**
     * @dev Stream a music NFT and pay royalties
     * @param tokenId The ID of the music NFT to stream
     */
    function streamMusic(uint256 tokenId) external payable nonReentrant {
        require(_exists(tokenId), "Music NFT does not exist");
        require(msg.value >= STREAMING_FEE, "Insufficient streaming fee");
        require(musicNFTs[tokenId].isActive, "Music NFT is not active");
        
        MusicNFT storage music = musicNFTs[tokenId];
        StreamingData storage userStream = userStreams[tokenId][msg.sender];
        
        // Calculate royalty payment
        uint256 royaltyAmount = (STREAMING_FEE * music.royaltyPercentage) / 10000;
        uint256 platformFeeAmount = (STREAMING_FEE * PLATFORM_FEE) / 10000;
        uint256 creatorAmount = STREAMING_FEE - platformFeeAmount;
        
        // Update streaming data
        music.totalStreams++;
        music.totalRoyalties += royaltyAmount;
        userStream.streamCount++;
        userStream.lastStreamTime = block.timestamp;
        userStream.totalPaid += STREAMING_FEE;
        
        // Add to pending royalties
        pendingRoyalties[music.creator] += creatorAmount;
        
        // Refund excess payment
        if (msg.value > STREAMING_FEE) {
            payable(msg.sender).transfer(msg.value - STREAMING_FEE);
        }
        
        emit MusicStreamed(tokenId, msg.sender, royaltyAmount, userStream.streamCount);
    }
    
    /**
     * @dev Withdraw accumulated royalties
     */
    function withdrawRoyalties() external nonReentrant {
        uint256 amount = pendingRoyalties[msg.sender];
        require(amount > 0, "No royalties to withdraw");
        
        pendingRoyalties[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        
        emit RoyaltiesWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Get music NFT details
     * @param tokenId The ID of the music NFT
     */
    function getMusicNFT(uint256 tokenId) external view returns (
        string memory title,
        string memory artist,
        string memory ipfsHash,
        uint256 price,
        uint256 royaltyPercentage,
        uint256 totalStreams,
        uint256 totalRoyalties,
        address creator,
        bool isActive
    ) {
        require(_exists(tokenId), "Music NFT does not exist");
        
        MusicNFT memory music = musicNFTs[tokenId];
        return (
            music.title,
            music.artist,
            music.ipfsHash,
            music.price,
            music.royaltyPercentage,
            music.totalStreams,
            music.totalRoyalties,
            music.creator,
            music.isActive
        );
    }
    
    /**
     * @dev Get user's streaming data for a specific NFT
     * @param tokenId The ID of the music NFT
     * @param user The user's address
     */
    function getUserStreamingData(uint256 tokenId, address user) external view returns (
        uint256 streamCount,
        uint256 lastStreamTime,
        uint256 totalPaid
    ) {
        StreamingData memory data = userStreams[tokenId][user];
        return (data.streamCount, data.lastStreamTime, data.totalPaid);
    }
    
    /**
     * @dev Toggle active status of a music NFT (only creator)
     * @param tokenId The ID of the music NFT
     */
    function toggleMusicStatus(uint256 tokenId) external {
        require(_exists(tokenId), "Music NFT does not exist");
        require(musicNFTs[tokenId].creator == msg.sender, "Not the creator");
        
        musicNFTs[tokenId].isActive = !musicNFTs[tokenId].isActive;
    }
    
    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        payable(_owner).transfer(balance);
    }
    
    /**
     * @dev Get total number of minted NFTs
     */
    function getTotalNFTs() external view returns (uint256) {
        return _tokenIds;
    }
    
    /**
     * @dev Get tokenURI to return metadata
     */
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        
        // In a real implementation, this would return a properly formatted JSON metadata URI
        // For now, returning the IPFS hash
        return string(abi.encodePacked("ipfs://", musicNFTs[tokenId].ipfsHash));
    }
}
