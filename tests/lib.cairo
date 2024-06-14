#[test]
fn example_passing_test() {
    assert(1 == 1, 'This should pass');
}

#[test]
#[should_panic]
fn example_failing_test() {
    assert(1 == 0, 'This should fail');
}


#[test]
#[should_panic(expected: ('expected message',))]
fn example_failing_test_with_expected_message() {
    assert(1 == 0, 'expected message');
}

