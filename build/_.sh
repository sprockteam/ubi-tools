#!/usr/bin/env bash

build_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_dir="${build_dir%/*}"
script_name="easy-ubnt.sh"
script_output="${script_dir}/${script_name}"

echo "Saving script to ${script_output}"

cd "${build_dir}" && cat *-*.sh | sed -e '/^### End ###$/d' >"${script_output}"
