#!/usr/bin/env bash

IPSEC_CONFIG_PATH="/etc/ipsec.conf"
readonly IPSEC_CONFIG_PATH
IPSEC_SECRET_CONFIG_PATH="/etc/ipsec.secrets"
readonly IPSEC_SECRET_CONFIG_PATH
XL2TP_CONFIG_PATH="/etc/xl2tpd/xl2tpd.conf"
readonly XL2TP_CONFIG_PATH
PPP_CONFIG_PATH="/etc/ppp/options.l2tpd.client"
readonly PPP_CONFIG_PATH
XL2TP_RUN_PATH="/var/run/xl2tpd"
readonly XL2TP_RUN_PATH
VPN_NAME="myvpn"
readonly VPN_NAME

cleanup() {
  echo
  echo "[INFO] Start gracefully shutdown..."
  echo

  echo "d $VPN_NAME" > "$XL2TP_RUN_PATH/l2tp-control"
  sleep 2

  ipsec stop
  route del "$VPN_ADDR"

  xl2tp_pid=$(pgrep xl2tpd)
  if [ -n "$xl2tp_pid" ]; then
    kill -2 "$xl2tp_pid"
  fi

  : > "$XL2TP_RUN_PATH/l2tp-control"
  echo
}

trap cleanup INT TERM SIGINT SIGTERM SIGILL

file_env() {
  local var="$1"
  local fileVar="${var}_FILE"
  local def="${2:-}"
  if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
    echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
    exit 1
  fi
  local val="$def"
  if [ "${!var:-}" ]; then
    val="${!var}"
  elif [ "${!fileVar:-}" ]; then
    val="$(<"${!fileVar}")"
  fi
  export "$var"="$val"
  unset "$fileVar"
}

function docker_setup_env() {
  file_env 'VPN_ADDR'
  file_env 'VPN_USER'
  file_env 'VPN_PASS'
  file_env 'VPN_PSK'
  file_env 'VPN_IPSEC_CUSTOM_CONFIG_PATH'
  file_env 'VPN_XL2TP_CUSTOM_CONFIG_PATH'
  file_env 'VPN_PPP_CUSTOM_CONFIG_PATH'
  file_env 'DISABLE_ADD_ROUTE'
  file_env 'DNS_IP_LIST'
}

check_require_variable_set() {
  if [ -z "$VPN_ADDR" ] && [ -z "$VPN_USER" ] && [ -z "$VPN_PASS" ] && [ -z "$VPN_PSK" ]; then
    echo "Variables VPN_ADDR, VPN_USER and VPN_PASS and VPN_PSK must be set."
    exit 1
  fi
}

config_ipsec() {
  if [ -n "$VPN_IPSEC_CUSTOM_CONFIG_PATH" ] && [ -f "$VPN_IPSEC_CUSTOM_CONFIG_PATH" ]; then
    cat "$VPN_IPSEC_CUSTOM_CONFIG_PATH" > "$IPSEC_CONFIG_PATH"
  else
    cat > "$IPSEC_CONFIG_PATH" <<-EOF
conn $VPN_NAME
  auto=add
  keyexchange=ikev1
  authby=secret
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  rightprotoport=17/1701
  right=$VPN_ADDR
  ike=aes128-sha1-modp2048
  esp=aes128-sha1
EOF
  fi

  cat > "$IPSEC_SECRET_CONFIG_PATH" <<-EOF
  : PSK "$VPN_PSK"
EOF

  chmod 600 "$IPSEC_SECRET_CONFIG_PATH"
}

config_xl2tpd() {
  if [ -n "$VPN_XL2TP_CUSTOM_CONFIG_PATH" ] && [ -f "$VPN_XL2TP_CUSTOM_CONFIG_PATH" ]; then
      cat "$VPN_XL2TP_CUSTOM_CONFIG_PATH" > "$XL2TP_CONFIG_PATH"
  else
    cat > "$XL2TP_CONFIG_PATH" <<-EOF
[lac $VPN_NAME]
lns = $VPN_ADDR
ppp debug = yes
pppoptfile = $PPP_CONFIG_PATH
length bit = yes
EOF
  fi

  if [ -n "$VPN_XL2TP_CUSTOM_CONFIG_PATH" ] && [ -f "$VPN_XL2TP_CUSTOM_CONFIG_PATH" ]; then
    cat "$VPN_PPP_CUSTOM_CONFIG_PATH" > "$PPP_CONFIG_PATH"
  else
    cat > "$PPP_CONFIG_PATH" <<-EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-chap
noccp
noauth
mtu 1280
mru 1280
noipdefault
defaultroute
usepeerdns
connect-delay 5000
name "$VPN_USER"
password "$VPN_PASS"
EOF
  fi

  chmod 600 "$PPP_CONFIG_PATH"

  rm -rf "$XL2TP_RUN_PATH"
  mkdir -p "$XL2TP_RUN_PATH"
  touch "$XL2TP_RUN_PATH/l2tp-control"
}

run() {
  config_ipsec

  config_xl2tpd

  ipsec start
  sleep 1
  ipsec reload
  sleep 3

  ipsec_res=$(ipsec up $VPN_NAME 2>&1)
  if ! echo "$ipsec_res" | grep -qe "connection '$VPN_NAME' established successfully"; then
    echo "[ERR] Couldn't connect ipsec"
    echo
    echo "$ipsec_res"
    exit 1
  fi

  {
    xl2tpd -D
  } <&0 &

  sleep 3
  echo "c $VPN_NAME" > "$XL2TP_RUN_PATH/l2tp-control"

  sleep 6
  if ! ip -br a | grep -q "ppp0"; then
    echo "[ERR] Couldn't bind ppp0"
    exit 1
  fi

  if [ -z "$DISABLE_ADD_ROUTE" ]; then
    inter=$(ip route | grep "default via" | awk '{print $3}')
    if [ "$inter" != "ppp0" ]; then
      route add "$VPN_ADDR" gw "$(ip route | grep 'default via' | awk '{print $3}')"
    fi

    route add default dev ppp0
  fi

  if [ -n "$DNS_IP_LIST" ]; then
    while IFS=',' read -ra ADDRS; do
      for dns in $(echo "${ADDRS[@]}" | rev); do
         if ! grep -q "$dns" /etc/resolv.conf; then
            tmp_file=$(mktemp /tmp/resolv.conf.XXXXXX)
            (echo "nameserver $dns" && cat /etc/resolv.conf) > "$tmp_file" && cat "$tmp_file" > /etc/resolv.conf
            rm -f "$tmp_file"
          fi
      done
    done <<< "$DNS_IP_LIST"
  fi

  echo "[INFO] Ready to use vpn"
  sleep infinity
}

_main() {
  docker_setup_env

  check_require_variable_set

  run
}

_main "$@"