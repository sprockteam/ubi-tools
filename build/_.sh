#!/usr/bin/env bash

build_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_dir="${build_dir%/*}"
script_name="easy-ubnt.sh"
script_output="${script_dir}/${script_name}"
tests_name="tests.sh"
script_tests="${script_dir}/${tests_name}"
source "${build_dir}/_config.sh"

echo "Saving script to ${script_output}"

cd "${build_dir}" && cat *-*.sh | sed -e '/^### End ###$/d' >"${script_output}"

if command -v "shellcheck" &>/dev/null; then
  shellcheck "${script_output}"
fi

if command -v "duck" &>/dev/null; then
  duck --assumeyes --existing "overwrite" --username "${test_server_username}" --upload "sftp://${test_server}/${test_server_path}/${test_server_username}/${script_name}" "${script_output}"
  duck --assumeyes --existing "overwrite" --username "${test_server_username}" --upload "sftp://${test_server}/${test_server_path}/${test_server_username}/${tests_name}" "${script_tests}"
fi