// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 * @title OracleLib
 * @author Victor_TheOracle
 * @notice Utilities for checking Chainlink Aggregator price freshness and retrieving latest round data.
 */
library OracleLib {

    error OracleLib__StalePriceData();

    uint256 private constant TIMEOUT = 2 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface _priceFeed) public view returns (uint80, int256, uint256, uint256, uint80 ) {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = _priceFeed.latestRoundData();
        
        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;

        if (timeSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePriceData();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}