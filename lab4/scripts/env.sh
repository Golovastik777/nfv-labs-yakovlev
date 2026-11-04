# Переменные и функции из задания 1.3. Подключать: source scripts/env.sh
export STUDENT=yakovlev N=7
export ODL=http://10.104.$N.100:8181
odl_get() { curl -s -u admin:admin "$ODL/rests/data/$1" | jq .; }
put_flow() { # put_flow <номер коммутатора> <id потока> <файл.json>
  curl -s -u admin:admin -X PUT -H "Content-Type: application/json" -d @"$3" \
    -o /dev/null -w "PUT $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
del_flow() { # del_flow <номер коммутатора> <id потока>
  curl -s -u admin:admin -X DELETE -o /dev/null -w "DELETE $2: %{http_code}\n" \
    "$ODL/rests/data/opendaylight-inventory:nodes/node=openflow%3A$1/flow-node-inventory:table=0/flow=$2"
}
# Нет containerlab на хосте (Colima на Mac) — запускаем официальный образ
command -v containerlab >/dev/null || containerlab() {
  docker run --rm --privileged --network host --pid host -e STUDENT -e N \
    -v /var/run/docker.sock:/var/run/docker.sock -v /var/run/netns:/var/run/netns \
    -v /etc/hosts:/etc/hosts -v /var/lib/docker/containers:/var/lib/docker/containers \
    -v "$PWD":"$PWD" -w "$PWD" ghcr.io/srl-labs/clab:latest containerlab "$@"
}
