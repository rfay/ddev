#!/usr/bin/env bats

setup() {
  PROJNAME=my-topcoat-site
  load 'common-setup'
  _common_setup
}

# executed after each test
teardown() {
  _common_teardown
}

@test "Topcoat quickstart with $(ddev --version)" {
  TOPCOAT_SITENAME=${PROJNAME}
  run -0 mkdir -p ${TOPCOAT_SITENAME}
  cd ${TOPCOAT_SITENAME}

  run -0 ddev config --project-type=generic --webserver-type=generic \
    --webimage-extra-packages=build-essential \
    --web-environment-add=CARGO_TARGET_DIR=/mnt/ddev-global-cache/topcoat/${TOPCOAT_SITENAME}/target \
    --omit-containers=db

  cat <<'EOF' > .ddev/web-build/Dockerfile.topcoat
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path \
    && /usr/local/cargo/bin/cargo install --locked topcoat-cli \
    && chmod -R a+rwX /usr/local/rustup /usr/local/cargo \
    && echo 'export PATH="/usr/local/cargo/bin:$PATH"' > /etc/bashrc/topcoat.bashrc
EOF
  cat <<'EOF' > .ddev/config.topcoat.yaml
web_extra_daemons:
    - name: "topcoat"
      command: "HOST=0.0.0.0 PORT=3000 /usr/local/cargo/bin/topcoat dev"
      directory: /var/www/html
web_extra_exposed_ports:
    - name: "topcoat"
      container_port: 3000
      http_port: 80
      https_port: 443
EOF
  assert_file_exist .ddev/web-build/Dockerfile.topcoat
  assert_file_exist .ddev/config.topcoat.yaml

  run -0 ddev start -y

  run -0 ddev exec 'topcoat new /tmp/app --name "${DDEV_SITENAME}" --recommended --no-interactive && cp -a /tmp/app/. . && rm -rf /tmp/app'
  assert_file_exist Cargo.toml
  assert_file_exist src/app.rs

  run -0 ddev exec cargo run -- toasty migration generate
  run -0 ddev exec cargo run -- toasty migration apply
  assert_file_exist data.db

  run -0 ddev restart

  _extra_info

  DDEV_DEBUG=true run -0 ddev launch
  assert_output --partial "FULLURL ${PRIMARY_URL}"

  # topcoat dev compiles the app after the restart, so wait for it to serve
  for _ in $(seq 1 60); do
    curl -sf ${PRIMARY_URL} >/dev/null && break
    sleep 5
  done

  run -0 curl -sf ${PRIMARY_URL}
  assert_output --partial "<title>${PROJNAME}</title>"
  assert_output --partial "save to see your changes"

  # The todo example reads from the SQLite database
  run -0 curl -sf ${PRIMARY_URL}/todos
}
