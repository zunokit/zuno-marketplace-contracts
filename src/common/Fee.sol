// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {MAX_ROYALTY_FEE} from "src/types/ListingTypes.sol";
import {FeeUpdated} from "src/events/FeeEvents.sol";
import {Fee__InvalidRoyaltyFee} from "src/errors/FeeErrors.sol";

contract Fee is Ownable, ERC165, IERC2981 {
    uint256 public s_royaltyFee; // Royalty fee (in basis points, e.g., 500 = 5%)

    constructor(address owner_, uint256 royaltyFee_) Ownable(owner_) {
        if (royaltyFee_ > MAX_ROYALTY_FEE) revert Fee__InvalidRoyaltyFee();
        s_royaltyFee = royaltyFee_;
    }

    // Setter for royaltyFee
    function setRoyaltyFee(uint256 newRoyaltyFee) external onlyOwner {
        if (newRoyaltyFee > MAX_ROYALTY_FEE) revert Fee__InvalidRoyaltyFee();
        uint256 oldRoyaltyFee = s_royaltyFee;
        s_royaltyFee = newRoyaltyFee;
        emit FeeUpdated(
            "royaltyFee",
            oldRoyaltyFee,
            newRoyaltyFee,
            msg.sender,
            block.timestamp
        );
    }

    // Getter for royaltyFee
    function getRoyaltyFee() external view returns (uint256) {
        return s_royaltyFee;
    }

    // Support royalty via EIP-2981
    function royaltyInfo(
        uint256,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        return (owner(), (salePrice * s_royaltyFee) / 10000);
    }

    // ERC165 interface support
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
