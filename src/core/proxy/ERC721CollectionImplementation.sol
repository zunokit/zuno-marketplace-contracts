// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721Collection} from "src/core/collection/ERC721Collection.sol";
import {CollectionParams, MintStage} from "src/types/ListingTypes.sol";
import {Fee} from "src/common/Fee.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title ERC721CollectionImplementation
 * @notice Implementation contract for ERC721 collections using proxy pattern
 * @dev This contract is deployed once and used as implementation for all ERC721 collection proxies
 * @dev Uses OpenZeppelin's Initializable to prevent re-initialization attacks
 * @author NFT Marketplace Team
 */
contract ERC721CollectionImplementation is ERC721Collection, Initializable {
    /**
     * @notice Constructor that prevents direct usage
     * @dev Disables initializers to prevent implementation contract initialization
     * @dev Uses dummy params to satisfy parent constructor requirements
     */
    constructor() ERC721Collection(_getDefaultParams()) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ERC721 collection implementation
     * @param params Collection parameters
     * @dev This function replaces the constructor for proxy pattern
     * @dev Uses OpenZeppelin's initializer modifier to prevent re-initialization
     * @dev Can only be called once per proxy instance
     */
    function initialize(CollectionParams memory params) external initializer {
        require(params.owner != address(0), "Zero address owner");
        require(params.maxSupply > 0, "Max supply must be greater than 0");
        require(bytes(params.name).length > 0, "Name cannot be empty");
        require(bytes(params.symbol).length > 0, "Symbol cannot be empty");

        // Initialize collection state manually since we can't call parent constructors
        _initializeCollection(params);

        // Transfer ownership to the specified owner
        _transferOwnership(params.owner);
    }

    /**
     * @notice Internal function to initialize collection state
     * @param params Collection parameters
     */
    function _initializeCollection(CollectionParams memory params) internal {
        // Initialize name and symbol for proxy pattern
        _setNameAndSymbol(params.name, params.symbol);

        // Initialize BaseCollection state
        s_description = params.description;
        s_mintPrice = params.mintPrice;
        s_maxSupply = params.maxSupply;
        s_mintLimitPerWallet = params.mintLimitPerWallet;
        s_mintStartTime = params.mintStartTime;
        s_allowlistMintPrice = params.allowlistMintPrice;
        s_publicMintPrice = params.publicMintPrice;
        s_allowlistStageEnd = params.mintStartTime + params.allowlistStageDuration;
        s_currentStage = MintStage.INACTIVE;
        s_tokenURI = params.tokenURI;
        s_royaltyFee = params.royaltyFee;

        // Create Fee contract for royalty management
        s_feeContract = new Fee(params.owner, params.royaltyFee);
    }

    /**
     * @notice Returns default parameters for implementation constructor
     * @dev Used to initialize implementation with dummy data
     */
    function _getDefaultParams() internal pure returns (CollectionParams memory) {
        return CollectionParams({
            name: "Implementation",
            symbol: "IMPL",
            owner: address(0xdead),
            description: "Implementation contract",
            mintPrice: 0,
            royaltyFee: 0,
            maxSupply: 0,
            mintLimitPerWallet: 0,
            mintStartTime: 0,
            allowlistMintPrice: 0,
            publicMintPrice: 0,
            allowlistStageDuration: 0,
            tokenURI: ""
        });
    }
}
