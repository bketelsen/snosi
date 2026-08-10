#!/usr/bin/env bats

setup() {
    REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    FIXTURE="$BATS_TEST_TMPDIR/fixture-$BATS_TEST_NUMBER"
    mkdir -p "$FIXTURE"
}

init_git_fixture() {
    git -C "$FIXTURE" init -q
    git -C "$FIXTURE" config user.email fixture@example.invalid
    git -C "$FIXTURE" config user.name fixture
    git -C "$FIXTURE" add .
}

make_runtime_fixture() {
    cp "$REPO_ROOT/check-runtime-etc-guard.sh" "$FIXTURE/"
    mkdir -p "$FIXTURE/shared/example/tree/usr/libexec"
    cat >"$FIXTURE/shared/example/tree/usr/libexec/example" <<'EOF'
#!/bin/sh
touch /var/lib/example.done
EOF
    init_git_fixture
}

make_duplicate_fixture() {
    cp "$REPO_ROOT/check-duplicate-packages.sh" "$FIXTURE/"
    mkdir -p "$FIXTURE/mkosi.images/example"
    cat >"$FIXTURE/mkosi.images/example/mkosi.conf" <<'EOF'
[Content]
Packages=
    bash
    coreutils
EOF
    init_git_fixture
}

make_native_fixture() {
    cp "$REPO_ROOT/check-native-publication-guard.sh" "$FIXTURE/"
    cp -a "$REPO_ROOT/mkosi.profiles" "$FIXTURE/"
    mkdir -p "$FIXTURE/shared/native-ab/keys" "$FIXTURE/.github/workflows"
    cp -a "$REPO_ROOT/shared/native-ab-secure" "$FIXTURE/shared/"
    cp "$REPO_ROOT/shared/native-ab/keys/import-pubring.gpg" \
        "$FIXTURE/shared/native-ab/keys/"
    cp "$REPO_ROOT/.github/workflows/build-native-images.yml" \
        "$FIXTURE/.github/workflows/"
}

@test "bootc publication guard keeps its exhaustive mutation suite" {
    run "$REPO_ROOT/test/bootc-publication-guard-test.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"passing assertions, 0 failures"* ]]
}

@test "runtime etc guard accepts a runtime marker under var" {
    make_runtime_fixture

    run "$FIXTURE/check-runtime-etc-guard.sh"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "runtime etc guard rejects service enablement mutation" {
    make_runtime_fixture
    printf '%s\n' 'systemctl disable example.service' >> \
        "$FIXTURE/shared/example/tree/usr/libexec/example"
    git -C "$FIXTURE" add .

    run "$FIXTURE/check-runtime-etc-guard.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"runtime systemctl enable/disable mutates /etc"* ]]
    [[ "$output" == *"Runtime /etc mutation check FAILED"* ]]
}

@test "runtime etc guard honors an explained escape marker" {
    make_runtime_fixture
    cat >>"$FIXTURE/shared/example/tree/usr/libexec/example" <<'EOF'
# etc-guard-allow: fixture path is created only at runtime
rm -f /etc/runtime-only-example
EOF
    git -C "$FIXTURE" add .

    run "$FIXTURE/check-runtime-etc-guard.sh"

    [ "$status" -eq 0 ]
}

@test "duplicate package guard accepts unique package entries" {
    make_duplicate_fixture

    run "$FIXTURE/check-duplicate-packages.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No duplicate package entries found"* ]]
}

@test "duplicate package guard reports package and source lines" {
    make_duplicate_fixture
    cat >>"$FIXTURE/mkosi.images/example/mkosi.conf" <<'EOF'
    bash
EOF
    git -C "$FIXTURE" add .

    run "$FIXTURE/check-duplicate-packages.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Duplicate package entries in mkosi.images/example/mkosi.conf"* ]]
    [[ "$output" == *"bash: lines 3, 5"* ]]
}

@test "native publication guard accepts the committed publication contract" {
    make_native_fixture

    run "$FIXTURE/check-native-publication-guard.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"cayo-ab/mkosi.conf satisfies the native publication guard"* ]]
    [[ "$output" == *"cayo-ab-raw/mkosi.conf remains unpublishable"* ]]
}

@test "native publication guard rejects a raw fixture publication marker" {
    make_native_fixture
    printf '%s\n' 'SecureBoot=yes' >> \
        "$FIXTURE/mkosi.profiles/cayo-ab-raw/mkosi.conf"

    run "$FIXTURE/check-native-publication-guard.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"raw dev fixture must never carry publication markers"* ]]
}

@test "native publication guard rejects a missing update pubring" {
    make_native_fixture
    rm "$FIXTURE/shared/native-ab/keys/import-pubring.gpg"

    run "$FIXTURE/check-native-publication-guard.sh"

    [ "$status" -eq 1 ]
    [[ "$output" == *"update pubring not committed"* ]]
}
