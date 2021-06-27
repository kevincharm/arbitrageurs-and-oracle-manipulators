// SPDX-License-Identifier: MIT

pragma solidity ^0.6;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

// import "hardhat/console.sol";

contract DaiWethTwapPriceOracle {
    using FixedPoint for *;

    uint256 public constant TWAP_PERIOD = 4 hours;
    address private constant daiEthPairAddress =
        0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;

    struct Observation {
        uint256 timestamp;
        uint256 cumPrice0;
        uint256 cumPrice1;
    }
    /** Treat this array as a ringbuffer */
    uint8 private constant OBS_LEN = 6;
    Observation[] private observations;
    uint256 private obs_head = 0;

    constructor() public {
        seedTwap();
    }

    function obsIndex(uint256 head) private pure returns (uint8) {
        return (uint8)(head % OBS_LEN);
    }

    function recordObservation(Observation memory obs) private {
        observations[obsIndex(obs_head++)] = obs;
    }

    function getLatestObservation() private view returns (Observation memory) {
        return observations[obsIndex(obs_head - 1)];
    }

    /**
     * Seed the TWAP as if it had already run for 24h. (with current mid price)
     */
    function seedTwap() private {
        (uint112 daiReserve, uint112 ethReserve, ) =
            IUniswapV2Pair(daiEthPairAddress).getReserves();
        uint256 lastCumPrice0 =
            IUniswapV2Pair(daiEthPairAddress).price0CumulativeLast();
        uint256 lastCumPrice1 =
            IUniswapV2Pair(daiEthPairAddress).price1CumulativeLast();
        FixedPoint.uq112x112 memory ethDaiPrice =
            FixedPoint.fraction(ethReserve, daiReserve);
        FixedPoint.uq112x112 memory daiEthPrice =
            FixedPoint.fraction(daiReserve, ethReserve);
        for (uint8 i = 0; i < OBS_LEN; i++) {
            uint256 newCumPrice0 =
                lastCumPrice0 +
                    FixedPoint.mul(ethDaiPrice, TWAP_PERIOD * i).decode144();
            uint256 newCumPrice1 =
                lastCumPrice1 +
                    FixedPoint.mul(daiEthPrice, TWAP_PERIOD * i).decode144();
            Observation memory newObs =
                Observation(
                    block.timestamp - TWAP_PERIOD * (OBS_LEN - i),
                    newCumPrice0,
                    newCumPrice1
                );
            observations.push(newObs);
            obs_head += 1;

            // Sanity checks
            if (i > 0) {
                Observation memory lastObs =
                    observations[obsIndex(obs_head - 2)];
                require(
                    newObs.timestamp - lastObs.timestamp == TWAP_PERIOD,
                    "4 hours since last update"
                );
                require(
                    (newObs.cumPrice1 - lastObs.cumPrice1) / TWAP_PERIOD ==
                        daiEthPrice.decode(),
                    "Correct cumulative price for 4h"
                );
            }
        }
    }

    /**
     * Update cumulative price, must be run periodically at about ~TWAP_PERIOD
     * either by users of keepers.
     */
    function updateTwap() public {
        Observation memory latestObservation = getLatestObservation();
        (uint112 daiReserve, uint112 ethReserve, uint256 timestamp) =
            IUniswapV2Pair(daiEthPairAddress).getReserves();
        uint256 timeElapsed = timestamp - latestObservation.timestamp;

        require(
            timeElapsed >= TWAP_PERIOD || msg.sender == address(this),
            "Too soon since last TWAP update!"
        );

        uint256 newCumulativePrice0 =
            latestObservation.cumPrice0 +
                uint256(FixedPoint.fraction(ethReserve, daiReserve).decode()) *
                timeElapsed;
        uint256 newCumulativePrice1 =
            latestObservation.cumPrice1 +
                uint256(FixedPoint.fraction(daiReserve, ethReserve).decode()) *
                timeElapsed;

        recordObservation(
            Observation(timestamp, newCumulativePrice0, newCumulativePrice1)
        );
    }

    /**
     * Fetches the 24h TWAP for WETH.
     */
    function getEthTwapPrice() external view returns (uint256) {
        uint256 sumTwap = 0;
        for (uint256 i = obs_head; i < (obs_head + OBS_LEN) - 1; i++) {
            Observation memory obs = observations[obsIndex(i)];
            Observation memory nextObs = observations[obsIndex(i + 1)];
            uint256 avgPrice =
                (nextObs.cumPrice1 - obs.cumPrice1) /
                    (nextObs.timestamp - obs.timestamp);
            sumTwap += avgPrice;
        }

        return sumTwap / (OBS_LEN - 1);
    }
}
