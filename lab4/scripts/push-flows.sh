#!/usr/bin/env bash
# Применяет потоки из flows/ к ODL через RESTCONF (RFC 8040).
# Использование: scripts/push-flows.sh [-d] [шаблон ...]
#   шаблон — имя файла без .json (= id потока без префикса), можно glob в кавычках: 's*'
#   без шаблонов — все flows/*.json; -d — удалить потоки (DELETE вместо PUT)
# Коммутатор определяется по match.in-port вида "openflow:<dpid>:<порт>".
set -uo pipefail
cd "$(dirname "$0")/.."
: "${STUDENT:?export STUDENT=<фамилия>}"
ODL=${ODL:-http://10.104.${N:?export N=<N>}.100:8181}

mode=PUT
if [ "${1:-}" = "-d" ]; then mode=DELETE; shift; fi
[ $# -eq 0 ] && set -- '*'

rc=0
for pat in "$@"; do
  for f in flows/$pat.json; do
    if [ ! -f "$f" ]; then echo "нет файлов: $f" >&2; rc=1; continue; fi
    name=$(basename "$f" .json)
    id=$(jq -r '."flow-node-inventory:flow"[0].id' "$f")
    if [ "$id" != "$STUDENT-$name" ]; then
      echo "$f: id=$id, ожидается $STUDENT-$name" >&2; rc=1; continue
    fi
    dpid=$(jq -r '."flow-node-inventory:flow"[0].match."in-port"' "$f" | cut -d: -f2)
    url="$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$dpid/flow-node-inventory:table=0/flow=$id"
    if [ "$mode" = PUT ]; then
      code=$(curl -s -u admin:admin -X PUT -H "Content-Type: application/json" -d @"$f" \
        -o /dev/null -w "%{http_code}" "$url")
    else
      code=$(curl -s -u admin:admin -X DELETE -o /dev/null -w "%{http_code}" "$url")
    fi
    printf '%-6s openflow:%s %-26s %s\n' "$mode" "$dpid" "$id" "$code"
    case $code in 200|201|204) ;; *) rc=1 ;; esac
  done
done
exit $rc
