#!/usr/bin/env bash
# Load OpenBao credentials for the other scripts in this directory.
# Secret values live in ~/.config/lumynex/openbao.env or the environment.
# This file has none.

openbao_env_file() {
  printf '%s\n' "${OPENBAO_ENV_FILE:-${HOME}/.config/lumynex/openbao.env}"
}

# This Mac has Ethernet (en0) and Wi-Fi (en1) on 192.168.4.0/22. bao dials
# once. nc uses connectx and can succeed on the other interface. If nc opens
# the port, let bao dial. The Python probe only runs when nc cannot, and then
# it refreshes ARP and pins bao to a source that completes a TCP handshake.
openbao_pin_route() {
  local picked proxy_port rest hostport host port
  rest="${BAO_ADDR#*://}"
  hostport="${rest%%/*}"
  if [[ "${hostport}" != \[* && "${hostport}" == *:* ]]; then
    host="${hostport%:*}"
    port="${hostport##*:}"
    if /usr/bin/nc -z -G 3 "${host}" "${port}" 2>/dev/null; then
      return 0
    fi
  fi
  if ! picked="$(
    /usr/bin/python3 - "$BAO_ADDR" <<'PY'
import socket, subprocess, sys

raw = sys.argv[1]
rest = raw.split("://", 1)[-1]
hostport = rest.split("/", 1)[0]
if hostport.startswith("["):
    print("ok")
    raise SystemExit(0)
host, sep, port_s = hostport.rpartition(":")
if sep != ":":
    print("ok")
    raise SystemExit(0)
port = int(port_s)

errors = []

def attempt(src):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        if src:
            sock.bind((src, 0))
        sock.connect((host, port))
        return True
    except OSError as exc:
        label = src or "default"
        errors.append(f"{label}: {exc.strerror or exc} (errno {exc.errno})")
        return False
    finally:
        sock.close()

def sources():
    found = []
    iface = ""
    for line in subprocess.check_output(["ifconfig"], text=True).splitlines():
        if line and not line[0].isspace():
            iface = line.split(":", 1)[0]
            continue
        if iface not in ("en0", "en1"):
            continue
        # ifconfig indents with a tab, so match the split token, not " inet ".
        parts = line.split()
        if len(parts) >= 2 and parts[0] == "inet" and parts[1].startswith("192.168."):
            found.append((iface, parts[1]))
    return found

if attempt(None):
    print("ok")
    raise SystemExit(0)
for iface, _src in sources():
    subprocess.run(
        ["ping", "-c", "1", "-W", "500", "-b", iface, host],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
if attempt(None):
    print("ok")
    raise SystemExit(0)
for _iface, src in sources():
    if attempt(src):
        print(f"proxy {src} {host} {port}")
        raise SystemExit(0)
print("error: TCP connect failed:", file=sys.stderr)
for line in errors:
    print(f"error: {line}", file=sys.stderr)
raise SystemExit(1)
PY
  )"; then
    echo "error: no TCP handshake to ${BAO_ADDR} from Ethernet en0 or Wi-Fi en1." >&2
    return 1
  fi
  if [[ "${picked}" == "ok" ]]; then
    return 0
  fi
  local src host port portfile i
  read -r _kind src host port <<<"${picked}"
  portfile="$(mktemp)"
  /usr/bin/python3 - "$src" "$host" "$port" >"${portfile}" <<'PY' &
import socket, sys, threading

src, host, port = sys.argv[1], sys.argv[2], int(sys.argv[3])

def pipe(left, right):
    try:
        while True:
            data = left.recv(65536)
            if not data:
                break
            right.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (left, right):
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

def handle(client):
    remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        remote.bind((src, 0))
        remote.connect((host, port))
    except OSError:
        client.close()
        remote.close()
        return
    left = threading.Thread(target=pipe, args=(client, remote), daemon=True)
    right = threading.Thread(target=pipe, args=(remote, client), daemon=True)
    left.start()
    right.start()
    left.join()
    right.join()

listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", 0))
listener.listen(16)
print(listener.getsockname()[1], flush=True)
while True:
    client, _addr = listener.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
PY
  OPENBAO_PROXY_PID=$!
  trap 'kill "${OPENBAO_PROXY_PID}" 2>/dev/null || true' EXIT
  proxy_port=""
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [[ -s "${portfile}" ]]; then
      proxy_port="$(head -n 1 "${portfile}")"
      break
    fi
    sleep 0.05
  done
  rm -f "${portfile}"
  if [[ -z "${proxy_port}" ]]; then
    echo "error: OpenBao local proxy did not start." >&2
    return 1
  fi
  export BAO_ADDR="http://127.0.0.1:${proxy_port}"
}

openbao_load() {
  local env_file
  if [[ -x /opt/homebrew/bin/bao ]]; then
    export PATH="/opt/homebrew/bin:${PATH}"
  fi
  env_file="$(openbao_env_file)"
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
  if [[ -z "${BAO_ADDR:-}" ]]; then
    echo "BAO_ADDR is unset. Set it in the environment or in ${env_file}." >&2
    return 1
  fi
  openbao_pin_route
  if [[ -n "${BAO_TOKEN:-}" ]]; then
    return 0
  fi
  if [[ -z "${BAO_ROLE_ID:-}" || -z "${BAO_SECRET_ID:-}" ]]; then
    echo "No BAO_TOKEN. Put BAO_TOKEN, or BAO_ROLE_ID and BAO_SECRET_ID, in ${env_file}." >&2
    return 1
  fi
  BAO_TOKEN="$(
    bao write -field=token auth/approle/login \
      role_id="${BAO_ROLE_ID}" \
      secret_id="${BAO_SECRET_ID}"
  )"
  export BAO_TOKEN
}
