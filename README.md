# trustERC20

This project implements a trustlines-based ERC20 token smart contract in Cairo. It combines standard ERC20 functionality with additional features such as trustlines, holding limits, asset freezing, and transfer validation.


## Table of Contents

1. [Components](#components)
   - [Trustlines Component](#trustlines-component)
   - [Holding Limits Component](#holding-limits-component)
2. [Contract Overview](#contract-overview)
   - [Key Features](#key-features)
   - [Roles and Permissions](#roles-and-permissions)
3. [Development](#development)
   - [Prerequisites](#prerequisites)
   - [Installation](#installation)
   - [Running Tests](#running-tests)
   - [CI/CD](#cicd)
4. [Usage](#usage)
5. [Contributing](#contributing)

## Components
### Trustlines Component

The Trustlines component allows users to establish bilateral lines (trustlines) with each other. Key features include:

- Proposing new trustlines
    - Used for proposal of new trustline between caller and another address
- Accepting trustline proposals 
    - Used for accepting new trustline proposal between caller and another address
- Proposing modification of existing trustlines
    - Used for proposing a modification of new trustline between caller and another address
- Accepting modification of existing trustlines
    - Used for accepting of proposed trustline modification between caller and another user
- Cancelling trustline proposals    
    - Used for cancelling any proposal
- Decreasing trustline limits   
    - Used for unilateral decrease of trustline limit 
- Trustline transfer
    - Doesn't actually transfer any tokens, just tracks the trustline usage and verifies that it's within limits

### Holding Limits Component

The Holding Limits component enforces restrictions on the maximum number of tokens an address can hold. It includes:

- Setting hard holding limits (by authorized roles)
    - Absolute maximum an address can hold, acts as a limit for soft limit
- Setting soft holding limits (by users themselves)
    - Set by an user in order to limit their holdings, can never exceed hard limit
- Validating token holdings against these limits
    - Validates that amount is not over (soft) holding limit


## Contract Overview

The main contract, `trustERC20`, combines standard ERC20 functionality with the Trustlines and Holding Limits components, along with additional features.

### Key Features

- **ERC20 Functionality**: Standard token operations (transfer, approve, etc.)
- **Trustlines**: Allows users to establish bilateral credit lines.
- **Holding Limits**: Enforces maximum token holding limits for addresses.
- **Address Freezing**: Allows freezing of addresses.
- **Transfer Validation**: Optional validation of transfers by an external contract.
- **Upgradability**: The contract can be upgraded.
- **Asset Pull**: Force transfer

### Notes:
- Contract currently does not implement functionality for (temporarily) stopping all transfers altogether
- `mint` and `burn` functions are currently commented out, uncomment (in inerface as well) if necessary
- `delete_trustline` function currently commented out, see comment above it for reasoning
- During trustline transfer, if recipient is the Marketplace, then the limit on transfer is disabled
- When user decreases trustline, it could block the trustline if the usage is above new effective amount
- When new trustline proposal is canceled, the trustline still exists, so to propose new limit again, `propose_modify_trustline` needs to be used
- If transfer validation is enabled then Marketplace MUST be compatible with interface `ITransferValidator` in `src/contract.cairo`, otherwise all transfers might fail


### Roles and Permissions
The contract uses OpenZeppelin's AccessControl for role-based permissions:

-  **DEFAULT_ADMIN_ROLE**: Has overall administrative privileges.
    - `Owner` address has this role
-  **OWNER_ROLE**: Can upgrade the contract.
    - `Owner` address has this role
-  **ISSUER_ROLE**: Has permissions to:
    - `Issuer` address has this role
   - Freeze/unfreeze assets
   - Pull assets (force transfer)
   - Set hard holding limits
   - Enable/disable transfer validation

- Additionaly, the contract keeps a **Marketplace** adress, which:
    - Validates transfers if transfer validation is enabled
        - If transfer validation is enabled then Marketplace MUST be compatible with interface `ITransferValidator` in `src/contract.cairo`, otherwise all transfers will fail
    - Doesn't use trustline limit if Marketplace is being transferred to


## Developement

### Prerequisites

- [Cairo](https://github.com/starkware-libs/cairo) 
- [Scarb](https://github.com/software-mansion/scarb) - version 2.6.3
    - Install: 
    ```bash
        curl --proto '=https' --tlsv1.2 -sSf https://docs.swmansion.com/scarb/install.sh | sh -s -- -v 2.6.3
    ```
- [Starknet Foundry](https://github.com/foundry-rs/starknet-foundry) - version 0.23.0
    - Install:
    ```bash
        curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
        snfoundryup -v 0.23.0
    ```
    
### Running Tests
To run the test suite from root of project:
```bash
scarb test
```

### CI/CD

This project uses GitHub Actions for continuous integration and deployment. The workflow includes:

- Building the project on every push and pull request
- Running tests on every push and pull request
- Checking code format with `scarb fmt --check` on every push and pull request

## Usage
- Deploy process is described using `starkli`, however any tool can be used (such as `sncast`, which is bundled in `starknet-foundry`).

- **Build contract**:
```bash
scarb build
```

- **Declare contract**
```bash
starkli declare ./target/dev/trustlines_erc_trustERC20.contract_class.json
```

- **Deploy contract**
```bash
export DECLARED_HASH=<insert hash of the declared contract>
export INITIAL_SUPPLY=(<initial supply high> <initial supply low>)
export RECIPIENT=<insert initial supply recipient address>
export OWNER=<insert owner address>
export ISSUER=<insert issuer address>
export MARKETPLACE=<insert marketplace address>
export VALIDATE_TRANSFERS=<0 or 1 based on whether to enable transfer validation>

starkli deploy $DECLARED_HASH $INITIAL_SUPPLY $RECIPIENT $OWNER $ISSUER $MARKETPLACE $VALIDATE_TRANSFERS
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

