#!/bin/sh
# Run a command on the MiSTer over ssh, or copy a file to it, with the
# password supplied through expect (the stock MiSTer image has no key auth).
#   MISTER_PW=... tools/mister_ssh.sh run  "<remote command>"
#   MISTER_PW=... tools/mister_ssh.sh put  <local file> <remote path>
# MISTER_HOST defaults to 192.168.1.63, MISTER_PW to "1".
HOST=${MISTER_HOST:-192.168.1.63}; PW=${MISTER_PW:-1}
mode=$1; shift
case "$mode" in
  run) set -- ssh -o StrictHostKeyChecking=no "root@$HOST" "$1" ;;
  put) set -- scp -o StrictHostKeyChecking=no "$1" "root@$HOST:$2" ;;
  *) echo "usage: $0 run <cmd> | put <file> <remote>"; exit 2 ;;
esac
tmp=$(mktemp)
cat > "$tmp" <<EOX
set timeout 600
spawn -noecho {*}\$argv
expect {
    -nocase "password" { send "$PW\r"; exp_continue }
    "yes/no" { send "yes\r"; exp_continue }
    "denied" { puts "\nAUTH FAILED"; exit 1 }
    timeout { puts "\nTIMEOUT"; exit 1 }
    eof
}
catch wait result
exit [lindex \$result 3]
EOX
expect "$tmp" "$@"; rc=$?
rm -f "$tmp"; exit $rc
