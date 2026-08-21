#!/bin/bash

# bats file_tags=pre-merge

load helpers/setup

TEST_PASSWORD="test"

# Characters the shell would otherwise expand, split on, or execute.

TEST_UNSAFE_PASSWORD='all'"'"'of$it `x` ;#|<>'

_getArchiveFile() {
	find shared_workspaces -maxdepth 1 -type f | head -n 1
}

_assertArchiveEncrypted() {
	local password="${1}"

	local archive
	archive="$(_getArchiveFile)"

	run 7z l "${archive}" </dev/null

	assert_failure

	run 7z l -slt -p"${password}" "${archive}"

	assert_success
	assert_output --partial "7zAES"
}

_assertArchiveNotEncrypted() {
	local archive
	archive="$(_getArchiveFile)"

	run 7z l -slt "${archive}" </dev/null

	assert_success
	refute_output --partial "7zAES"
}

setup_file() {
	BATS_TEST_NAME_PREFIX="Share encryption: "
	export BATS_TEST_NAME_PREFIX

	common_setup_file
}

setup() {
	common_setup

	unset LEC_SHARE_ENCRYPT_MODE
}

teardown() {
	common_teardown
}

@test "The --encrypt flag encrypts the archive" {
	_debug "RUNNING ${BATS_TEST_NAME}"

	run _lec share --encrypt < <(printf "%s\n%s\n" "${TEST_PASSWORD}" "${TEST_PASSWORD}")

	assert_success

	_assertArchiveEncrypted "${TEST_PASSWORD}"
}

@test "The --no-encrypt flag leaves the archive unencrypted" {
	_debug "RUNNING ${BATS_TEST_NAME}"

	run _lec share --no-encrypt </dev/null

	assert_success

	_assertArchiveNotEncrypted
}

@test "LEC_SHARE_ENCRYPT_MODE=always encrypts without prompting" {
	_debug "RUNNING ${BATS_TEST_NAME}"

	export LEC_SHARE_ENCRYPT_MODE=always

	run _lec share < <(printf "%s\n%s\n" "${TEST_PASSWORD}" "${TEST_PASSWORD}")

	assert_success
	refute_output --partial "Encrypt the workspace archive"

	_assertArchiveEncrypted "${TEST_PASSWORD}"
}

@test "An invalid LEC_SHARE_ENCRYPT_MODE fails without creating an archive" {
	_debug "RUNNING ${BATS_TEST_NAME}"

	export LEC_SHARE_ENCRYPT_MODE=bogus

	run _lec share </dev/null

	assert_failure
	assert_output --partial "is not a valid value for LEC_SHARE_ENCRYPT_MODE"

	assert [ -z "$(_getArchiveFile)" ]
}

@test "A password containing shell metacharacters is passed through intact" {
	_debug "RUNNING ${BATS_TEST_NAME}"

	run _lec share --encrypt < <(printf "%s\n%s\n" "${TEST_UNSAFE_PASSWORD}" "${TEST_UNSAFE_PASSWORD}")

	assert_success
	refute_output --partial "${TEST_UNSAFE_PASSWORD}"

	_assertArchiveEncrypted "${TEST_UNSAFE_PASSWORD}"
}