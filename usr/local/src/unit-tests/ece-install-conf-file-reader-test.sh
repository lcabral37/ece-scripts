#! /usr/bin/env bash
## author: torstein@escenic.com

test_can_parse_yaml_conf_credentials() {
  local yaml_file=
  yaml_file=$(mktemp)
  local escenic_download_user=foouser
  local escenic_download_password=barpassword

  cat > "${yaml_file}" <<EOF
---
credentials:
  - site: maven.escenic.com
    user: ${escenic_download_user}
    password: ${escenic_download_password}
EOF

  unset technet_user
  unset technet_password
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set technet_user" "${technet_user}"
  assertEquals "Should set technet_user" "${escenic_download_user}" "${technet_user}"

  assertNotNull "Should set technet_password" "${technet_password}"
  assertEquals "Should set technet_password" "${escenic_download_password}" "${technet_password}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_packages() {
  local yaml_file=
  yaml_file=$(mktemp)
  local package_name=escenic-content-engine
  local package_version=6.1.0-2

  cat > "${yaml_file}" <<EOF
---
packages:
  - name: ${package_name}
    version: ${package_version}
EOF
  unset fai_package_map
  declare -A fai_package_map
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"

  for name in "${!fai_package_map[@]}"; do
    local version=${fai_package_map[${name}]}
    assertEquals "Should have parsed package name" "${package_name}" "${name}"
    assertEquals "Should have parsed package version" "${package_version}" "${version}"
  done

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_packages_multiple() {
  local yaml_file=
  yaml_file=$(mktemp)

  local package_name=escenic-content-engine
  local package_version=6.1.0-2
  local package_name_without_version=escenic-video

  cat > "${yaml_file}" <<EOF
---
packages:
  - name: ${package_name}
    version: ${package_version}
  - name: ${package_name_without_version}
EOF
  unset fai_package_map
  declare -A fai_package_map
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"

  for name in "${!fai_package_map[@]}"; do
    local version=${fai_package_map[${name}]}

    if [[ "${name}" == "${package_name_without_version}" ]]; then
      assertNull "Package without version should have no version" \
                 "${version}"
    else
      assertEquals "Should have parsed package version" "${package_version}" "${version}"
    fi
  done

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_java_home() {
  local yaml_file=
  yaml_file=$(mktemp)
  local foo_java_home=/usr/lib/jvm/foo-java-sdk

  cat > "${yaml_file}" <<EOF
---
environment:
  - java_home: ${foo_java_home}
EOF

  unset java_home
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set java_home" "${java_home}"
  assertEquals "Should set java_home" "${foo_java_home}" "${java_home}"
  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_use_escenic_packages() {
  local yaml_file=
  yaml_file=$(mktemp)
  local foo_java_home=/usr/lib/jvm/foo-java-sdk

  cat > "${yaml_file}" <<EOF
---
environment:
  - use_escenic_packages: yes
EOF

  unset fai_package_enabled
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_package_enabled" "${fai_package_enabled}"
  assertEquals "Should set fai_package_enabled" 1 "${fai_package_enabled}"
  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_presentation_install() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
profiles:
  - presentation: yes
EOF

  unset fai_presentation_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_presentation_install" "${fai_presentation_install}"
  assertEquals "Should set fai_presentation_install" 1 "${fai_presentation_install}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_search_install() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
profiles:
  - search: yes
EOF

  unset fai_search_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_search_install" "${fai_search_install}"
  assertEquals "Should set fai_search_install" 1 "${fai_search_install}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_editor_install() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
profiles:
  - editor: yes
    port: 8080
    name: engine1
EOF

  unset fai_editor_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_editor_install" "${fai_editor_install}"
  assertEquals "Should set fai_editor_install" 1 "${fai_editor_install}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_editor_install_multi_profiles() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
profiles:
  - editor: yes
  - search: yes
  - db: no
EOF

  unset fai_editor_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_editor_install" "${fai_editor_install}"
  assertEquals "Should set fai_editor_install" 1 "${fai_editor_install}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_db_install() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
profiles:
  - db: yes
    port: 8080
    name: engine1
EOF

  unset fai_db_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_db_install" "${fai_db_install}"
  assertEquals "Should set fai_db_install" 1 "${fai_db_install}"

  rm -rf "${yaml_file}"
}

test_can_parse_yaml_conf_cache_install() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
profiles:
  - cache: yes
EOF

  unset fai_cache_install
  parse_yaml_conf_file_or_source_if_sh_conf "${yaml_file}"
  assertNotNull "Should set fai_cache_install" "${fai_cache_install}"
  assertEquals "Should set fai_cache_install" 1 "${fai_cache_install}"

  rm -rf "${yaml_file}"
}

test_can_recognise_a_yaml_conf_file() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
---
foo: bar
EOF

  local expected=0
  is_yaml "${yaml_file}" && actual=$? || actual=$?
  assertEquals "${expected}" "${actual}"

  rm -rf "${yaml_file}"
}

test_can_recognise_a_conf_file_thats_not_yaml_xml() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
<foo>bar</foo>
EOF

  local expected=1
  is_yaml "${yaml_file}" && actual=$? || actual=$?
  assertEquals "${expected}" "${actual}"

  rm -rf "${yaml_file}"
}

test_can_recognise_a_conf_file_thats_not_yaml_conf() {
  local yaml_file=
  yaml_file=$(mktemp)
  cat > "${yaml_file}" <<EOF
<foo>bar</foo>
EOF

  local expected=1
  is_yaml "${yaml_file}" && actual=$? || actual=$?
  assertEquals "${expected}" "${actual}"

  rm -rf "${yaml_file}"
}

## @override shunit2
setUp() {
  source "$(dirname "$0")/../../../share/escenic/ece-scripts/ece-install.d/conf-file-reader.sh"
}

## @override shunit2
tearDown() {
  :
}

main() {
  . "$(dirname "$0")"/shunit2/source/2.1/src/shunit2
}

main "$@"
