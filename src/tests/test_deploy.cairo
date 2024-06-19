use trustlines_erc::tests::utils::{deploy_token, OWNER, ISSUER, THIRD_PARTY};


#[test]
fn test_deploy() {
    let _ = deploy_token(0, OWNER(), OWNER(), ISSUER(), THIRD_PARTY());
}

