#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
"${COMPILER[@]}" -target "$HOST_TARGET" "$PROJECT_ROOT/Source/NetworkPolicy.swift" "$PROJECT_ROOT/Tests/NetworkPolicyTests.swift" -o "$BUILD_DIR/network-policy-tests"
"$BUILD_DIR/network-policy-tests"
"${COMPILER[@]}" -target "$HOST_TARGET" "$PROJECT_ROOT/Source/Shared.swift" "$PROJECT_ROOT/Tests/SessionPolicyTests.swift" -framework IOKit -o "$BUILD_DIR/session-policy-tests"
"$BUILD_DIR/session-policy-tests"
"${COMPILER[@]}" -target "$HOST_TARGET" "$PROJECT_ROOT/Source/ReadyAcknowledgement.swift" "$PROJECT_ROOT/Tests/ReadyAcknowledgementTests.swift" -o "$BUILD_DIR/ready-acknowledgement-tests"
"$BUILD_DIR/ready-acknowledgement-tests"
"${COMPILER[@]}" -target "$HOST_TARGET" "$PROJECT_ROOT/Source/Shared.swift" "$PROJECT_ROOT/Source/ReadyAcknowledgement.swift" "$PROJECT_ROOT/Source/Guardian.swift" -framework IOKit -o "$BUILD_DIR/guardian-self-test"
"$BUILD_DIR/guardian-self-test" --self-test
