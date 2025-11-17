**Project Overview**

OracleStablecoin (OSC) — a minimal, audit-friendly over-collateralized stablecoin framework.

Key ideas:
- **Peg**: Algorithmic stablecoin pegged to USD via Chainlink price feeds.
- **Collateral**: Users supply external crypto (WETH, WBTC) to mint OSC.
- **Safety**: Health-factor-based minting and liquidation to protect the protocol.

**Repository layout**
- `src/OracleStablecoin.sol` — ERC20-based token with restricted `mint`/`burn` (owner-only).
- `src/OSCEngine.sol` — Protocol engine handling collateral management, minting, redeeming, and liquidation logic.
- `src/libraries/OracleLib.sol` — Chainlink price-feed helper that validates freshness.
- `test/` — Unit and invariant tests (Foundry).
- `script/` — Deployment helpers.

**Contracts (short)**
- `OracleStablecoin`:
    - Extends OpenZeppelin `ERC20Burnable` + `Ownable`.
    - `mint(address to, uint256 amount)` and `burn(uint256 amount)` are `onlyOwner`.
    - Uses checks to prevent zero amounts and zero addresses.
- `OSCEngine`:
    - Manages allowed collateral tokens and their Chainlink price feeds.
    - Users deposit collateral via `depositCollateral(token, amount)`.
    - Users mint OSC via `mintOsc(amount)` — health factor is enforced.
    - Redeem via `redeemCollateral(token, amount)` and combined `redeemCollateralForOsc` flows.
    - Liquidation: `liquidate(collateral, user, debtToCover)` lets a liquidator repay part of a user's debt and claim discounted collateral + liquidation bonus.
    - Uses `OracleLib.staleCheckLatestRoundData` to ensure price freshness.

**Important constants / behavior**
- `LIQUIDATION_THRESHOLD = 50` (50%): collateral is discounted to compute allowed borrow.
- `LIQUIDATION_BONUS = 10` (10%): bonus awarded to liquidator.
- `MIN_HEALTH_FACTOR = 1e18`: minimum allowed HF (1.0 when using 18-decimal precision).
- Health factor formula: ((collateralValueUsd * LIQUIDATION_THRESHOLD / 100) * PRECISION) / totalOscMinted.

**Testing & Invariants**
- Unit tests: `test/unit` (e.g. `OSCEngineTest.t.sol`) — constructor, deposit, mint, redeem, burn, liquidation edge cases.
- Invariant tests: `test/invariants/Invariant.t.sol` and `Handler.t.sol` — checks that protocol collateral value >= total OSC supply.

**Quick commands (Foundry)**
- Run tests: `forge test`.
- Run a single test file: `forge test --match-path test/unit/OSCEngineTest.t.sol`.
- Run invariant property tests: `forge test --match-path test/invariants`.
- Coverage: `forge coverage` (already available in this workspace).

**How to use (dev)**
1. Start by deploying the contracts via the provided script: `script/DeployOSC.s.sol` (use `forge script` or inspect the script for network configuration).
2. Interact locally in tests or via Foundry `cast` and `anvil` with deployed addresses.
3. Typical flow:
     - Mint collateral tokens in tests/mocks (see `test/mocks/ERC20Mock.sol`).
     - Approve and `depositCollateral` to `OSCEngine`.
     - `mintOsc` up to the health-factor limit.
     - When below the health factor, positions are subject to `liquidate` by third parties.
