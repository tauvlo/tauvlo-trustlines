use trustlines_erc::tests::utils::{deploy_token, OWNER, ISSUER, THIRD_PARTY};

use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
use trustlines_erc::traits::ItrustERC20DispatcherTrait;
use trustlines_erc::traits::ItrustERC20Dispatcher;
use trustlines_erc::constants::{OWNER_ROLE, ISSUER_ROLE, THIRD_PARTY_ROLE};

use trustlines_erc::contract::ITrustlinesDispatcherTrait;
use trustlines_erc::contract::ITrustlinesDispatcher;

#[test]
fn test_deploy() {
    let token_addr = deploy_token(0, OWNER(), OWNER(), ISSUER(), THIRD_PARTY());
    let token = ItrustERC20Dispatcher { contract_address: token_addr };

    assert(token.total_supply() == 0, 'Supply wrong');
    assert(token.name() == "Token", 'Name wrong');
    assert(token.symbol() == "TKN", 'Symbol wrong');
    assert(token.decimals() == 18, 'Decimals wrong');

    assert(token.has_role(DEFAULT_ADMIN_ROLE, OWNER()), 'Wrong owner role');
    assert(token.has_role(OWNER_ROLE, OWNER()), 'Wrong owner role');
    assert(token.has_role(ISSUER_ROLE, ISSUER()), 'Wrong issuer role');
    assert(token.has_role(THIRD_PARTY_ROLE, THIRD_PARTY()), 'Wrong 3rd party role');
}
